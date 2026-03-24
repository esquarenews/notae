class AgentActionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_agent_action, only: %i[show update approve reject request_changes]
  before_action :load_approval_targets, only: %i[show]

  def index
    authorize AgentAction.new(workspace: @workspace)
    @agent_actions = policy_scope(AgentAction).for_workspace(@workspace).recent_first
    @pending_approval_actions = approver_membership? ? @agent_actions.pending.where.not(user_id: current_user.id) : AgentAction.none
    @needs_revision_actions = @agent_actions.changes_requested.where(user_id: current_user.id)
  end

  def show
    authorize @agent_action
    @review_history = @agent_action.review_history
  end

  def new
    @agent_action = AgentAction.new(
      workspace: @workspace,
      target_system: params[:target_system].presence || "gmail",
      draft_type: params[:draft_type].presence || "email_draft",
      proposed_by: "manual"
    )
    authorize @agent_action
  end

  def create
    @agent_action = build_agent_action_form_object(user: current_user)
    authorize @agent_action

    @agent_action = AgentActions::DraftCreator.new(
      workspace: @workspace,
      actor: current_user,
      attributes: {
        title: agent_action_params.fetch(:title),
        proposed_by: agent_action_params[:proposed_by].presence || "manual",
        target_system: agent_action_params.fetch(:target_system),
        draft_type: agent_action_params.fetch(:draft_type),
        payload_json: draft_payload_from(agent_action_params)
      }
    ).call
    redirect_to agent_action_path(workspace_slug: @workspace.slug, id: @agent_action.id), notice: "Draft action created for review."
  rescue AgentActions::DraftCreator::Error => error
    @agent_action = build_agent_action_form_object
    authorize @agent_action
    flash.now[:alert] = error.message
    render :new, status: :unprocessable_entity
  end

  def update
    authorize @agent_action

    AgentActions::UpdateService.new(
      agent_action: @agent_action,
      actor: current_user,
      attributes: {
        title: agent_action_params.fetch(:title, @agent_action.title),
        payload_json: draft_payload_from(agent_action_params)
      },
      comment: agent_action_params[:revision_comment]
    ).call

    redirect_to agent_action_path(workspace_slug: @workspace.slug, id: @agent_action.id), notice: "Draft updated."
  rescue AgentActions::UpdateService::Error => error
    @review_history = @agent_action.review_history
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  end

  def approve
    authorize @agent_action, :approve?

    AgentActions::ApprovalService.new(
      agent_action: @agent_action,
      actor: current_user,
      comment: approval_params[:decision_comment],
      destination_database_id: approval_params[:destination_database_id],
      destination_calendar_id: approval_params[:destination_calendar_id]
    ).call

    redirect_to agent_action_path(workspace_slug: @workspace.slug, id: @agent_action.id), notice: approval_notice_for(@agent_action.reload)
  rescue AgentActions::ApprovalService::Error => error
    @review_history = @agent_action.review_history
    load_approval_targets
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  end

  def reject
    authorize @agent_action, :reject?

    AgentActions::RejectionService.new(
      agent_action: @agent_action,
      actor: current_user,
      comment: params[:decision_comment]
    ).call

    redirect_to agent_action_path(workspace_slug: @workspace.slug, id: @agent_action.id), notice: "Draft rejected."
  rescue AgentActions::RejectionService::Error => error
    @review_history = @agent_action.review_history
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  end

  def request_changes
    authorize @agent_action, :request_changes?

    AgentActions::RequestChangesService.new(
      agent_action: @agent_action,
      actor: current_user,
      comment: params[:decision_comment]
    ).call

    redirect_to agent_action_path(workspace_slug: @workspace.slug, id: @agent_action.id), notice: "Changes requested."
  rescue AgentActions::RequestChangesService::Error => error
    @review_history = @agent_action.review_history
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_agent_action
    @agent_action = policy_scope(AgentAction).for_workspace(@workspace).find(params[:id])
  end

  def agent_action_params
    params.fetch(:agent_action, {}).permit(
      :title,
      :proposed_by,
      :target_system,
      :draft_type,
      :to_line,
      :cc_line,
      :subject,
      :body,
      :repository,
      :target_reference,
      :project,
      :assignee,
      :due_at,
      :starts_at,
      :ends_at,
      :attendees_line,
      :revision_comment
    )
  end

  def draft_payload_from(params_hash)
    case params_hash[:draft_type].presence || @agent_action&.draft_type
    when "email_draft"
      {
        "to" => split_multiline_values(params_hash[:to_line]),
        "cc" => split_multiline_values(params_hash[:cc_line]),
        "subject" => params_hash[:subject].to_s.strip,
        "body" => params_hash[:body].to_s
      }
    when "github_comment_draft"
      {
        "repository" => params_hash[:repository].to_s.strip,
        "target_reference" => params_hash[:target_reference].to_s.strip,
        "body" => params_hash[:body].to_s
      }
    when "calendar_hold"
      {
        "title" => params_hash[:title].to_s.strip,
        "starts_at" => params_hash[:starts_at].to_s.strip,
        "ends_at" => params_hash[:ends_at].to_s.strip,
        "attendees" => split_multiline_values(params_hash[:attendees_line]),
        "body" => params_hash[:body].to_s
      }
    when "nota_draft"
      {
        "title" => params_hash[:title].to_s.strip,
        "body" => params_hash[:body].to_s
      }
    else
      {
        "project" => params_hash[:project].to_s.strip,
        "assignee" => params_hash[:assignee].to_s.strip,
        "due_at" => params_hash[:due_at].to_s.strip,
        "title" => params_hash[:title].to_s.strip,
        "body" => params_hash[:body].to_s
      }
    end
  end

  def split_multiline_values(raw)
    raw.to_s.split(/\r?\n|,/).map(&:strip).reject(&:blank?).uniq
  end

  def build_agent_action_form_object(user: nil)
    AgentAction.new(
      agent_action_identity_attributes.merge(
        workspace: @workspace,
        user: user,
        payload_json: draft_payload_from(agent_action_params)
      )
    )
  end

  def agent_action_identity_attributes
    {
      title: agent_action_params[:title],
      proposed_by: agent_action_params[:proposed_by].presence || "manual",
      target_system: agent_action_params[:target_system].presence || "gmail",
      draft_type: agent_action_params[:draft_type].presence || "email_draft"
    }
  end

  def approver_membership?
    Membership.find_by(user_id: current_user.id, workspace_id: @workspace.id)&.admin_or_owner?
  end

  def approval_params
    params.permit(:decision_comment, :destination_database_id, :destination_calendar_id)
  end

  def load_approval_targets
    @approval_target_databases =
      if @agent_action&.draft_type == "task_ticket"
        policy_scope(Database).for_workspace(@workspace).active.order(:name)
      else
        Database.none
      end

    @approval_target_calendars =
      if @agent_action&.draft_type == "calendar_hold"
        policy_scope(KalendariumCalendar).for_workspace(@workspace).enabled.user_writable.order(:name)
      else
        KalendariumCalendar.none
      end
  end

  def approval_notice_for(agent_action)
    return "Draft approved in dry-run mode." if agent_action.dry_run?

    agent_action.result_json["summary"].presence || "Draft approved and saved to Notae."
  end
end

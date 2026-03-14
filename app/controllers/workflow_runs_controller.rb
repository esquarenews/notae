class WorkflowRunsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_workflow_run, only: :show

  def index
    authorize WorkflowRun.new(workspace: @workspace, user: current_user, workflow_kind: WorkflowRun::KIND_CREATE_NOTA, queued_at: Time.current)
    @workflow_runs = policy_scope(WorkflowRun).for_workspace(@workspace).recent_first.limit(100)
    @queued_workflows = @workflow_runs.where(status: [ WorkflowRun::STATUS_QUEUED, WorkflowRun::STATUS_RUNNING ])
    @failed_workflows = @workflow_runs.failed.limit(12)
  end

  def show
    authorize @workflow_run
  end

  def new
    @workflow_run = WorkflowRun.new(
      workspace: @workspace,
      user: current_user,
      workflow_kind: params[:workflow_kind].presence || WorkflowRun::KIND_CREATE_NOTA,
      queued_at: Time.current
    )
    authorize @workflow_run
    load_workflow_targets
  end

  def create
    @workflow_run = WorkflowRun.new(
      workspace: @workspace,
      user: current_user,
      workflow_kind: workflow_params[:workflow_kind],
      queued_at: Time.current
    )
    authorize @workflow_run

    workflow_run = Workflows::LaunchService.new(
      workspace: @workspace,
      actor: current_user,
      workflow_kind: workflow_params.fetch(:workflow_kind),
      input: workflow_input_payload,
      trigger_source: "manual",
      confidence_score: workflow_params[:confidence_score].presence || 1.0
    ).call

    redirect_to workflow_run_path(workspace_slug: @workspace.slug, id: workflow_run.id), notice: "Workflow queued."
  rescue Workflows::LaunchService::Error => e
    load_workflow_targets
    flash.now[:alert] = e.message
    render :new, status: :unprocessable_entity
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_workflow_run
    @workflow_run = policy_scope(WorkflowRun).for_workspace(@workspace).find(params[:id])
  end

  def workflow_params
    params.fetch(:workflow_run, {}).permit(
      :workflow_kind,
      :confidence_score,
      :title,
      :body,
      :database_id,
      :owner_name,
      :due_on,
      :kalendarium_calendar_id,
      :starts_at_local,
      :ends_at_local,
      :description,
      :location
    )
  end

  def workflow_input_payload
    workflow_params.except(:workflow_kind, :confidence_score).to_h
  end

  def load_workflow_targets
    @task_databases = policy_scope(Database).for_workspace(@workspace).active.order(updated_at: :desc).limit(24)
    @internal_calendars = policy_scope(KalendariumCalendar).for_workspace(@workspace).where(source_kind: %w[local project]).order(:name)
  end
end

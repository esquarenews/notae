class KalendariumProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_project, only: %i[update archive unarchive destroy]

  def create
    @project = KalendariumProject.new(project_params.merge(workspace: @workspace, created_by: current_user))
    apply_linked_nota_action!(@project, project_params[:linked_page_action])
    authorize @project

    ActiveRecord::Base.transaction do
      if @project.save
        calendar = KalendariumCalendar.create!(
          workspace: @workspace,
          created_by: current_user,
          name: @project.name,
          color_hex: @project.color_hex,
          source_kind: "project",
          enabled: true
        )
        @project.update!(kalendarium_calendar: calendar)
      end
    end

    if @project.persisted?
      redirect_to kalendarium_path(kalendarium_redirect_params.merge(view: "project", project_id: @project.id)), notice: "Project created."
    else
      redirect_to kalendarium_path(kalendarium_redirect_params.merge(view: "project")), alert: @project.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to kalendarium_path(kalendarium_redirect_params.merge(view: "project")), alert: error.record.errors.full_messages.to_sentence
  end

  def update
    authorize @project

    @project.assign_attributes(project_params.except(:linked_page_action))
    apply_linked_nota_action!(@project, project_params[:linked_page_action])

    if @project.save
      if @project.kalendarium_calendar.present?
        @project.kalendarium_calendar.update(name: @project.name, color_hex: @project.color_hex)
      end
      redirect_to kalendarium_path(kalendarium_redirect_params.merge(view: "project", project_id: @project.id)), notice: "Project updated."
    else
      redirect_to kalendarium_path(kalendarium_redirect_params.merge(view: "project", project_id: @project.id)), alert: @project.errors.full_messages.to_sentence
    end
  end

  def archive
    authorize @project, :update?

    ActiveRecord::Base.transaction do
      @project.update!(archived_at: Time.current)
      @project.kalendarium_calendar&.update!(enabled: false)
    end

    redirect_to kalendarium_path(kalendarium_redirect_params), notice: "Project archived."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to kalendarium_path(kalendarium_redirect_params), alert: error.record.errors.full_messages.to_sentence
  end

  def unarchive
    authorize @project, :update?

    ActiveRecord::Base.transaction do
      @project.update!(archived_at: nil)
      @project.kalendarium_calendar&.update!(enabled: true)
    end

    redirect_to kalendarium_path(kalendarium_redirect_params.merge(view: "project", project_id: @project.id)), notice: "Project restored."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to kalendarium_path(kalendarium_redirect_params), alert: error.record.errors.full_messages.to_sentence
  end

  def destroy
    authorize @project, :update?

    project_name = @project.name
    calendar = @project.kalendarium_calendar
    ActiveRecord::Base.transaction do
      calendar&.update!(enabled: false)
      @project.destroy!
    end

    redirect_to kalendarium_path(kalendarium_redirect_params), notice: "#{project_name} deleted."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to kalendarium_path(kalendarium_redirect_params), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_project
    @project = policy_scope(KalendariumProject).for_workspace(@workspace).find(params[:id])
  end

  def project_params
    params.require(:kalendarium_project).permit(:name, :slug, :color_hex, :linked_page_id, :linked_page_action)
  end

  def kalendarium_redirect_params
    {
      workspace_slug: @workspace.slug,
      view: params[:view].presence || "project",
      date: params[:date].presence || Date.current
    }.tap do |redirect_params|
      calendar_ids = Array(params[:calendar_ids]).map(&:to_s).reject(&:blank?)
      redirect_params[:calendar_ids] = calendar_ids if calendar_ids.any?
      time_zones = Array(params[:tz]).map(&:to_s).reject(&:blank?)
      redirect_params[:tz] = time_zones if time_zones.any?
      redirect_params[:year_daily_events] = "1" if ActiveModel::Type::Boolean.new.cast(params[:year_daily_events])
      redirect_params[:project_scope_id] = params[:project_scope_id].to_s.presence if params[:project_scope_id].present?
      redirect_params[:window_start] = params[:window_start].to_s.presence if params[:window_start].present?
      redirect_params[:embedded] = "1" if params[:embedded].to_s == "1"
      redirect_params[:task_row_id] = params[:task_row_id].to_s.presence if params[:task_row_id].present?
    end
  end

  def apply_linked_nota_action!(project, action)
    case action.to_s
    when "create_page"
      page = @workspace.pages.new(title: [ project.name.presence || "Kalendarium project", "overview" ].join(" "), created_by: current_user)
      return unless policy(page).create? && page.save

      project.linked_page = page
    when "clear"
      project.linked_page = nil
    end
  end
end

class KalendariumProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_project, only: :update

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
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: "project", project_id: @project.id), notice: "Project created."
    else
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: "project"), alert: @project.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: "project"), alert: error.record.errors.full_messages.to_sentence
  end

  def update
    authorize @project

    @project.assign_attributes(project_params.except(:linked_page_action))
    apply_linked_nota_action!(@project, project_params[:linked_page_action])

    if @project.save
      if @project.kalendarium_calendar.present?
        @project.kalendarium_calendar.update(name: @project.name, color_hex: @project.color_hex)
      end
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: "project", project_id: @project.id), notice: "Project updated."
    else
      redirect_to kalendarium_path(workspace_slug: @workspace.slug, view: "project", project_id: @project.id), alert: @project.errors.full_messages.to_sentence
    end
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

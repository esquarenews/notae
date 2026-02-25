class PageTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_page, only: :create
  before_action :set_page_template, only: :instantiate

  def create
    template_record = PageTemplate.new(
      workspace: @workspace,
      page: @page,
      created_by: current_user,
      name: template_name,
      snapshot_json: {}
    )
    authorize template_record

    PageTemplates::CreateFromPageService.call(
      page: @page,
      created_by: current_user,
      name: template_name
    )

    redirect_to page_redirect_path(@page.id), notice: "Template saved."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to page_redirect_path(@page.id), alert: error.record.errors.full_messages.to_sentence
  end

  def instantiate
    authorize @page_template, :instantiate?

    page = PageTemplates::InstantiateService.call(
      template: @page_template,
      workspace: @workspace,
      created_by: current_user,
      title: params.dig(:page_template, :title)
    )

    redirect_to page_redirect_path(page.id), notice: "Page created from template."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to workspace_path(@workspace.slug), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_page
    @page = policy_scope(Page).for_workspace(@workspace).find(params[:id])
    authorize @page, :show?
  end

  def set_page_template
    @page_template = policy_scope(PageTemplate).for_workspace(@workspace).find(params[:id])
  end

  def template_name
    params.dig(:page_template, :name).to_s
  end

  def page_redirect_path(page_id)
    route_params = { workspace_slug: @workspace.slug, id: page_id }
    route_params[:options_menu] = "open" if params[:options_menu].to_s == "open"
    page_path(route_params)
  end
end

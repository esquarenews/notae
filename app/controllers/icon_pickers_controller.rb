class IconPickersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    icon_target = resolve_icon_target
    authorize icon_target.record, :update?

    render partial: "shared/icon_picker_panel_body",
           locals: {
             update_url: icon_target.update_url,
             workspace: @workspace,
             param_key: icon_target.param_key,
             current_icon: icon_target.record.icon,
             fallback: icon_target.fallback,
             return_to: params[:return_to].presence
           }
  end

  private

  IconTarget = Struct.new(:record, :update_url, :param_key, :fallback, keyword_init: true)

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def resolve_icon_target
    case params[:target_type].to_s
    when "page"
      page_icon_target
    when "database"
      database_icon_target
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def page_icon_target
    page = policy_scope(Page).for_workspace(@workspace).find(params[:page_id])

    IconTarget.new(
      record: page,
      update_url: page_path(workspace_slug: @workspace.slug, id: page.id),
      param_key: :page,
      fallback: fallback_icon(default: "📄")
    )
  end

  def database_icon_target
    database = policy_scope(Database).for_workspace(@workspace).find(params[:database_id])

    IconTarget.new(
      record: database,
      update_url: database_path(workspace_slug: @workspace.slug, id: database.id, view_id: params[:view_id].presence),
      param_key: :database,
      fallback: fallback_icon(default: "🗃️")
    )
  end

  def fallback_icon(default:)
    params[:fallback].presence || default
  end
end

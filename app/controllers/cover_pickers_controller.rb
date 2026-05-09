class CoverPickersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    cover_target = resolve_cover_target
    authorize cover_target.record, :update?

    render partial: "shared/cover_picker_panel_body",
           locals: {
             update_url: cover_target.update_url,
             workspace: @workspace,
             param_key: cover_target.param_key,
             selected_cover_key: cover_target.record.cover_preset_key,
             cover_record: cover_target.record,
             unsplash_url: workspace_cover_unsplash_path(workspace_slug: @workspace.slug),
             embedded: truthy_param?(:embedded),
             allow_remove: allow_remove?(cover_target.record),
             remove_label: params[:remove_label].presence || "Remove",
             return_to: params[:return_to].presence
           }
  end

  private

  CoverTarget = Struct.new(:record, :update_url, :param_key, keyword_init: true)

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def resolve_cover_target
    case params[:target_type].to_s
    when "page"
      page_cover_target
    when "database"
      database_cover_target
    else
      raise ActiveRecord::RecordNotFound
    end
  end

  def page_cover_target
    page = policy_scope(Page).for_workspace(@workspace).find(params[:page_id])

    CoverTarget.new(
      record: page,
      update_url: page_path(workspace_slug: @workspace.slug, id: page.id),
      param_key: :page
    )
  end

  def database_cover_target
    database = policy_scope(Database).for_workspace(@workspace).find(params[:database_id])

    CoverTarget.new(
      record: database,
      update_url: database_path(workspace_slug: @workspace.slug, id: database.id, view_id: params[:view_id].presence),
      param_key: :database
    )
  end

  def allow_remove?(record)
    return truthy_param?(:allow_remove) if params.key?(:allow_remove)

    record.cover?
  end

  def truthy_param?(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end
end

class PwaController < ApplicationController
  before_action :authenticate_user!, only: :launch
  skip_forgery_protection only: :service_worker
  skip_after_action :verify_pundit_authorization
  skip_after_action :verify_same_origin_request, only: :service_worker

  def launch
    workspace = last_workspace_for_pwa_launch || first_accessible_workspace

    if workspace.present?
      redirect_to workspace_path(workspace.slug)
    else
      redirect_to new_workspace_path
    end
  end

  def manifest
    expires_now
    render "pwa/manifest",
           formats: :json,
           content_type: "application/manifest+json",
           layout: false
  end

  def service_worker
    expires_now
    response.headers["Service-Worker-Allowed"] = "/"

    render "pwa/service-worker",
           formats: :js,
           content_type: "application/javascript",
           layout: false
  end

  def offline
    render :offline
  end

  private

  def last_workspace_for_pwa_launch
    slug = session["notae_last_workspace_slug"].to_s.strip
    return if slug.blank?

    workspace_scope.find_by(slug: slug)
  end

  def first_accessible_workspace
    workspace_scope.first
  end

  def workspace_scope
    policy_scope(Workspace)
      .where.not(slug: [ nil, "" ])
      .order(:created_at)
  end
end

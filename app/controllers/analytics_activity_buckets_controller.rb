class AnalyticsActivityBucketsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def create
    authorize current_user, :update?
    authorize @workspace, :show? if @workspace.present?

    Analytics::ActivityRecorder.call(
      user: current_user,
      workspace: @workspace,
      surface: activity_params[:surface],
      bucket_started_at: activity_params[:bucket_started_at],
      duration_seconds: activity_params[:duration_seconds],
      sample_id: activity_params[:sample_id]
    )

    head :no_content
  rescue Analytics::ActivityRecorder::InvalidSample
    head :unprocessable_content
  end

  private

  def set_workspace
    slug = activity_params[:workspace_slug].to_s.strip
    @workspace = policy_scope(Workspace).find_by!(slug: slug) if slug.present?
  end

  def activity_params
    @activity_params ||= params.fetch(:activity, {}).permit(
      :workspace_slug,
      :surface,
      :bucket_started_at,
      :duration_seconds,
      :sample_id
    )
  end
end

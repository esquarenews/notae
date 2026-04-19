class AccountSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace
  before_action :set_user

  def show
    authorize @workspace, :show?
    authorize @user, :update?
  end

  def update
    authorize @workspace, :show?
    authorize @user, :update?

    remove_avatar_if_requested!

    if @user.update(account_params)
      redirect_to workspace_account_settings_path(workspace_slug: @workspace.slug), notice: "Account settings updated."
    else
      redirect_to workspace_account_settings_path(workspace_slug: @workspace.slug), alert: @user.errors.full_messages.to_sentence
    end
  end

  def request_deletion
    authorize @workspace, :show?
    authorize @user, :update?

    @user.account_deletion_recipients.each do |recipient|
      AccountSettingsMailer.with(user: @user, workspace: @workspace, recipient: recipient).account_deletion_requested.deliver_now
    end

    redirect_to workspace_account_settings_path(workspace_slug: @workspace.slug),
                notice: "Account deletion confirmation sent to #{helpers.to_sentence(@user.account_deletion_recipients)}."
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def set_user
    @user = policy_scope(User).find(current_user.id)
  end

  def account_params
    params.fetch(:user, {}).permit(:avatar, :full_name, :backup_email, :personal_bio)
  end

  def remove_avatar_if_requested!
    return unless ActiveModel::Type::Boolean.new.cast(params.dig(:user, :remove_avatar))
    return unless @user.avatar.attached?

    @user.avatar.purge
  end
end

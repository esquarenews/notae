class EpistulariumController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  def show
    authorize @workspace, :show?

    @accounts = policy_scope(EpistulariumAccount).for_workspace(@workspace).includes(:owner).order(updated_at: :desc, created_at: :desc)
    @selected_account = resolve_selected_account
    @selected_mailbox = params[:mailbox].to_s == "sent" ? "sent" : "inbox"
    queue_due_syncs(@accounts)
    @messages = resolve_messages
    @selected_message = resolve_selected_message
    @thread_messages = resolve_thread_messages
    @message_counts_by_account = resolve_message_counts
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def queue_due_syncs(accounts)
    Epistularium::DueSyncScheduler.new(accounts: accounts).call
  end

  def resolve_selected_account
    requested_id = params[:account_id].presence
    return @accounts.find { |account| account.id.to_s == requested_id.to_s } if requested_id.present?

    @accounts.first
  end

  def resolve_messages
    return EpistulariumMessage.none if @selected_account.blank?

    policy_scope(EpistulariumMessage)
      .for_workspace(@workspace)
      .for_account(@selected_account)
      .for_mailbox(@selected_mailbox)
      .recent_first_for_mailbox(@selected_mailbox)
      .limit(120)
  end

  def resolve_selected_message
    requested_id = params[:message_id].presence
    return @messages.first if requested_id.blank?

    @messages.find { |message| message.id.to_s == requested_id.to_s } ||
      policy_scope(EpistulariumMessage).for_workspace(@workspace).find_by(id: requested_id)
  end

  def resolve_thread_messages
    return [] if @selected_message.blank? || @selected_account.blank?

    if @selected_message.provider_thread_id.present?
      policy_scope(EpistulariumMessage)
        .for_workspace(@workspace)
        .for_account(@selected_account)
        .where(provider_thread_id: @selected_message.provider_thread_id)
        .recent_first
        .limit(20)
        .to_a
    elsif @selected_message.thread_key.present?
      policy_scope(EpistulariumMessage)
        .for_workspace(@workspace)
        .for_account(@selected_account)
        .where(thread_key: @selected_message.thread_key)
        .recent_first
        .limit(20)
        .to_a
    else
      [ @selected_message ]
    end
  end

  def resolve_message_counts
    return {} if @accounts.empty?

    counts = policy_scope(EpistulariumMessage)
             .for_workspace(@workspace)
             .where(epistularium_account_id: @accounts.map(&:id))
             .group(:epistularium_account_id, :mailbox)
             .count

    @accounts.each_with_object({}) do |account, mapping|
      mapping[account.id] = {
        "inbox" => counts.fetch([ account.id, "inbox" ], 0),
        "sent" => counts.fetch([ account.id, "sent" ], 0)
      }
    end
  end
end

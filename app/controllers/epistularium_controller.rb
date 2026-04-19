require "digest"

class EpistulariumController < ApplicationController
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  track_request_performance_for :show

  def show
    authorize @workspace, :show?

    @accounts = policy_scope(EpistulariumAccount).for_workspace(@workspace).includes(:owner).order(updated_at: :desc, created_at: :desc)
    @selected_account = resolve_selected_account
    @selected_mailbox = params[:mailbox].to_s == "sent" ? "sent" : "inbox"
    queue_due_syncs(@accounts) if queue_due_syncs_for_request?
    @messages = resolve_messages
    @selected_message = resolve_selected_message
    @thread_messages = resolve_thread_messages
    @message_counts_by_account = resolve_message_counts
    @epistularium_poll_cursor = build_poll_cursor

    respond_to do |format|
      format.html
      format.json do
        render json: {
          html: render_to_string(partial: "epistularium/grid", formats: [ :html ]),
          cursor: @epistularium_poll_cursor,
          active: @accounts.any?
        }
      end
    end
  end

  private

  def set_workspace
    @workspace = policy_scope(Workspace).find_by!(slug: params[:workspace_slug])
  end

  def queue_due_syncs(accounts)
    Epistularium::DueSyncScheduler.new(accounts: accounts).call
  end

  def queue_due_syncs_for_request?
    request.format.html?
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

  def build_poll_cursor
    parts = []

    parts.concat(@accounts.map { |account| [ account.id, account.updated_at&.utc&.iso8601, account.status, account.last_synced_at&.utc&.iso8601 ].join(":") })
    parts.concat(
      @message_counts_by_account
        .sort_by { |account_id, _counts| account_id.to_i }
        .flat_map do |account_id, counts|
          [ "account:#{account_id}:inbox:#{counts.fetch('inbox', 0)}", "account:#{account_id}:sent:#{counts.fetch('sent', 0)}" ]
        end
    )
    parts.concat(@messages.map { |message| [ message.id, message.updated_at&.utc&.iso8601, message.primary_timestamp&.utc&.iso8601 ].join(":") })
    parts.concat(@thread_messages.map { |message| [ "thread", message.id, message.updated_at&.utc&.iso8601 ].join(":") })
    parts << "selected-account:#{@selected_account&.id}"
    parts << "selected-mailbox:#{@selected_mailbox}"
    parts << "selected-message:#{@selected_message&.id}"

    Digest::SHA256.hexdigest(parts.join("|"))
  end
end

require "digest"

class EpistulariumController < ApplicationController
  include RequestPerformanceInstrumentation

  before_action :authenticate_user!
  before_action :set_workspace
  track_request_performance_for :show

  def show
    authorize @workspace, :show?

    @accounts = policy_scope(EpistulariumAccount).visible_in_workspace(@workspace).includes(:owner).order(updated_at: :desc, created_at: :desc)
    @selected_account = resolve_selected_account
    @selected_mailbox = params[:mailbox].to_s == "sent" ? "sent" : "inbox"
    queue_due_syncs(@accounts) if queue_due_syncs_for_request?
    @message_revisions = resolve_message_revisions
    @message_counts_by_account = resolve_message_counts
    @epistularium_poll_cursor = build_poll_cursor

    if unchanged_poll_request?
      render json: {
        cursor: @epistularium_poll_cursor,
        active: @accounts.any?,
        unchanged: true
      }
      return
    end

    @messages = resolve_messages
    @selected_message = resolve_selected_message
    @thread_messages = resolve_thread_messages

    respond_to do |format|
      format.html
      format.json do
        render json: {
          html: render_to_string(partial: "epistularium/grid", formats: [ :html ]),
          cursor: @epistularium_poll_cursor,
          active: @accounts.any?,
          unchanged: false
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
      .for_account(@selected_account)
      .for_mailbox(@selected_mailbox)
      .recent_first_for_mailbox(@selected_mailbox)
      .limit(120)
  end

  def resolve_selected_message
    requested_id = params[:message_id].presence
    return @messages.first if requested_id.blank?

    @messages.find { |message| message.id.to_s == requested_id.to_s } ||
      policy_scope(EpistulariumMessage).for_account(@selected_account).find_by(id: requested_id)
  end

  def resolve_thread_messages
    return [] if @selected_message.blank? || @selected_account.blank?

    if @selected_message.provider_thread_id.present?
      policy_scope(EpistulariumMessage)
        .for_account(@selected_account)
        .where(provider_thread_id: @selected_message.provider_thread_id)
        .recent_first
        .limit(20)
        .to_a
    elsif @selected_message.thread_key.present?
      policy_scope(EpistulariumMessage)
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

    @accounts.each_with_object({}) do |account, mapping|
      mapping[account.id] = {
        "inbox" => @message_revisions.dig([ account.id, "inbox" ], :count).to_i,
        "sent" => @message_revisions.dig([ account.id, "sent" ], :count).to_i
      }
    end
  end

  def resolve_message_revisions
    return {} if @accounts.empty?

    policy_scope(EpistulariumMessage)
      .where(epistularium_account_id: @accounts.map(&:id))
      .group(:epistularium_account_id, :mailbox)
      .pluck(
        :epistularium_account_id,
        :mailbox,
        Arel.sql("COUNT(*)"),
        Arel.sql("MAX(epistularium_messages.updated_at)")
      )
      .each_with_object({}) do |(account_id, mailbox, count, updated_at), revisions|
        revisions[[ account_id, mailbox ]] = { count: count.to_i, updated_at: updated_at }
      end
  end

  def build_poll_cursor
    parts = []

    parts.concat(@accounts.map { |account| [ account.id, precise_timestamp(account.updated_at), account.status, precise_timestamp(account.last_synced_at) ].join(":") })
    parts.concat(
      @message_revisions
        .sort_by { |(account_id, mailbox), _revision| [ account_id.to_s, mailbox.to_s ] }
        .map do |(account_id, mailbox), revision|
          [
            "account",
            account_id,
            mailbox,
            revision.fetch(:count),
            precise_timestamp(revision.fetch(:updated_at))
          ].join(":")
        end
    )
    parts << "selected-account:#{@selected_account&.id}"
    parts << "selected-mailbox:#{@selected_mailbox}"
    parts << "selected-message:#{params[:message_id].presence || 'latest'}"

    Digest::SHA256.hexdigest(parts.join("|"))
  end

  def unchanged_poll_request?
    request.format.json? &&
      params[:poll_cursor].present? &&
      params[:poll_cursor].to_s == @epistularium_poll_cursor
  end

  def precise_timestamp(value)
    value&.utc&.iso8601(6)
  end
end

class PageChannel < ApplicationCable::Channel
  PRESENCE_TIMEOUT = 45.seconds
  EDITING_TIMEOUT = 8.seconds
  HEARTBEAT_THROTTLE_WINDOW = 20.seconds

  def subscribed
    @workspace = WorkspacePolicy::Scope.new(connection.current_user, Workspace).resolve.find_by!(slug: params[:workspace_slug])
    @page = PagePolicy::Scope.new(connection.current_user, Page).resolve.where(workspace_id: @workspace.id).find(params[:page_id])
    @session_token = SecureRandom.uuid

    stream_from stream_name
    touch_presence!
    broadcast_snapshots!
  rescue ActiveRecord::RecordNotFound
    reject
  end

  def unsubscribed
    return if @session_token.blank? || @page.blank?

    PagePresence.where(session_token: @session_token).delete_all
    cleanup_stale_rows!
    broadcast_snapshots!
  end

  def heartbeat(_data = {})
    return if @page.blank?
    return if heartbeat_throttled?

    touch_presence!(run_cleanup: false)
  end

  def editing_start(data)
    return if @page.blank?

    block_id = data["block_id"].presence
    return if block_id.blank?

    touch_presence!(editing_block_id: block_id, run_cleanup: false)
    broadcast_editing_snapshot!
  end

  def editing_stop(_data = {})
    return if @page.blank?

    touch_presence!(editing_block_id: nil, run_cleanup: false)
    broadcast_editing_snapshot!
  end

  private

  def stream_name
    "page:#{@page.id}:collaboration"
  end

  def heartbeat_throttled?
    now = Time.current
    if @last_heartbeat_at.present? && now - @last_heartbeat_at < HEARTBEAT_THROTTLE_WINDOW
      true
    else
      @last_heartbeat_at = now
      false
    end
  end

  def touch_presence!(editing_block_id: :keep, run_cleanup: true)
    cleaned_up = run_cleanup ? cleanup_stale_rows! : false

    now = Time.current
    record = PagePresence.find_or_initialize_by(session_token: @session_token)
    record.workspace_id = @workspace.id
    record.page_id = @page.id
    record.user_id = connection.current_user.id
    should_persist_last_seen = record.new_record? || record.last_seen_at.blank? || record.last_seen_at < 60.seconds.ago

    if editing_block_id != :keep
      record.editing_block_id = editing_block_id
      record.editing_seen_at = editing_block_id.present? ? now : nil
    end

    if should_persist_last_seen || editing_block_id != :keep
      record.last_seen_at = now
      record.save!
    end

    cleaned_up
  end

  def cleanup_stale_rows!
    scope = PagePresence.for_page(@page.id)
    deleted_rows = scope.where(PagePresence.arel_table[:last_seen_at].lt(PRESENCE_TIMEOUT.ago)).delete_all
    cleared_editing_rows = scope.where.not(editing_block_id: nil)
                                .where(PagePresence.arel_table[:editing_seen_at].lt(EDITING_TIMEOUT.ago))
                                .update_all(editing_block_id: nil, editing_seen_at: nil)
    deleted_rows.positive? || cleared_editing_rows.positive?
  end

  def broadcast_snapshots!
    ActionCable.server.broadcast(stream_name, { type: "presence", users: presence_users_payload })
    broadcast_editing_snapshot!
  end

  def broadcast_editing_snapshot!
    ActionCable.server.broadcast(stream_name, { type: "editing", entries: editing_entries_payload })
  end

  def presence_users_payload
    rows = PagePresence.for_page(@page.id).active_since(PRESENCE_TIMEOUT.ago).includes(:user).to_a
    rows.map(&:user).uniq(&:id).sort_by(&:email).map do |user|
      {
        id: user.id,
        email: user.email
      }
    end
  end

  def editing_entries_payload
    rows = PagePresence.for_page(@page.id).editing_active_since(EDITING_TIMEOUT.ago).includes(:user).to_a
    rows.uniq { |row| [ row.user_id, row.editing_block_id ] }.map do |row|
      {
        block_id: row.editing_block_id,
        user: {
          id: row.user.id,
          email: row.user.email
        }
      }
    end
  end
end

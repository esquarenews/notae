require "set"

module Documents
  class WorkspaceMoveService
    class Error < StandardError; end

    class << self
      def call(record:, target_workspace:, actor:)
        new(record:, target_workspace:, actor:).call
      end
    end

    def initialize(record:, target_workspace:, actor:)
      @record = record
      @source_workspace = record.workspace
      @target_workspace = target_workspace
      @actor = actor
    end

    def call
      raise Error, "Choose a different workspace." if source_workspace.id == target_workspace.id

      ActiveRecord::Base.transaction do
        page_ids, database_ids = document_graph
        move_pages!(page_ids)
        move_databases!(database_ids, moved_page_ids: page_ids)
        log_move!(page_ids:, database_ids:)
      end

      record.reload
    end

    private

    attr_reader :record, :source_workspace, :target_workspace, :actor

    def document_graph
      seed_page_ids = []
      seed_database_ids = []

      case record
      when Page
        seed_page_ids = [ record.id ]
      when Database
        seed_database_ids = [ record.id ]
        seed_page_ids = [ record.linked_page_id ].compact
      else
        raise Error, "Unsupported document type."
      end

      collect_document_graph(seed_page_ids:, seed_database_ids:)
    end

    def collect_document_graph(seed_page_ids:, seed_database_ids:)
      page_ids = collect_page_tree_ids(seed_page_ids)
      database_ids = seed_database_ids.compact.map(&:to_s).uniq

      loop do
        previous_page_count = page_ids.size
        previous_database_count = database_ids.size

        if page_ids.any?
          database_ids |= Database.where(linked_page_id: page_ids).pluck(:id).map(&:to_s)
        end

        linked_page_ids = Database.where(id: database_ids).where.not(linked_page_id: nil).pluck(:linked_page_id)
        page_ids |= collect_page_tree_ids(linked_page_ids)

        break if page_ids.size == previous_page_count && database_ids.size == previous_database_count
      end

      [ page_ids, database_ids ]
    end

    def collect_page_tree_ids(seed_ids)
      ids = seed_ids.compact.map(&:to_s).uniq
      frontier = ids.dup

      until frontier.empty?
        child_ids = Page.where(parent_page_id: frontier).pluck(:id).map(&:to_s)
        new_ids = child_ids - ids
        ids |= new_ids
        frontier = new_ids
      end

      ids
    end

    def move_pages!(page_ids)
      return if page_ids.empty?

      now = Time.current
      page_scope = Page.where(id: page_ids)
      block_ids = Block.where(page_id: page_ids).pluck(:id)
      target_member_user_ids = target_workspace.memberships.select(:user_id)

      page_scope.where.not(parent_page_id: page_ids).update_all(parent_page_id: nil)
      PageLink.where(source_page_id: page_ids, target_page_id: page_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      PageLink.where(source_page_id: page_ids).where.not(target_page_id: page_ids).delete_all
      PageLink.where(target_page_id: page_ids).where.not(source_page_id: page_ids).delete_all

      PageShare.where(page_id: page_ids).where.not(user_id: target_member_user_ids).delete_all
      move_favorites!("Page", page_ids, target_member_user_ids, now:)

      page_scope.update_all(workspace_id: target_workspace.id, updated_at: now)
      Block.where(id: block_ids).update_all(workspace_id: target_workspace.id, updated_at: now)

      page_comment_ids = Comment.where(commentable_type: "Page", commentable_id: page_ids).pluck(:id)
      block_comment_ids = Comment.where(commentable_type: "Block", commentable_id: block_ids).pluck(:id)
      move_comments!(page_comment_ids + block_comment_ids, now:)

      share_link_ids = ShareLink.where(page_id: page_ids).pluck(:id)
      ShareLink.where(id: share_link_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      ShareLinkView.where(share_link_id: share_link_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      PageExport.where(page_id: page_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      PagePresence.where(page_id: page_ids).delete_all
      SearchChunk.where(page_id: page_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      KalendariumEvent.where(linked_page_id: page_ids).update_all(linked_page_id: nil, updated_at: now)
      KalendariumProject.where(linked_page_id: page_ids).update_all(linked_page_id: nil, updated_at: now)
      move_page_templates!(page_ids)
    end

    def move_databases!(database_ids, moved_page_ids:)
      return if database_ids.empty?

      now = Time.current
      row_ids = DbRow.where(database_id: database_ids).pluck(:id)
      property_ids = DbProperty.where(database_id: database_ids).pluck(:id)
      target_member_user_ids = target_workspace.memberships.select(:user_id)

      DbRow.where(id: row_ids).where.not(linked_page_id: moved_page_ids).update_all(linked_page_id: nil, updated_at: now)
      DatabaseShare.where(database_id: database_ids).where.not(user_id: target_member_user_ids).delete_all
      move_favorites!("Database", database_ids, target_member_user_ids, now:)
      move_database_records!(database_ids, now:)

      DbProperty.where(id: property_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      DbRow.where(id: row_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      DbCell.where(db_row_id: row_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      DatabaseView.where(database_id: database_ids).update_all(workspace_id: target_workspace.id, updated_at: now)

      database_comment_ids = Comment.where(commentable_type: "Database", commentable_id: database_ids).pluck(:id)
      move_comments!(database_comment_ids, now:)

      DatabaseShareLink.where(database_id: database_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      DatabaseTemplate.where(database_id: database_ids).find_each do |template|
        template.update!(workspace: target_workspace, name: unique_template_name(DatabaseTemplate, template.name))
      end
      SearchChunk.where(database_id: database_ids).or(SearchChunk.where(db_row_id: row_ids)).update_all(workspace_id: target_workspace.id, updated_at: now)
      KalendariumEvent.where(linked_db_row_id: row_ids).update_all(linked_db_row_id: nil, updated_at: now)
    end

    def move_database_records!(database_ids, now:)
      used_names = Database.where(workspace_id: target_workspace.id).where.not(id: database_ids).pluck(:name).map { |name| name.to_s.downcase }.to_set

      Database.where(id: database_ids).find_each do |database|
        name = unique_database_name(database.name, used_names)
        used_names << name.downcase
        database_template_id = database.database_template&.workspace_id == target_workspace.id ? database.database_template_id : nil
        database.update_columns(
          workspace_id: target_workspace.id,
          database_template_id: database_template_id,
          name: name,
          updated_at: now
        )
      end
    end

    def move_comments!(comment_ids, now:)
      return if comment_ids.empty?

      Comment.where(id: comment_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
      Notification.where(notifiable_type: "Comment", notifiable_id: comment_ids).update_all(workspace_id: target_workspace.id, updated_at: now)
    end

    def move_favorites!(favoritable_type, favoritable_ids, target_member_user_ids, now:)
      scope = Favorite.where(favoritable_type:, favoritable_id: favoritable_ids)
      scope.where.not(user_id: target_member_user_ids).delete_all
      scope.update_all(workspace_id: target_workspace.id, updated_at: now)
    end

    def move_page_templates!(page_ids)
      PageTemplate.where(page_id: page_ids).find_each do |template|
        template.update!(workspace: target_workspace, name: unique_template_name(PageTemplate, template.name))
      end
    end

    def unique_database_name(name, used_names)
      base_name = name.to_s.strip.presence || "Untitled grid"
      candidate = base_name
      suffix = 2

      while used_names.include?(candidate.downcase)
        candidate = "#{base_name} #{suffix}"
        suffix += 1
      end

      candidate
    end

    def unique_template_name(template_class, name)
      base_name = name.to_s.strip.presence || "Untitled template"
      return base_name unless template_class.where(workspace_id: target_workspace.id).where("LOWER(name) = ?", base_name.downcase).exists?

      suffix = 2
      loop do
        candidate = "#{base_name} #{suffix}"
        return candidate unless template_class.where(workspace_id: target_workspace.id).where("LOWER(name) = ?", candidate.downcase).exists?

        suffix += 1
      end
    end

    def log_move!(page_ids:, database_ids:)
      kind = record.is_a?(Database) ? "database_moved_workspace" : "page_moved_workspace"
      AuditEventLogger.log!(
        workspace: target_workspace,
        actor: actor,
        action: "move",
        metadata: {
          kind: kind,
          source_workspace_id: source_workspace.id,
          target_workspace_id: target_workspace.id,
          page_ids: page_ids,
          database_ids: database_ids
        },
        auditable: record
      )
    end
  end
end

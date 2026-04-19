require "csv"
require "json"
require "zip"

module WorkspaceExports
  class ArchiveBuilder
    class << self
      def call(workspace_export:)
        new(workspace_export:).call
      end
    end

    def initialize(workspace_export:)
      @workspace_export = workspace_export
      @workspace = workspace_export.workspace
      @user = workspace_export.requested_by
    end

    def call
      Zip::OutputStream.write_buffer do |zip|
        add_workspace_summary(zip)
        add_page_exports(zip)
        add_database_exports(zip)
        add_kalendarium_exports(zip)
        add_epistularium_exports(zip)
      end.string
    end

    private

    attr_reader :workspace_export, :workspace, :user

    def add_workspace_summary(zip)
      add_string_entry(zip, "workspace.md", <<~MARKDOWN)
        # Workspace backup

        - Workspace: #{workspace.name}
        - Workspace slug: #{workspace.slug}
        - Workspace ID: #{workspace.id}
        - Requested by: #{user.email}
        - Exported at: #{Time.current.iso8601}
        - Includes:
          - Pages as Markdown
          - Page attachments
          - Databases as CSV
          - Kalendarium events as CSV
          - Epistularium messages visible to the requester as CSV
      MARKDOWN
    end

    def add_page_exports(zip)
      pages.find_each do |page|
        result = Pages::MarkdownExportService.call(page:)
        base_path = "pages/#{page.archived? ? 'archived' : 'active'}/#{safe_slug(page.title, fallback: 'page')}-#{page.id}"

        add_string_entry(zip, "#{base_path}.md", result.markdown)
        result.attachments.each do |attachment|
          add_blob_entry(zip, "#{base_path}/#{attachment.relative_path}", attachment.blob)
        end
      end
    end

    def add_database_exports(zip)
      databases.find_each do |database|
        csv = Databases::CsvExportService.call(
          database:,
          include_archived_rows: true,
          include_archived_metadata: true
        )
        file_path = "databases/#{database.archived? ? 'archived' : 'active'}/#{safe_slug(database.name, fallback: 'database')}-#{database.id}.csv"
        add_string_entry(zip, file_path, csv)
      end
    end

    def add_kalendarium_exports(zip)
      csv = CSV.generate(headers: true) do |table|
        table << [
          "Calendar",
          "Title",
          "Starts at (UTC)",
          "Ends at (UTC)",
          "All day",
          "Status",
          "Location",
          "Description",
          "Join meeting URL",
          "Linked page",
          "Linked row",
          "Created at",
          "Updated at"
        ]

        kalendarium_events.each do |event|
          table << [
            event.kalendarium_calendar.name,
            event.title,
            event.starts_at_utc&.iso8601,
            event.ends_at_utc&.iso8601,
            event.all_day? ? "yes" : "no",
            event.status,
            event.location.to_s,
            event.description.to_s,
            event.meeting_join_url.to_s,
            event.linked_page&.title.to_s,
            event.linked_db_row&.title.to_s,
            event.created_at&.iso8601,
            event.updated_at&.iso8601
          ]
        end
      end

      add_string_entry(zip, "kalendarium/events.csv", csv)
    end

    def add_epistularium_exports(zip)
      csv = CSV.generate(headers: true) do |table|
        table << [
          "Account",
          "Mailbox",
          "Provider message ID",
          "Subject",
          "From name",
          "From email",
          "To",
          "Cc",
          "Bcc",
          "Reply-to",
          "Sent at (UTC)",
          "Received at (UTC)",
          "Unread",
          "Snippet",
          "Body text",
          "Body html",
          "Attachment metadata",
          "Metadata"
        ]

        epistularium_messages.each do |message|
          table << [
            message.epistularium_account.label,
            message.mailbox,
            message.provider_message_id,
            message.subject,
            message.from_name.to_s,
            message.from_email.to_s,
            recipients_text(message.to_recipients_json),
            recipients_text(message.cc_recipients_json),
            recipients_text(message.bcc_recipients_json),
            recipients_text(message.reply_to_recipients_json),
            message.sent_at&.iso8601,
            message.received_at&.iso8601,
            message.unread? ? "yes" : "no",
            message.snippet.to_s,
            message.body_text.to_s,
            message.body_html.to_s,
            JSON.generate(message.attachment_metadata_json),
            JSON.generate(message.metadata_json)
          ]
        end
      end

      add_string_entry(zip, "epistularium/messages.csv", csv)
    end

    def add_string_entry(zip, path, contents)
      zip.put_next_entry(path)
      zip.write(contents.to_s)
    end

    def add_blob_entry(zip, path, blob)
      zip.put_next_entry(path)
      zip.write(blob.download)
    end

    def safe_slug(value, fallback:)
      value.to_s.parameterize.presence || fallback
    end

    def recipients_text(values)
      Array(values).filter_map do |recipient|
        next unless recipient.is_a?(Hash)

        [ recipient["name"].to_s.strip.presence, recipient["email"].to_s.strip.presence ].compact.join(" ").strip.presence
      end.join(", ")
    end

    def pages
      @pages ||= PagePolicy::Scope.new(user, Page).resolve.for_workspace(workspace).order(:archived_at, :created_at)
    end

    def databases
      @databases ||= DatabasePolicy::Scope.new(user, Database).resolve.for_workspace(workspace).order(:archived_at, :created_at)
    end

    def kalendarium_events
      @kalendarium_events ||= KalendariumEventPolicy::Scope.new(user, KalendariumEvent)
        .resolve
        .for_workspace(workspace)
        .includes(:kalendarium_calendar, :linked_page, :linked_db_row)
        .order(:starts_at_utc, :created_at)
        .to_a
    end

    def epistularium_messages
      @epistularium_messages ||= EpistulariumMessagePolicy::Scope.new(user, EpistulariumMessage)
        .resolve
        .for_workspace(workspace)
        .includes(:epistularium_account)
        .recent_first
        .to_a
    end
  end
end

require "digest"
require "json"

module Search
  class AssistantToolRegistry
    class Error < StandardError; end

    MAX_SEARCH_RESULTS = 14
    MAX_READ_CHARACTERS = 24_000
    CONTENT_TYPES = %w[text media pages databases calendar meetings email].freeze
    SCOPES = %w[document workspace account].freeze

    attr_reader :sources, :executed_tools

    def initialize(user:, workspace:, selected_scope:, current_page: nil)
      @user = user
      @workspace = workspace
      @selected_scope = selected_scope.to_s
      @current_page = current_page
      @sources = []
      @executed_tools = []
      @result_cache = {}
    end

    def definitions
      [
        search_definition,
        read_nota_definition,
        list_resources_definition,
        update_nota_definition,
        create_nota_definition,
        create_database_definition,
        create_database_row_definition,
        create_calendar_event_definition
      ]
    end

    def call(name:, arguments:)
      tool_name = name.to_s
      args = normalize_arguments(arguments)
      cache_key = Digest::SHA256.hexdigest(JSON.generate([ tool_name, args ]))
      return @result_cache.fetch(cache_key) if @result_cache.key?(cache_key)

      result = dispatch(tool_name, args)
      executed_tools << tool_name
      @result_cache[cache_key] = result
    rescue JSON::ParserError => error
      error_result("Invalid tool arguments: #{error.message}")
    rescue ActiveRecord::RecordInvalid => error
      error_result(error.record.errors.full_messages.to_sentence)
    rescue ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError
      error_result("That Notae item is not available in the selected scope.")
    rescue Workflows::LaunchService::Error, Error => error
      error_result(error.message)
    end

    private

    attr_reader :user, :workspace, :selected_scope, :current_page

    def dispatch(name, args)
      case name
      when "search_notae" then search_notae(args)
      when "read_nota" then read_nota(args)
      when "list_notae_resources" then list_notae_resources(args)
      when "update_nota" then update_nota(args)
      when "create_nota" then create_nota(args)
      when "create_database" then create_database(args)
      when "create_database_row" then create_database_row(args)
      when "create_calendar_event" then create_calendar_event(args)
      else raise Error, "Unsupported Notae tool: #{name}"
      end
    end

    def search_notae(args)
      query = args.fetch("query").to_s.strip
      raise Error, "A search query is required." if query.blank?

      scope = effective_search_scope(args.fetch("scope"))
      page = scope == "document" ? current_page : nil
      results = Search::AssistantContentSearchService.new(
        user: user,
        workspace: workspace,
        query: query,
        scope: scope,
        page: page
      ).call

      content_types = Array(args.fetch("content_types")).map(&:to_s) & CONTENT_TYPES
      results = filter_search_results(results, content_types) if content_types.any?
      results = results.first(MAX_SEARCH_RESULTS)

      payload = results.each_with_index.map do |result, index|
        source = source_from_search_result(result, index: index + 1)
        record_source(source)
        {
          index: index + 1,
          kind: result.kind,
          title: result.title,
          excerpt: result.excerpt.to_s.truncate(900),
          url: result.url,
          workspace: result.respond_to?(:workspace_name) ? result.workspace_name : workspace.name,
          media: result.respond_to?(:media) ? result.media : nil
        }.compact
      end

      { ok: true, scope: scope, count: payload.length, results: payload }
    end

    def read_nota(args)
      page = accessible_page!(args.fetch("page_id"))
      export = Pages::MarkdownExportService.call(page: page)
      record_source(
        title: page.title,
        kind: "Nota",
        url: page_url(page),
        workspace_name: page.workspace.name
      )

      {
        ok: true,
        page: {
          id: page.id,
          title: page.title,
          workspace_id: page.workspace_id,
          workspace: page.workspace.name,
          url: page_url(page),
          markdown: export.markdown.to_s.first(MAX_READ_CHARACTERS),
          truncated: export.markdown.to_s.length > MAX_READ_CHARACTERS,
          attachments: export.attachments.map { |attachment| { block_id: attachment.block_id, filename: attachment.filename } }
        }
      }
    end

    def list_notae_resources(args)
      resource_type = args.fetch("resource_type").to_s
      query = args.fetch("query").to_s.strip.downcase
      workspaces = resource_workspaces

      resources = case resource_type
      when "workspaces"
        workspaces.map { |candidate| { id: candidate.id, name: candidate.name, slug: candidate.slug } }
      when "databases"
        scope = Pundit.policy_scope!(user, Database).active.where(workspace_id: workspaces.map(&:id)).includes(:workspace)
        scope.map do |database|
          {
            id: database.id,
            name: database.name,
            description: database.description,
            workspace_id: database.workspace_id,
            workspace: database.workspace.name,
            locked: database.locked?
          }
        end
      when "calendars"
        scope = Pundit.policy_scope!(user, KalendariumCalendar).where(workspace_id: workspaces.map(&:id)).enabled.user_writable.includes(:workspace)
        scope.map do |calendar|
          {
            id: calendar.id,
            name: calendar.name,
            workspace_id: calendar.workspace_id,
            workspace: calendar.workspace.name,
            source: calendar.source_kind
          }
        end
      else
        raise Error, "Unsupported resource type."
      end

      if query.present?
        resources.select! do |resource|
          [ resource[:name], resource[:description], resource[:workspace], resource[:slug] ].compact.join(" ").downcase.include?(query)
        end
      end

      { ok: true, resource_type: resource_type, count: resources.length, resources: resources.first(50) }
    end

    def update_nota(args)
      page = accessible_page!(args.fetch("page_id"), update: true)
      target_workspace = page.workspace
      input = {
        "page_id" => page.id,
        "title" => args.fetch("title").to_s,
        "body" => args.fetch("body").to_s,
        "content_mode" => args.fetch("body_mode").to_s
      }
      run_workflow!(workspace: target_workspace, kind: WorkflowRun::KIND_UPDATE_NOTA, input: input)
    end

    def create_nota(args)
      target_workspace = accessible_workspace!(args.fetch("workspace_id"))
      run_workflow!(
        workspace: target_workspace,
        kind: WorkflowRun::KIND_CREATE_NOTA,
        input: {
          "title" => args.fetch("title").to_s,
          "body" => args.fetch("body").to_s
        }
      )
    end

    def create_database(args)
      target_workspace = accessible_workspace!(args.fetch("workspace_id"))
      run_workflow!(
        workspace: target_workspace,
        kind: WorkflowRun::KIND_CREATE_DATABASE,
        input: {
          "name" => args.fetch("name").to_s,
          "description" => args.fetch("description").to_s,
          "properties" => Array(args.fetch("properties")),
          "rows" => Array(args.fetch("rows"))
        }
      )
    end

    def create_database_row(args)
      database = accessible_database!(args.fetch("database_id"), update: true)
      run_workflow!(
        workspace: database.workspace,
        kind: WorkflowRun::KIND_CREATE_TASK,
        input: {
          "database_id" => database.id,
          "title" => args.fetch("title").to_s,
          "cells" => Array(args.fetch("cells"))
        }
      )
    end

    def create_calendar_event(args)
      calendar = accessible_calendar!(args.fetch("calendar_id"))
      run_workflow!(
        workspace: calendar.workspace,
        kind: WorkflowRun::KIND_CREATE_CALENDAR_EVENT,
        input: {
          "kalendarium_calendar_id" => calendar.id,
          "title" => args.fetch("title").to_s,
          "description" => args.fetch("description").to_s,
          "location" => args.fetch("location").to_s,
          "starts_at_local" => args.fetch("starts_at").to_s,
          "ends_at_local" => args.fetch("ends_at").to_s,
          "all_day" => args.fetch("all_day")
        }
      )
    end

    def run_workflow!(workspace:, kind:, input:)
      run = Workflows::LaunchService.new(
        workspace: workspace,
        actor: user,
        workflow_kind: kind,
        input: input,
        trigger_source: "ai_assistant",
        confidence_score: 1.0,
        execution_mode: :inline
      ).call

      result = run.result_json.to_h
      url = result["url"].to_s.presence
      record_source(
        title: result["title"].presence || kind.humanize,
        kind: "Completed action",
        url: url,
        workspace_name: workspace.name
      ) if url.present?

      {
        ok: run.succeeded?,
        status: run.status,
        workflow_run_id: run.id,
        action: kind,
        result: result,
        error: run.error_message
      }.compact
    end

    def accessible_page!(id, update: false)
      page = Pundit.policy_scope!(user, Page).active.includes(:workspace).find(id)
      enforce_page_scope!(page)
      Pundit.authorize(user, page, update ? :update? : :show?)
    end

    def accessible_database!(id, update: false)
      database = Pundit.policy_scope!(user, Database).active.includes(:workspace).find(id)
      Pundit.authorize(user, database, update ? :update? : :show?)
    end

    def accessible_calendar!(id)
      calendar = Pundit.policy_scope!(user, KalendariumCalendar).enabled.user_writable.includes(:workspace).find(id)
      Pundit.authorize(user, calendar, :update?)
    end

    def accessible_workspace!(id)
      candidate_id = id.to_s.strip
      return workspace if candidate_id.blank? || candidate_id == workspace.id.to_s

      Pundit.policy_scope!(user, Workspace).find(candidate_id)
    end

    def enforce_page_scope!(page)
      case selected_scope
      when Search::AssistantQueryService::SCOPE_DOCUMENT
        raise Pundit::NotAuthorizedError unless current_page.present? && page.id == current_page.id
      when Search::AssistantQueryService::SCOPE_WORKSPACE
        raise Pundit::NotAuthorizedError unless page.workspace_id == workspace.id
      end
    end

    def resource_workspaces
      if selected_scope == Search::AssistantQueryService::SCOPE_ACCOUNT || selected_scope == Search::AssistantQueryService::SCOPE_AUTO
        Pundit.policy_scope!(user, Workspace).where.not(slug: [ nil, "" ]).order(:name).to_a
      else
        [ workspace ]
      end
    end

    def effective_search_scope(requested)
      requested_scope = requested.to_s
      requested_scope = "workspace" unless SCOPES.include?(requested_scope)

      case selected_scope
      when Search::AssistantQueryService::SCOPE_DOCUMENT then "document"
      when Search::AssistantQueryService::SCOPE_WORKSPACE then requested_scope == "document" ? "document" : "workspace"
      when Search::AssistantQueryService::SCOPE_ACCOUNT then requested_scope
      else requested_scope
      end
    end

    def filter_search_results(results, content_types)
      results.select do |result|
        kind = result.kind.to_s.downcase
        media = result.respond_to?(:media) && result.media.present?
        content_types.any? do |type|
          case type
          when "media" then media
          when "pages" then kind.include?("page") || kind.include?("nota") || kind.include?("block")
          when "databases" then kind.include?("row") || kind.include?("grid") || kind.include?("database")
          when "calendar" then kind.include?("calendar") || kind.include?("event")
          when "meetings" then kind.include?("meeting")
          when "email" then kind.include?("email")
          when "text" then !media
          else true
          end
        end
      end
    end

    def source_from_search_result(result, index:)
      {
        index: index,
        title: result.title,
        kind: result.kind,
        url: result.url,
        workspace_name: result.respond_to?(:workspace_name) ? result.workspace_name : workspace.name
      }
    end

    def record_source(source = nil, **attributes)
      normalized = (source || attributes).compact
      return if normalized[:url].to_s.blank?
      return if sources.any? { |existing| existing[:url] == normalized[:url] }

      sources << normalized
    end

    def page_url(page)
      Rails.application.routes.url_helpers.page_path(workspace_slug: page.workspace.slug, id: page.id)
    end

    def normalize_arguments(arguments)
      return arguments.deep_stringify_keys if arguments.respond_to?(:deep_stringify_keys)

      JSON.parse(arguments.to_s)
    end

    def error_result(message)
      { ok: false, error: message.to_s.truncate(500) }
    end

    def function_definition(name:, description:, properties:, required: properties.keys)
      {
        type: "function",
        name: name,
        description: description,
        strict: true,
        parameters: {
          type: "object",
          properties: properties,
          required: required,
          additionalProperties: false
        }
      }
    end

    def search_definition
      function_definition(
        name: "search_notae",
        description: "Search authorized text, media, pages, databases, calendar events, meetings, and email in Notae. Use the user's requested document, workspace, or whole-app scope.",
        properties: {
          query: { type: "string", description: "A concise semantic search query." },
          scope: { type: "string", enum: SCOPES, description: "Where to search. account means the whole authorized Notae app." },
          content_types: {
            type: "array",
            items: { type: "string", enum: CONTENT_TYPES },
            description: "Relevant content families. Use an empty array to search everything."
          }
        }
      )
    end

    def read_nota_definition
      function_definition(
        name: "read_nota",
        description: "Read the complete authorized Nota as Markdown, including attachment names.",
        properties: { page_id: { type: "string", description: "The exact page UUID from context or search." } }
      )
    end

    def list_resources_definition
      function_definition(
        name: "list_notae_resources",
        description: "Resolve exact writable Notae workspace, database, or calendar IDs before an action. Never invent IDs.",
        properties: {
          resource_type: { type: "string", enum: %w[workspaces databases calendars] },
          query: { type: "string", description: "Optional name filter; use an empty string to list all authorized resources." }
        }
      )
    end

    def update_nota_definition
      function_definition(
        name: "update_nota",
        description: "Update an authorized Nota title and/or Markdown body immediately. Empty title or body leaves that field unchanged.",
        properties: {
          page_id: { type: "string" },
          title: { type: "string" },
          body: { type: "string" },
          body_mode: { type: "string", enum: %w[keep replace append] }
        }
      )
    end

    def create_nota_definition
      function_definition(
        name: "create_nota",
        description: "Create a new Nota with a title and Markdown body immediately.",
        properties: {
          workspace_id: { type: "string", description: "Exact workspace UUID, or an empty string for the current workspace." },
          title: { type: "string" },
          body: { type: "string", description: "Markdown content." }
        }
      )
    end

    def create_database_definition
      cell_schema = {
        type: "object",
        properties: { property: { type: "string" }, value: { type: "string" } },
        required: %w[property value],
        additionalProperties: false
      }
      function_definition(
        name: "create_database",
        description: "Create a general Notae database/list with typed properties and initial rows immediately. This is not limited to tasks.",
        properties: {
          workspace_id: { type: "string", description: "Exact workspace UUID, or an empty string for the current workspace." },
          name: { type: "string" },
          description: { type: "string" },
          properties: {
            type: "array",
            items: {
              type: "object",
              properties: {
                name: { type: "string" },
                type: { type: "string", enum: %w[text number date checkbox select progress] },
                options: { type: "array", items: { type: "string" } }
              },
              required: %w[name type options],
              additionalProperties: false
            }
          },
          rows: {
            type: "array",
            items: {
              type: "object",
              properties: { title: { type: "string" }, cells: { type: "array", items: cell_schema } },
              required: %w[title cells],
              additionalProperties: false
            }
          }
        }
      )
    end

    def create_database_row_definition
      function_definition(
        name: "create_database_row",
        description: "Add one row/item to an existing authorized Notae database immediately, using exact property names from the database.",
        properties: {
          database_id: { type: "string" },
          title: { type: "string" },
          cells: {
            type: "array",
            items: {
              type: "object",
              properties: { property: { type: "string" }, value: { type: "string" } },
              required: %w[property value],
              additionalProperties: false
            }
          }
        }
      )
    end

    def create_calendar_event_definition
      function_definition(
        name: "create_calendar_event",
        description: "Create an event immediately in an exact writable Notae calendar. Resolve the calendar first. Times must be ISO 8601 or unambiguous local times.",
        properties: {
          calendar_id: { type: "string" },
          title: { type: "string" },
          description: { type: "string" },
          location: { type: "string" },
          starts_at: { type: "string" },
          ends_at: { type: "string" },
          all_day: { type: "boolean" }
        }
      )
    end
  end
end

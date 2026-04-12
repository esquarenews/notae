module Kalendarium
  class TasksProjectEnsurer
    PROJECT_NAME = "Tasks".freeze
    PROJECT_SLUG = "tasks".freeze
    PROJECT_COLOR = "#10B981".freeze

    def initialize(workspace:, actor:)
      @workspace = workspace
      @actor = actor
    end

    def call
      project = find_or_initialize_project

      ActiveRecord::Base.transaction do
        project.created_by ||= actor
        project.name = PROJECT_NAME
        project.slug = PROJECT_SLUG if project.slug.blank? || project.slug == PROJECT_SLUG
        project.color_hex = project.color_hex.presence || PROJECT_COLOR
        project.archived_at = nil
        project.save! if project.changed?

        calendar = project.kalendarium_calendar || build_project_calendar(project)
        sync_calendar!(calendar, project)

        if project.kalendarium_calendar_id != calendar.id
          project.update!(kalendarium_calendar: calendar)
        end

        project
      end
    end

    private

    attr_reader :workspace, :actor

    def find_or_initialize_project
      existing_project =
        workspace.kalendarium_projects.find_by(slug: PROJECT_SLUG) ||
        workspace.kalendarium_projects.where("LOWER(name) = ?", PROJECT_NAME.downcase).order(:created_at).first

      return existing_project if existing_project.present?

      workspace.kalendarium_projects.new(
        name: PROJECT_NAME,
        slug: PROJECT_SLUG,
        color_hex: PROJECT_COLOR,
        created_by: actor
      )
    end

    def build_project_calendar(project)
      workspace.kalendarium_calendars.new(
        created_by: actor,
        name: project.name,
        color_hex: project.color_hex,
        source_kind: "project",
        enabled: true,
        time_zone: actor.time_zone.presence || "UTC"
      )
    end

    def sync_calendar!(calendar, project)
      calendar.assign_attributes(
        name: project.name,
        color_hex: project.color_hex,
        source_kind: "project",
        enabled: true
      )
      calendar.time_zone = actor.time_zone.presence || calendar.time_zone.presence || "UTC"
      calendar.save! if calendar.changed?
    end
  end
end

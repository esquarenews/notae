class WorkflowRun < ApplicationRecord
  KIND_CREATE_NOTA = "create_nota".freeze
  KIND_CREATE_TASK = "create_task".freeze
  KIND_CREATE_CALENDAR_EVENT = "create_calendar_event".freeze
  KINDS = [
    KIND_CREATE_NOTA,
    KIND_CREATE_TASK,
    KIND_CREATE_CALENDAR_EVENT
  ].freeze

  STATUS_QUEUED = "queued".freeze
  STATUS_RUNNING = "running".freeze
  STATUS_SUCCEEDED = "succeeded".freeze
  STATUS_FAILED = "failed".freeze
  STATUS_KILLED = "killed".freeze
  STATUS_CANCELLED = "cancelled".freeze
  STATUSES = [
    STATUS_QUEUED,
    STATUS_RUNNING,
    STATUS_SUCCEEDED,
    STATUS_FAILED,
    STATUS_KILLED,
    STATUS_CANCELLED
  ].freeze

  TRIGGER_SOURCES = %w[manual ai_assistant automation_agent].freeze

  belongs_to :workspace
  belongs_to :user

  validates :workflow_kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :trigger_source, inclusion: { in: TRIGGER_SOURCES }
  validates :attempts_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :queued_at, presence: true

  scope :for_workspace, ->(workspace) { where(workspace_id: workspace.id) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :finished, -> { where(status: [ STATUS_SUCCEEDED, STATUS_FAILED, STATUS_KILLED, STATUS_CANCELLED ]) }
  scope :failed, -> { where(status: STATUS_FAILED) }
  scope :successful, -> { where(status: STATUS_SUCCEEDED) }

  def queued?
    status == STATUS_QUEUED
  end

  def running?
    status == STATUS_RUNNING
  end

  def succeeded?
    status == STATUS_SUCCEEDED
  end

  def failed?
    status == STATUS_FAILED
  end

  def killed?
    status == STATUS_KILLED
  end

  def finished?
    [ STATUS_SUCCEEDED, STATUS_FAILED, STATUS_KILLED, STATUS_CANCELLED ].include?(status)
  end

  def retryable?
    attempts_count < max_attempts && !finished?
  end
end

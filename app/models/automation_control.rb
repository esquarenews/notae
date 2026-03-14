class AutomationControl < ApplicationRecord
  GLOBAL_SCOPE = "global".freeze

  validates :scope_name, presence: true, uniqueness: true
  validates :enabled, inclusion: { in: [ true, false ] }

  def self.current
    find_or_create_by!(scope_name: GLOBAL_SCOPE)
  end

  def pause!(reason:)
    update!(enabled: false, paused_at: Time.current, pause_reason: reason.to_s.strip.presence)
  end

  def resume!
    update!(enabled: true, paused_at: nil, pause_reason: nil)
  end
end

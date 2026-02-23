class AuditEventLogger
  class << self
    def log!(workspace:, actor:, action:, metadata: {}, auditable: nil)
      AuditEvent.create!(
        workspace: workspace,
        actor: actor,
        action: action,
        metadata: metadata,
        auditable: auditable
      )
    end
  end
end

module AgentActions
  module Adapters
    class BaseAdapter
      DryRunResult = Struct.new(:target_system, :draft_type, :dry_run, :summary, :preview, keyword_init: true) do
        def to_h
          {
            "target_system" => target_system,
            "draft_type" => draft_type,
            "dry_run" => dry_run,
            "summary" => summary,
            "preview" => preview
          }
        end
      end

      def supports_draft_type?(_draft_type)
        false
      end

      def dry_run(_agent_action)
        raise NotImplementedError
      end
    end
  end
end

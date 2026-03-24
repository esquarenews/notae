module AgentActions
  class AdapterRegistry
    class Error < StandardError; end

    class << self
      def fetch(target_system)
        case target_system.to_s
        when "gmail" then AgentActions::Adapters::GmailAdapter.new
        when "email" then AgentActions::Adapters::EmailAdapter.new
        when "github" then AgentActions::Adapters::GithubAdapter.new
        when "slack" then AgentActions::Adapters::SlackAdapter.new
        when "calendar" then AgentActions::Adapters::CalendarAdapter.new
        when "crm" then AgentActions::Adapters::CrmAdapter.new
        when "notae" then AgentActions::Adapters::NotaeAdapter.new
        else
          raise Error, "Unsupported adapter target: #{target_system}"
        end
      end
    end
  end
end

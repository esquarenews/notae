namespace :search_chunks do
  desc "Backfill search chunks for all workspaces (or a specific workspace via WORKSPACE_SLUG=...)"
  task backfill: :environment do
    scope = Workspace.all

    if ENV["WORKSPACE_SLUG"].present?
      scope = scope.where(slug: ENV["WORKSPACE_SLUG"])
    end

    scope.find_each do |workspace|
      puts "Backfilling search chunks for workspace: #{workspace.slug}"
      Search::BackfillWorkspaceChunksJob.perform_now(workspace.id)
    end
  end
end

class FaviconSettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_workspace

  CANDIDATES = [
    {
      id: "disco-core",
      name: "Disco Core",
      description: "Bold disco orb with high-contrast glow for strong visibility at 16px.",
      svg_href: "/favicons/candidates/disco-core.svg"
    },
    {
      id: "neon-n",
      name: "Neon N",
      description: "Monogram-first icon with thick geometry and cyan-magenta edge lighting.",
      svg_href: "/favicons/candidates/neon-n.svg"
    },
    {
      id: "signal-beacon",
      name: "Signal Beacon",
      description: "Concentric pulse beacon with clean silhouette and tab-safe contrast.",
      svg_href: "/favicons/candidates/signal-beacon.svg"
    },
    {
      id: "grid-prism",
      name: "Grid Prism",
      description: "Structured prism tile reflecting the Grid identity with simplified facets.",
      svg_href: "/favicons/candidates/grid-prism.svg"
    },
    {
      id: "orbit-dot",
      name: "Orbit Dot",
      description: "Minimal orbital mark with bright center and clear ring at small sizes.",
      svg_href: "/favicons/candidates/orbit-dot.svg"
    },
    {
      id: "star-node",
      name: "Star Node",
      description: "Futuristic node star with strong directional shape and dark-edge framing.",
      svg_href: "/favicons/candidates/star-node.svg"
    }
  ].freeze

  def show
    authorize @workspace, :show?
    @favicon_candidates = CANDIDATES
  end

  private

  def set_workspace
    accessible_workspaces = policy_scope(Workspace).order(updated_at: :desc)
    requested_slug = params[:workspace_slug].to_s

    @workspace = if requested_slug.present? && !requested_slug.start_with?(":")
      accessible_workspaces.find_by(slug: requested_slug)
    end
    return if @workspace.present?

    fallback_workspace = accessible_workspaces.first
    if fallback_workspace.present?
      redirect_to workspace_favicon_settings_path(workspace_slug: fallback_workspace.slug),
                  alert: "Select a valid workspace to open Favicon Lab."
      return
    end

    redirect_to root_path, alert: "No accessible workspace was found."
  end
end

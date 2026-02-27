class HomeController < ApplicationController
  def index
    @workspaces = policy_scope(Workspace).where.not(slug: [ nil, "" ]).order(:name)
  end
end

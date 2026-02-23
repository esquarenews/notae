class HomeController < ApplicationController
  def index
    @workspaces = policy_scope(Workspace).order(:name)
  end
end

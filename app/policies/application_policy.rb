# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NoMethodError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end

  private

  def membership_for_workspace(workspace_id)
    return nil unless user && workspace_id.present?

    cache = user_membership_cache
    return cache[workspace_id] if cache.key?(workspace_id)

    membership =
      if user_memberships_preloaded?
        user.memberships.find { |candidate| candidate.workspace_id == workspace_id }
      else
        Membership.find_by(user_id: user.id, workspace_id: workspace_id)
      end

    cache[workspace_id] = membership
  end

  def user_membership_cache
    cache = user.instance_variable_get(:@_notae_membership_cache)
    return cache if cache.is_a?(Hash)

    cache =
      if user_memberships_preloaded?
        user.memberships.index_by(&:workspace_id)
      else
        {}
      end

    user.instance_variable_set(:@_notae_membership_cache, cache)
  end

  def user_memberships_preloaded?
    user.respond_to?(:association) && user.association(:memberships).loaded?
  rescue ArgumentError
    false
  end
end

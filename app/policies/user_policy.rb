class UserPolicy < ApplicationPolicy
  def show?
    user.present? && record.id == user.id
  end

  def update?
    show?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user

      scope.where(id: user.id)
    end
  end
end

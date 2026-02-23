module Features
  module_function

  def enabled?(name)
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("FEATURE_#{name.to_s.upcase}", "false"))
  end
end

class RemapLegacyAiLoaderStyles < ActiveRecord::Migration[8.1]
  LEGACY_STYLE_MAP = {
    "prism_gate" => "disco_ball_reflect",
    "signal_bloom" => "flock_cloud",
    "lattice_flux" => "neural_network"
  }.freeze

  def up
    LEGACY_STYLE_MAP.each do |from_style, to_style|
      execute <<~SQL.squish
        UPDATE users
        SET ai_loader_style = '#{to_style}'
        WHERE ai_loader_style = '#{from_style}'
      SQL
    end
  end

  def down
    LEGACY_STYLE_MAP.each do |from_style, to_style|
      execute <<~SQL.squish
        UPDATE users
        SET ai_loader_style = '#{from_style}'
        WHERE ai_loader_style = '#{to_style}'
      SQL
    end
  end
end

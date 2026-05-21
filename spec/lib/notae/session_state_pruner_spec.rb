require "rails_helper"

RSpec.describe Notae::SessionStatePruner do
  it "caps workspace-scoped session hashes to the configured limits" do
    session = {
      "notae_last_page_visits" => 10.times.to_h { |index| [ "w#{index}", index.to_s ] },
      "kalendarium_calendar_selection" => 12.times.to_h { |index| [ "w#{index}", { "mode" => "selected", "ids" => [ index.to_s ] } ] },
      "kalendarium_project_visibility" => 12.times.to_h { |index| [ "w#{index}", { "mode" => "all_except", "ids" => [ index.to_s ] } ] },
      "kalendarium_last_calendar_view" => 12.times.to_h { |index| [ "w#{index}", "week" ] }
    }

    described_class.prune!(session)

    expect(session["notae_last_page_visits"].keys).to eq(%w[w4 w5 w6 w7 w8 w9])
    expect(session["kalendarium_calendar_selection"].keys).to eq(%w[w4 w5 w6 w7 w8 w9 w10 w11])
    expect(session["kalendarium_project_visibility"].keys).to eq(%w[w4 w5 w6 w7 w8 w9 w10 w11])
    expect(session["kalendarium_last_calendar_view"].keys).to eq(%w[w4 w5 w6 w7 w8 w9 w10 w11])
  end

  it "compacts oversized legacy calendar visibility payloads before they overflow cookie sessions" do
    session = {
      "kalendarium_calendar_selection" => {
        "workspace" => {
          "selected_ids" => 40.times.map { |index| "calendar-#{index}" },
          "available_ids" => 40.times.map { |index| "calendar-#{index}" }
        }
      },
      "kalendarium_project_visibility" => {
        "workspace" => {
          "mode" => "selected",
          "ids" => 40.times.map { |index| "project-#{index}" }
        }
      }
    }

    described_class.prune!(session)

    expect(session["kalendarium_calendar_selection"]).to eq("workspace" => { "mode" => "all" })
    expect(session["kalendarium_project_visibility"]).to eq("workspace" => { "mode" => "all" })
  end
end

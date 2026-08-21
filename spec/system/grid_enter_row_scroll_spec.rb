require "rails_helper"
require "capybara/rspec"
require "warden/test/helpers"

RSpec.describe "Grid Enter row creation", type: :system do
  include Warden::Test::Helpers

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 900 ]
  end

  after do
    Warden.test_reset!
  end

  it "keeps a long grid steady while moving focus to the next created task" do
    user = User.create!(email: "grid-enter-scroll@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid Enter Scroll", slug: "grid-enter-scroll")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    database = Database.create!(workspace: workspace, name: "Long task grid")
    rows = 20.times.map do |index|
      DbRow.create!(workspace: workspace, database: database, title: "Task #{index + 1}")
    end

    login_as user, scope: :user
    visit database_path(workspace_slug: workspace.slug, id: database.id)
    source_input = find("#row_#{rows.last.id} input.notae-db-title-input")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", source_input.native)
    page.execute_script(<<~JAVASCRIPT)
      (() => {
        const scroller = document.querySelector(".notae-content-scroll")
        window.__notaeGridScrollSamples = [scroller.scrollTop]
        window.__notaeGridScrollListener = () => window.__notaeGridScrollSamples.push(scroller.scrollTop)
        scroller.addEventListener("scroll", window.__notaeGridScrollListener)
      })()
    JAVASCRIPT

    source_input.set("Task 20 renamed")
    source_input.send_keys(:enter)

    previous_row_id = rows.last.id
    3.times do |index|
      expect(page).to have_css(
        "tr.notae-db-grid-data-row:not(#row_#{previous_row_id}) form[data-controller~='select-on-connect'] input.notae-db-title-input:focus",
        wait: 5
      )

      focused_value = page.evaluate_script("document.activeElement?.value")
      selection = page.evaluate_script("[document.activeElement?.selectionStart, document.activeElement?.selectionEnd]")
      expect(focused_value).to eq("Untitled row")
      expect(selection).to eq([ 0, "Untitled row".length ])
      previous_row_id = page.evaluate_script("document.activeElement?.closest('tr')?.id")&.delete_prefix("row_")

      break if index == 2

      page.send_keys("Created task #{index + 1}")
      page.send_keys(:enter)
    end

    sleep 2

    result = page.evaluate_script(<<~JAVASCRIPT)
      (() => {
        const scroller = document.querySelector(".notae-content-scroll")
        scroller.removeEventListener("scroll", window.__notaeGridScrollListener)
        const samples = window.__notaeGridScrollSamples.concat(scroller.scrollTop)
        const focusedInput = document.activeElement?.matches("input.notae-db-title-input")
        const focusedRow = document.activeElement?.closest("tr.notae-db-grid-data-row")
        return {
          range: Math.max(...samples) - Math.min(...samples),
          focusedInput,
          focusedRowId: focusedRow?.id || null,
          sampleCount: samples.length,
          value: document.activeElement?.value || null,
          selectionStart: document.activeElement?.selectionStart ?? null,
          selectionEnd: document.activeElement?.selectionEnd ?? null
        }
      })()
    JAVASCRIPT

    created_row_id = result.fetch("focusedRowId").to_s.delete_prefix("row_")
    created_row = database.db_rows.find_by(id: created_row_id)
    expect(created_row).to be_present
    expect(rows.map(&:id)).not_to include(created_row.id)
    expect(result.fetch("focusedInput")).to be(true)
    expect(result.fetch("focusedRowId")).to eq("row_#{created_row.id}")
    expect(result.fetch("value")).to eq("Untitled row")
    expect(result.fetch("selectionStart")).to eq(0)
    expect(result.fetch("selectionEnd")).to eq("Untitled row".length)
    expect(result.fetch("range")).to be <= 2

    page.send_keys("Replacement title")
    expect(find("#row_#{created_row.id} input.notae-db-title-input").value).to eq("Replacement title")
  end
end

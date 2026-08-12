require "rails_helper"
require "capybara/rspec"

RSpec.describe "Grid Enter row creation", type: :system do
  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 900 ]
  end

  it "keeps a long grid steady while moving focus to the next created task" do
    user = User.create!(email: "grid-enter-scroll@example.com", password: "password123")
    workspace = Workspace.create!(name: "Grid Enter Scroll", slug: "grid-enter-scroll")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    database = Database.create!(workspace: workspace, name: "Long task grid")
    rows = 20.times.map do |index|
      DbRow.create!(workspace: workspace, database: database, title: "Task #{index + 1}")
    end

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign in"

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

    expect(page).to have_css("form[data-auto-submit-focus-on-connect-value='true'] input.notae-db-title-input", wait: 5)
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

    created_row = database.db_rows.where.not(id: rows.map(&:id)).order(:created_at).last
    expect(created_row).to be_present
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

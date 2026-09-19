require "rails_helper"
require "capybara/rspec"

RSpec.describe "AI rail submission", type: :system do
  before(:context) do
    @user = User.create!(
      email: "ai-rail-system@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne"
    )
    @workspace = Workspace.create!(name: "AI rail system", slug: "ai-rail-system")
    Membership.create!(workspace: @workspace, user: @user, role: :owner)
    KnowledgeSuggestion.create!(
      workspace: @workspace,
      user: @user,
      kind: KnowledgeSuggestion::KIND_PROACTIVE,
      status: KnowledgeSuggestion::STATUS_ACTIVE,
      title: "Long proactive suggestion",
      summary: Array.new(80, "This is existing proactive context that must not hide a newer assistant response.").join(" "),
      insights_json: [ "Review the existing context before the next planning session." ],
      task_suggestions_json: [],
      sources_json: [],
      generated_at: Time.current,
      expires_at: 4.hours.from_now
    )
  end

  after(:context) do
    Workspace.find_by(slug: "ai-rail-system")&.destroy!
    User.find_by(email: "ai-rail-system@example.com")&.destroy!
  end

  before do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 900 ]
  end

  it "keeps the submitted prompt visible and renders the model response" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("OPENAI_API_KEY").and_return("sk-server-test")
    allow(Search::AiBudgetGuard).to receive(:within_daily_budget?).and_return(true)
    allow(Search::AiRateLimiter).to receive(:allowed?).and_return(true)
    allow_any_instance_of(Search::AssistantModelRouter).to receive(:call).and_return(
      Search::AssistantModelRouter::Route.new(
        tier: "terra",
        model: "gpt-5.6-terra",
        reasoning_effort: "medium",
        usage: Openai::ResponsesClient.default_usage
      )
    )
    allow(Openai::ResponsesClient).to receive(:create).and_return(
      {
        id: "resp_visible_answer",
        text: "The AI rail response is visible.",
        function_calls: [],
        usage: { prompt_tokens: 20, completion_tokens: 8, total_tokens: 28 },
        sources: []
      }
    )

    visit new_user_session_path
    fill_in "Email", with: @user.email
    fill_in "Password", with: "password123"
    click_button "Sign in"

    visit workspace_path(@workspace.slug)
    fill_in "ai_prompt", with: "Show this submitted question"
    find("#ai_prompt").send_keys(:enter)

    expect(page).to have_css(".notae-ai-message.is-user", text: "Show this submitted question")
    expect(page).to have_css(".notae-ai-result-text", text: "The AI rail response is visible.")
    expect(find("#ai_prompt").value).to eq("")
    expect(
      page.evaluate_script(<<~JAVASCRIPT)
        (() => {
          const thread = document.querySelector(".notae-ai-thread")
          const answer = Array.from(document.querySelectorAll(".notae-ai-result-text"))
            .find((element) => element.textContent.includes("The AI rail response is visible."))
          if (!thread || !answer) return false

          const threadBounds = thread.getBoundingClientRect()
          const answerBounds = answer.getBoundingClientRect()
          return answerBounds.bottom > threadBounds.top && answerBounds.top < threadBounds.bottom
        })()
      JAVASCRIPT
    ).to be(true)
  end
end

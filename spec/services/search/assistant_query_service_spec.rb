require "rails_helper"

RSpec.describe Search::AssistantQueryService do
  it "returns exact calendar appointments for tomorrow without using an LLM round-trip" do
    fixed_now = Time.utc(2026, 3, 1, 0, 0, 0)
    allow(Time).to receive(:current).and_return(fixed_now)

    user = User.create!(
      email: "assistant-calendar-tomorrow@example.com",
      password: "password123",
      openai_api_key: "sk-test",
      time_zone: "Australia/Melbourne"
    )
    workspace = Workspace.create!(name: "Assistant Calendar", slug: "assistant-calendar")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    calendar = KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Family",
      color_hex: "#3B82F6",
      time_zone: "Australia/Melbourne",
      source_kind: "local"
    )

    zone = ActiveSupport::TimeZone[user.time_zone]
    tomorrow = Date.new(2026, 3, 2)
    first_start = zone.local(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0)
    first_end = first_start + 1.hour
    all_day_start = zone.local(tomorrow.year, tomorrow.month, tomorrow.day)
    all_day_end = all_day_start + 1.day
    out_of_window_start = first_start - 2.days

    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Dentist appointment",
      starts_at_utc: first_start.utc,
      ends_at_utc: first_end.utc,
      location: "CBD Clinic",
      created_by: user,
      updated_by: user
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "School holiday",
      starts_at_utc: all_day_start.utc,
      ends_at_utc: all_day_end.utc,
      all_day: true,
      created_by: user,
      updated_by: user
    )
    KalendariumEvent.create!(
      workspace: workspace,
      kalendarium_calendar: calendar,
      title: "Do not include",
      starts_at_utc: out_of_window_start.utc,
      ends_at_utc: (out_of_window_start + 1.hour).utc,
      created_by: user,
      updated_by: user
    )

    expect(Openai::ResponsesClient).not_to receive(:generate_text_with_usage)

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "What appointments do I have tomorrow?",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    ).call

    expect(response).to be_present
    expect(response.model).to eq(Search::AssistantQueryService::CALENDAR_DIRECT_MODEL)
    expect(response.answer).to include("Appointments for tomorrow")
    expect(response.answer).to include("Dentist appointment")
    expect(response.answer).to include("School holiday")
    expect(response.answer).to include("09:00")
    expect(response.answer).to include("All day")
    expect(response.answer).not_to include("Do not include")
    expect(response.sources.length).to eq(2)
    expect(response.sources.map { |source| source[:title] }).to contain_exactly("Dentist appointment", "School holiday")
  end

  it "returns an explicit no-appointments response for empty calendar windows" do
    fixed_now = Time.utc(2026, 3, 1, 0, 0, 0)
    allow(Time).to receive(:current).and_return(fixed_now)

    user = User.create!(
      email: "assistant-calendar-empty@example.com",
      password: "password123",
      openai_api_key: "sk-test",
      time_zone: "Australia/Melbourne"
    )
    workspace = Workspace.create!(name: "Assistant Calendar Empty", slug: "assistant-calendar-empty")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    KalendariumCalendar.create!(
      workspace: workspace,
      created_by: user,
      name: "Personal",
      color_hex: "#3B82F6",
      time_zone: "Australia/Melbourne",
      source_kind: "local"
    )

    expect(Openai::ResponsesClient).not_to receive(:generate_text_with_usage)

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "What appointments do I have tomorrow?",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    ).call

    expect(response).to be_present
    expect(response.model).to eq(Search::AssistantQueryService::CALENDAR_DIRECT_MODEL)
    expect(response.answer).to include("No appointments found for tomorrow")
    expect(response.sources).to eq([])
  end

  it "returns a cited answer for workspace scope questions" do
    user = User.create!(email: "assistant-workspace@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Workspace", slug: "assistant-workspace")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Mac Notes")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Mac is mentioned in the release checklist",
      token_count: 8,
      content_hash: "assistant-chunk-1",
      embedding: [ 1.0, 0.0 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: "Yes, Mac is mentioned [1].",
        usage: { prompt_tokens: 90, completion_tokens: 20, total_tokens: 110 }
      }
    )

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Is Mac mentioned in this workspace?",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    ).call

    expect(response).to be_present
    expect(response.answer).to include("[1]")
    expect(response.sources.length).to eq(1)
    expect(response.sources.first[:title]).to eq("Mac Notes")
    usage = AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_ASSISTANT_QUERY)
    expect(usage).to exist
  end

  it "returns no-context when document scope is requested without a page" do
    user = User.create!(email: "assistant-doc-empty@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Doc Empty", slug: "assistant-doc-empty")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    service = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Summarize this document",
      scope: Search::AssistantQueryService::SCOPE_DOCUMENT
    )
    response = service.call

    expect(response).to be_nil
    expect(service.unavailable_reason).to eq(:no_context)
  end

  it "uses a full-model general knowledge response for definition-style prompts" do
    user = User.create!(email: "assistant-general-knowledge@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant General Knowledge", slug: "assistant-general-knowledge")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:model]).to eq(Search::AssistantQueryService::GENERAL_MODEL)
      expect(args[:prompt]).to include("general knowledge")
      {
        text: "Notarum means notes or records, often used as a stylized plural for notes.",
        usage: { prompt_tokens: 55, completion_tokens: 22, total_tokens: 77 }
      }
    end

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "What is definition of notarum?",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    ).call

    expect(response).to be_present
    expect(response.answer).to include("Notarum")
    expect(response.sources).to eq([])
    expect(response.model).to eq(Search::AssistantQueryService::GENERAL_MODEL)
    usage = AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_ASSISTANT_QUERY)
    expect(usage).to exist
  end

  it "drops invalid citations and keeps mapped sources only" do
    user = User.create!(email: "assistant-citation@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Citation", slug: "assistant-citation")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Summary Source")
    SearchChunk.create!(
      workspace: workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "First chunk text",
      token_count: 3,
      content_hash: "assistant-chunk-2",
      embedding: [ 0.2, 0.4 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: "Summary [99] valid part [1].",
        usage: { prompt_tokens: 90, completion_tokens: 20, total_tokens: 110 }
      }
    )

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Summarize",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    ).call

    expect(response).to be_present
    expect(response.answer).not_to include("[99]")
    expect(response.sources.map { |source| source[:index] }).to eq([ 1 ])
  end

  it "supports whole-account scope across accessible workspaces" do
    user = User.create!(email: "assistant-account@example.com", password: "password123", openai_api_key: "sk-test")
    primary_workspace = Workspace.create!(name: "Assistant Account Primary", slug: "assistant-account-primary")
    secondary_workspace = Workspace.create!(name: "Assistant Account Secondary", slug: "assistant-account-secondary")
    Membership.create!(workspace: primary_workspace, user: user, role: :owner)
    Membership.create!(workspace: secondary_workspace, user: user, role: :owner)
    page = Page.create!(workspace: secondary_workspace, created_by: user, title: "Cross-workspace doc")
    SearchChunk.create!(
      workspace: secondary_workspace,
      source_type: SearchChunk::SOURCE_PAGE,
      source_id: page.id,
      page: page,
      chunk_index: 0,
      text: "Account-wide mention for billing and launch details",
      token_count: 7,
      content_hash: "assistant-account-chunk",
      embedding: [ 0.3, 0.7 ],
      embedding_model: SearchChunk::EMBEDDING_MODEL
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: "Found in another workspace [1].",
        usage: { prompt_tokens: 90, completion_tokens: 20, total_tokens: 110 }
      }
    )

    response = described_class.new(
      user: user,
      workspace: primary_workspace,
      prompt: "Where is billing mentioned across my account?",
      scope: Search::AssistantQueryService::SCOPE_ACCOUNT
    ).call

    expect(response).to be_present
    expect(response.answer).to include("[1]")
    expect(response.sources.first[:workspace_name]).to eq("Assistant Account Secondary")
  end

  it "uses a higher-quality writing model for compose-style prompts" do
    user = User.create!(email: "assistant-compose@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Compose", slug: "assistant-compose")
    Membership.create!(workspace: workspace, user: user, role: :owner)

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:model]).to eq("gpt-4.1-mini")
      expect(args[:prompt]).to include("Generate paste-ready text")
      {
        text: "Launch highlights include QA sign-off and announcement prep.",
        usage: { prompt_tokens: 80, completion_tokens: 18, total_tokens: 98 }
      }
    end

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Write two sentences about launch readiness.",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE
    ).call

    expect(response).to be_present
    expect(response.intent).to eq(Search::AssistantQueryService::INTENT_COMPOSE)
    expect(response.auto_insert).to be(true)
    expect(response.sources).to eq([])
    expect(AiUsageLog.where(user: user, workspace: workspace, operation: AiUsageLog::OP_ASSISTANT_WRITE)).to exist
  end

  it "uses suggest-edits intent to rewrite a target block without auto insert" do
    user = User.create!(email: "assistant-suggest-edits@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Assistant Suggest Edits", slug: "assistant-suggest-edits")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Draft")
    block = Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        "type" => "doc",
        "content" => [
          {
            "type" => "paragraph",
            "content" => [ { "type" => "text", "text" => "this draft have typo and unclear phrasing" } ]
          }
        ]
      }
    )

    expect(Openai::ResponsesClient).to receive(:generate_text_with_usage) do |args|
      expect(args[:model]).to eq("gpt-4.1-mini")
      expect(args[:prompt]).to include(block.search_text)
      {
        text: "This draft has typos and unclear phrasing.",
        usage: { prompt_tokens: 90, completion_tokens: 15, total_tokens: 105 }
      }
    end

    response = described_class.new(
      user: user,
      workspace: workspace,
      prompt: "Please suggest edits for this block.",
      scope: Search::AssistantQueryService::SCOPE_WORKSPACE,
      intent: Search::AssistantQueryService::INTENT_SUGGEST_EDITS,
      target_block: block
    ).call

    expect(response).to be_present
    expect(response.intent).to eq(Search::AssistantQueryService::INTENT_SUGGEST_EDITS)
    expect(response.auto_insert).to be(false)
    expect(response.answer).to include("This draft has")
  end
end

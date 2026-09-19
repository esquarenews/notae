require "rails_helper"

RSpec.describe Search::AssistantContentSearchService do
  before do
    allow(Openai::CredentialResolver).to receive(:resolve).and_return(nil)
  end

  def create_text_block(page:, user:, text:)
    Block.create!(
      workspace: page.workspace,
      page: page,
      created_by: user,
      block_type: "paragraph",
      content_json: {
        type: "doc",
        content: [ { type: "paragraph", content: [ { type: "text", text: text } ] } ]
      }
    )
  end

  it "restricts document search to the authorized current page" do
    user = User.create!(email: "assistant-document-search@example.com", password: "password123")
    workspace = Workspace.create!(name: "Assistant Document", slug: "assistant-document")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    current_page = Page.create!(workspace: workspace, created_by: user, title: "Current document")
    other_page = Page.create!(workspace: workspace, created_by: user, title: "Other document")
    create_text_block(page: current_page, user: user, text: "heliotrope appears in this document")
    create_text_block(page: other_page, user: user, text: "heliotrope appears elsewhere")

    results = described_class.new(
      user: user,
      workspace: workspace,
      query: "find heliotrope",
      scope: "document",
      page: current_page
    ).call

    expect(results).to be_present
    expect(results.map(&:url)).to all(start_with("/w/#{workspace.slug}/pages/#{current_page.id}"))
    expect(results.map(&:url)).not_to include(a_string_including(other_page.id))
  end

  it "searches every authorized workspace for account scope and labels each result" do
    user = User.create!(email: "assistant-account-search@example.com", password: "password123")
    first_workspace = Workspace.create!(name: "Assistant First", slug: "assistant-first")
    second_workspace = Workspace.create!(name: "Assistant Second", slug: "assistant-second")
    Membership.create!(workspace: first_workspace, user: user, role: :owner)
    Membership.create!(workspace: second_workspace, user: user, role: :owner)
    first_page = Page.create!(workspace: first_workspace, created_by: user, title: "First")
    second_page = Page.create!(workspace: second_workspace, created_by: user, title: "Second")
    create_text_block(page: first_page, user: user, text: "crossworkspace beacon one")
    create_text_block(page: second_page, user: user, text: "crossworkspace beacon two")

    workspace_results = described_class.new(
      user: user,
      workspace: first_workspace,
      query: "crossworkspace beacon",
      scope: "workspace"
    ).call
    account_results = described_class.new(
      user: user,
      workspace: first_workspace,
      query: "crossworkspace beacon",
      scope: "account"
    ).call

    expect(workspace_results.map(&:workspace_name).uniq).to eq([ first_workspace.name ])
    expect(account_results.map(&:workspace_name)).to include(first_workspace.name, second_workspace.name)
  end

  it "excludes private pages and blocks hidden by Pundit policy scopes" do
    owner = User.create!(email: "assistant-private-owner@example.com", password: "password123")
    member = User.create!(email: "assistant-private-member@example.com", password: "password123")
    workspace = Workspace.create!(name: "Assistant Private", slug: "assistant-private")
    Membership.create!(workspace: workspace, user: owner, role: :owner)
    Membership.create!(workspace: workspace, user: member, role: :member)
    shared_page = Page.create!(workspace: workspace, created_by: owner, title: "Shared result")
    private_page = Page.create!(
      workspace: workspace,
      created_by: owner,
      title: "Private result",
      permission_mode: :private_page
    )
    create_text_block(page: shared_page, user: owner, text: "authorizationtoken shared")
    create_text_block(page: private_page, user: owner, text: "authorizationtoken secret")

    results = described_class.new(
      user: member,
      workspace: workspace,
      query: "authorizationtoken",
      scope: "account"
    ).call

    expect(results.map(&:url)).to include(a_string_including(shared_page.id))
    expect(results.map(&:url)).not_to include(a_string_including(private_page.id))
  end

  it "creates one reusable query embedding while semantically ranking authorized chunks across the account" do
    user = User.create!(email: "assistant-semantic-user@example.com", password: "password123")
    other_owner = User.create!(email: "assistant-semantic-owner@example.com", password: "password123")
    first_workspace = Workspace.create!(name: "Semantic First", slug: "semantic-first-assistant")
    second_workspace = Workspace.create!(name: "Semantic Second", slug: "semantic-second-assistant")
    Membership.create!(workspace: first_workspace, user: user, role: :owner)
    Membership.create!(workspace: second_workspace, user: other_owner, role: :owner)
    Membership.create!(workspace: second_workspace, user: user, role: :member)
    first_page = Page.create!(workspace: first_workspace, created_by: user, title: "Visible vector one")
    second_page = Page.create!(workspace: second_workspace, created_by: other_owner, title: "Visible vector two")
    private_page = Page.create!(
      workspace: second_workspace,
      created_by: other_owner,
      title: "Hidden vector",
      permission_mode: :private_page
    )

    [ first_page, second_page, private_page ].each_with_index do |page, index|
      SearchChunk.create!(
        workspace: page.workspace,
        source_type: SearchChunk::SOURCE_PAGE,
        source_id: page.id,
        page: page,
        chunk_index: 0,
        text: "encoded concept #{index}",
        token_count: 3,
        content_hash: "assistant-semantic-#{index}",
        embedding: [ 1.0, 0.0 ],
        embedding_model: SearchChunk::EMBEDDING_MODEL
      )
    end

    expect(Openai::CredentialResolver).to receive(:resolve).once.with(user: user).and_return("server-key")
    allow(Search::AiBudgetGuard).to receive(:within_daily_budget?).and_return(true)
    allow(Search::AiRateLimiter).to receive(:allowed?).and_return(true)
    expect(Openai::EmbeddingsClient).to receive(:embed_with_usage).once.with(
      text: "strategic alignment",
      api_key: "server-key",
      model: SearchChunk::EMBEDDING_MODEL
    ).and_return(
      embedding: [ 1.0, 0.0 ],
      usage: { prompt_tokens: 4, completion_tokens: 0, total_tokens: 4 }
    )

    results = described_class.new(
      user: user,
      workspace: first_workspace,
      query: "strategic alignment",
      scope: "account"
    ).call

    expect(results.map(&:title)).to include(first_page.title, second_page.title)
    expect(results.map(&:title)).not_to include(private_page.title)
  end

  it "returns attached files and embeds as first-class media results" do
    user = User.create!(email: "assistant-media-search@example.com", password: "password123")
    workspace = Workspace.create!(name: "Assistant Media", slug: "assistant-media")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    page = Page.create!(workspace: workspace, created_by: user, title: "Launch assets")
    image = Block.create!(workspace: workspace, page: page, created_by: user, block_type: "image")
    image.asset.attach(
      io: StringIO.new("image-bytes"),
      filename: "launch-diagram.png",
      content_type: "image/png"
    )
    embed = Block.create!(
      workspace: workspace,
      page: page,
      created_by: user,
      block_type: "embed",
      embed_url: "https://www.youtube.com/embed/launch-review"
    )

    image_result = described_class.new(
      user: user,
      workspace: workspace,
      query: "launch diagram",
      scope: "workspace"
    ).call.find { |result| result.source_id == image.id }
    embed_result = described_class.new(
      user: user,
      workspace: workspace,
      query: "youtube launch review",
      scope: "workspace"
    ).call.find { |result| result.source_id == embed.id }

    expect(image_result.kind).to eq("Image")
    expect(image_result.media).to include(
      filename: "launch-diagram.png",
      content_type: "image/png",
      page_id: page.id,
      workspace_id: workspace.id,
      page_url: "/w/#{workspace.slug}/pages/#{page.id}",
      workspace_url: "/w/#{workspace.slug}"
    )
    expect(image_result.url).to eq("/w/#{workspace.slug}/pages/#{page.id}#block_#{image.id}")
    expect(embed_result.kind).to eq("Embed")
    expect(embed_result.media[:embed_url]).to eq(embed.embed_url)
  end
end

require "rails_helper"

RSpec.describe Epistularium::DraftSuggestionService do
  it "creates a reply draft action with source-email provenance" do
    user = User.create!(email: "epistularium-draft@example.com", password: "password123", openai_api_key: "sk-test")
    workspace = Workspace.create!(name: "Epistularium Draft", slug: "epistularium-draft")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "Inbox",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com" }
    )
    message = EpistulariumMessage.create!(
      workspace: workspace,
      epistularium_account: account,
      provider_message_id: "msg-1",
      subject: "Review request",
      from_name: "Alex",
      from_email: "alex@example.com",
      body_text: "Can you review the launch plan?"
    )

    allow(Openai::ResponsesClient).to receive(:generate_text_with_usage).and_return(
      {
        text: {
          title: "Reply to Alex about launch plan",
          payload: {
            to: [ "alex@example.com" ],
            cc: [],
            subject: "Re: Review request",
            body: "I will review the launch plan this afternoon."
          }
        }.to_json,
        usage: { prompt_tokens: 150, completion_tokens: 60, total_tokens: 210 }
      }
    )

    agent_action = described_class.new(
      user: user,
      workspace: workspace,
      message: message,
      suggestion_type: "reply"
    ).call

    expect(Openai::ResponsesClient).to have_received(:generate_text_with_usage).with(
      hash_including(
        model: "gpt-5.6-luna",
        reasoning: { effort: "none" },
        prompt_cache_key: "notae-email-draft-v1",
        prompt_cache_options: { ttl: "30m" }
      )
    )
    expect(agent_action.target_system).to eq("email")
    expect(agent_action.draft_type).to eq("email_draft")
    expect(agent_action.payload["subject"]).to eq("Re: Review request")
    expect(agent_action.metadata_json["source_email_id"]).to eq(message.id)
  end
end

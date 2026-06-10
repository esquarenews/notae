require "rails_helper"

RSpec.describe User, type: :model do
  it "requires email for authentication" do
    user = described_class.new(password: "password123")

    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("can't be blank")
  end

  it "has workspace memberships" do
    association = described_class.reflect_on_association(:memberships)

    expect(association.macro).to eq(:has_many)
  end

  it "resolves SaaS workspace limits from the user tier with optional overrides" do
    free_user = described_class.new(email: "free-tier@example.com", password: "password123", saas_plan_key: described_class::SAAS_PLAN_FREE)
    starter_user = described_class.new(email: "starter-tier@example.com", password: "password123", saas_plan_key: described_class::SAAS_PLAN_STARTER)
    team_user = described_class.new(email: "team-tier@example.com", password: "password123", saas_plan_key: described_class::SAAS_PLAN_TEAM)
    business_user = described_class.new(email: "business-tier@example.com", password: "password123", saas_plan_key: described_class::SAAS_PLAN_BUSINESS)

    expect(free_user.workspace_limit).to be_nil
    expect(free_user).to be_workspace_limit_unlimited
    expect(starter_user.workspace_limit).to eq(10)
    expect(team_user.workspace_limit).to eq(50)
    expect(business_user.workspace_limit).to be_nil
    expect(business_user).to be_workspace_limit_unlimited

    starter_user.workspace_limit_override = 12

    expect(starter_user.workspace_limit).to eq(12)
  end

  it "falls back to the free tier while SaaS plan columns are unavailable during deploys" do
    user = described_class.new(email: "pre-migration-tier@example.com", password: "password123")
    column_names_without_saas_plan = described_class.column_names - %w[saas_plan_key workspace_limit_override]
    allow(described_class).to receive(:column_names).and_return(column_names_without_saas_plan)

    user.saas_plan_key = described_class::SAAS_PLAN_TEAM
    user.workspace_limit_override = "12"

    expect(user.saas_plan_key).to eq(described_class::SAAS_PLAN_TEAM)
    expect(user.workspace_limit_override).to eq(12)
    expect(user).to be_valid
  end

  it "blocks authentication while suspended or removed by an admin" do
    user = described_class.create!(email: "admin-state-user@example.com", password: "password123")

    expect(user).to be_active_for_authentication

    user.suspend_for_week!

    expect(user).to be_admin_suspended
    expect(user).not_to be_active_for_authentication
    expect(user.inactive_message).to eq(:admin_suspended)

    user.update!(admin_suspended_until: 1.minute.ago)

    expect(user).to be_active_for_authentication

    user.remove_account!

    expect(user).to be_removed
    expect(user).not_to be_active_for_authentication
    expect(user.inactive_message).to eq(:removed_account)
  end

  it "blocks expired self-service trials unless the user has a paid active workspace subscription" do
    user = described_class.create!(
      email: "expired-trial-user@example.com",
      password: "password123",
      saas_plan_key: described_class::SAAS_PLAN_STARTER,
      trial_ends_at: 1.hour.ago
    )

    expect(user).not_to be_active_for_authentication
    expect(user.inactive_message).to eq(:trial_expired)

    workspace = Workspace.create!(name: "Paid Trial Conversion", slug: "paid-trial-conversion")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    workspace.create_workspace_subscription!(
      plan_key: WorkspaceSubscription::PLAN_STARTER,
      status: WorkspaceSubscription::STATUS_ACTIVE
    )

    expect(user).to be_active_for_authentication
  end

  it "reinstates removed users on the free tier for one week" do
    user = described_class.create!(
      email: "reinstated-user@example.com",
      password: "password123",
      saas_plan_key: described_class::SAAS_PLAN_TEAM,
      workspace_limit_override: 8,
      removed_at: Time.current
    )

    user.reinstate_free_tier_for_week!

    expect(user).not_to be_removed
    expect(user).not_to be_admin_suspended
    expect(user.saas_plan_key).to eq(described_class::SAAS_PLAN_FREE)
    expect(user.workspace_limit_override).to be_nil
    expect(user.admin_free_tier_ends_at).to be_within(5.seconds).of(1.week.from_now)
  end

  it "logs background Devise notification delivery failures" do
    delivery = instance_double(ActionMailer::MessageDelivery)
    allow(delivery).to receive(:deliver_now).and_raise(Net::SMTPFatalError, "SMTP unavailable")
    allow(Rails.logger).to receive(:error)

    thread = described_class.deliver_devise_notification_in_background(delivery, :confirmation_instructions)
    thread.join

    expect(Rails.logger).to have_received(:error).with(
      "[DeviseMailDelivery] notification=confirmation_instructions error_class=Net::SMTPFatalError error_message=SMTP unavailable"
    )
  end

  it "uses in-process background delivery for Devise notifications when configured" do
    user = described_class.new(email: "in-process-confirmation-user@example.com", password: "password123")
    delivery = instance_double(ActionMailer::MessageDelivery)
    mailer = class_double(Devise::Mailer)

    allow(mailer).to receive(:confirmation_instructions).with(user, "token", {}).and_return(delivery)
    allow(user).to receive(:devise_mailer).and_return(mailer)
    allow(described_class).to receive(:deliver_devise_notifications_in_process?).and_return(true)
    allow(described_class).to receive(:deliver_devise_notification_in_background)

    user.send_devise_notification(:confirmation_instructions, "token", {})

    expect(described_class).to have_received(:deliver_devise_notification_in_background)
      .with(delivery, :confirmation_instructions)
  end

  it "requires complete SMTP settings when any SMTP field is provided" do
    user = described_class.new(email: "smtp-user@example.com", password: "password123", smtp_address: "smtp.example.com")

    expect(user).not_to be_valid
    expect(user.errors[:smtp_port]).to include("can't be blank")
    expect(user.errors[:smtp_username]).to include("can't be blank")
    expect(user.errors[:smtp_password]).to include("can't be blank")
    expect(user.errors[:smtp_from_email]).to include("can't be blank")
  end

  it "rejects SMTP hosts targeting local or private networks" do
    user = described_class.new(
      email: "smtp-private-host@example.com",
      password: "password123",
      smtp_address: "localhost",
      smtp_port: 587,
      smtp_username: "smtp-user",
      smtp_password: "smtp-password-123",
      smtp_from_email: "noreply@example.com"
    )

    expect(user).not_to be_valid
    expect(user.errors[:smtp_address]).to include("must use a public host")
  end

  it "reports SMTP configuration and sender display values" do
    user = described_class.new(
      email: "smtp-ready@example.com",
      password: "password123",
      smtp_address: "smtp.example.com",
      smtp_port: 587,
      smtp_username: "smtp-user",
      smtp_password: "smtp-password-123",
      smtp_from_name: "Notae Bot",
      smtp_from_email: "noreply@example.com"
    )

    expect(user.smtp_configured?).to be(true)
    expect(user.smtp_from_display).to eq("Notae Bot <noreply@example.com>")
    expect(user.masked_smtp_password).to eq("sm...23")
  end

  it "encrypts AI and SMTP credential fields at rest" do
    user = described_class.create!(
      email: "encrypted-credentials@example.com",
      password: "password123",
      openai_api_key: "sk-test-abc123",
      smtp_address: "smtp.example.com",
      smtp_port: 587,
      smtp_domain: "example.com",
      smtp_username: "smtp-user",
      smtp_password: "smtp-password-123",
      smtp_from_name: "Notae Team",
      smtp_from_email: "noreply@example.com"
    )
    user.reload

    expect(user.attributes_before_type_cast["openai_api_key"]).not_to eq("sk-test-abc123")
    expect(user.attributes_before_type_cast["smtp_username"]).not_to eq("smtp-user")
    expect(user.attributes_before_type_cast["smtp_password"]).not_to eq("smtp-password-123")
    expect(user.openai_api_key).to eq("sk-test-abc123")
    expect(user.smtp_username).to eq("smtp-user")
    expect(user.smtp_password).to eq("smtp-password-123")
  end

  it "configures active record encryption keys at boot" do
    encryption_config = Rails.application.config.active_record.encryption

    expect(encryption_config.primary_key).to be_present
    expect(encryption_config.deterministic_key).to be_present
    expect(encryption_config.key_derivation_salt).to be_present
  end

  it "fails closed when encryption keys are missing instead of raising" do
    user = described_class.new(email: "missing-encryption@example.com", password: "password123")
    configuration_error = ActiveRecord::Encryption::Errors::Configuration.new("Missing key")
    allow(user).to receive(:openai_api_key).and_raise(configuration_error)
    allow(user).to receive(:smtp_password).and_raise(configuration_error)

    expect(user.openai_api_key_configured?).to be(false)
    expect(user.masked_openai_api_key).to eq("Not configured")
    expect(user.masked_smtp_password).to eq("Not configured")
  end

  it "supports per-type push notification preferences" do
    user = described_class.new(
      email: "push-preferences@example.com",
      password: "password123",
      push_notification_preferences: {
        Notification::TYPE_MENTION => false,
        Notification::TYPE_WORKFLOW_FAILED => true
      }
    )

    expect(user.push_notification_enabled_for?(Notification::TYPE_MENTION)).to be(false)
    expect(user.push_notification_enabled_for?(Notification::TYPE_WORKFLOW_FAILED)).to be(true)
    expect(user.push_notification_enabled_for?(Notification::TYPE_CALENDAR_REMINDER)).to be(true)
  end

  it "applies quiet hours to routine notifications but exempts workflow failures" do
    user = described_class.new(
      email: "push-quiet-hours@example.com",
      password: "password123",
      time_zone: "Australia/Melbourne",
      push_quiet_hours_enabled: true,
      push_quiet_hours_starts_at: "22:00",
      push_quiet_hours_ends_at: "07:00"
    )
    within_quiet_hours = Time.find_zone!("Australia/Melbourne").parse("2026-04-18 23:15")

    expect(user.push_quiet_hours_active_for?(Notification::TYPE_MENTION, at: within_quiet_hours)).to be(true)
    expect(user.push_delivery_allowed_for?(Notification::TYPE_MENTION, at: within_quiet_hours)).to be(false)
    expect(user.push_quiet_hours_active_for?(Notification::TYPE_WORKFLOW_FAILED, at: within_quiet_hours)).to be(false)
    expect(user.push_delivery_allowed_for?(Notification::TYPE_WORKFLOW_FAILED, at: within_quiet_hours)).to be(true)
  end

  it "respects workspace-scoped email overrides" do
    user = described_class.create!(
      email: "workspace-email-override@example.com",
      password: "password123",
      email_notify_activity: false
    )
    workspace = Workspace.create!(name: "Workspace Email Override", slug: "workspace-email-override")
    membership = Membership.create!(
      workspace: workspace,
      user: user,
      role: :owner,
      notification_preferences_json: { "email_notify_activity" => true }
    )

    expect(user.email_notify_activity_for?(workspace, membership: membership)).to be(true)
    expect(user.email_notify_activity_for?(workspace)).to be(true)
  end

  it "respects workspace-scoped push notification overrides" do
    user = described_class.create!(
      email: "workspace-push-override@example.com",
      password: "password123",
      push_notification_preferences: { Notification::TYPE_MENTION => true }
    )
    workspace = Workspace.create!(name: "Workspace Push Override", slug: "workspace-push-override")
    membership = Membership.create!(
      workspace: workspace,
      user: user,
      role: :owner,
      notification_preferences_json: {
        "push_notification_preferences" => {
          Notification::TYPE_MENTION => false
        }
      }
    )

    expect(user.push_notification_enabled_for?(Notification::TYPE_MENTION)).to be(true)
    expect(user.push_notification_enabled_for?(Notification::TYPE_MENTION, workspace: workspace, membership: membership)).to be(false)
    expect(user.push_delivery_allowed_for?(Notification::TYPE_MENTION, workspace: workspace, membership: membership)).to be(false)
  end
end

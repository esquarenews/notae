require "rails_helper"

RSpec.describe Epistularium::Providers::ImapAdapter do
  before do
    allow(Notae::OutboundNetworkGuard).to receive(:public_resolved_host?).and_return(true)
  end

  def build_stack(suffix:)
    user = User.create!(email: "epistularium-imap-#{suffix}@example.com", password: "password123")
    workspace = Workspace.create!(name: "Epistularium IMAP #{suffix}", slug: "epistularium-imap-#{suffix}")
    Membership.create!(workspace: workspace, user: user, role: :owner)
    account = EpistulariumAccount.create!(
      workspace: workspace,
      owner: user,
      created_by: user,
      provider: "imap",
      label: "IMAP",
      provider_username: "me@example.com",
      provider_password: "secret",
      settings_json: { "imap_host" => "imap.example.com", "sent_mailbox" => "Sent" }
    )

    [ user, workspace, account ]
  end

  it "blocks IMAP sync when the configured host resolves to a private address" do
    _user, _workspace, account = build_stack(suffix: "private-resolved-host")
    allow(Notae::OutboundNetworkGuard).to receive(:public_resolved_host?).with("imap.example.com").and_return(false)

    expect(Net::IMAP).not_to receive(:new)

    expect { described_class.new(account: account).sync! }
      .to raise_error("IMAP host must use a public host.")
  end

  it "imports messages from inbox and sent folders via IMAP" do
    _user, _workspace, account = build_stack(suffix: "import")
    imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:list).and_return([ instance_double(Net::IMAP::MailboxList) ])
    allow(imap).to receive(:select)
    allow(imap).to receive(:uid_search).and_return([ 101 ], [ 202 ])

    inbox_message = Struct.new(:attr).new(
      {
        "RFC822" => <<~MAIL,
          From: Alex <alex@example.com>
          To: Team <team@example.com>
          Subject: IMAP launch note
          Date: Tue, 18 Mar 2026 16:00:00 +1100
          Message-ID: <imap-1@example.com>
          MIME-Version: 1.0
          Content-Type: text/plain; charset=UTF-8

          Please review the IMAP launch note.
        MAIL
        "FLAGS" => [],
        "INTERNALDATE" => Time.utc(2026, 3, 18, 5, 0, 0)
      }
    )
    sent_message = Struct.new(:attr).new(
      {
        "RFC822" => <<~MAIL,
          From: Me <me@example.com>
          To: Alex <alex@example.com>
          Subject: Sent via IMAP
          Date: Tue, 18 Mar 2026 18:00:00 +1100
          Message-ID: <imap-2@example.com>
          MIME-Version: 1.0
          Content-Type: text/plain; charset=UTF-8

          Sent IMAP response.
        MAIL
        "FLAGS" => [ "\\Seen" ],
        "INTERNALDATE" => Time.utc(2026, 3, 18, 7, 0, 0)
      }
    )
    allow(imap).to receive(:uid_fetch).and_return([ inbox_message ], [ sent_message ])

    described_class.new(account: account).sync!

    expect(imap).to have_received(:uid_fetch).with(101, [ "BODY.PEEK[]", "FLAGS", "INTERNALDATE" ])
    expect(imap).to have_received(:uid_fetch).with(202, [ "BODY.PEEK[]", "FLAGS", "INTERNALDATE" ])
    expect(account.epistularium_messages.count).to eq(2)
    inbox = account.epistularium_messages.find_by(provider_message_id: "inbox:101")
    expect(inbox.mailbox).to eq("inbox")
    expect(inbox.unread).to eq(true)
    expect(inbox.body_text).to include("IMAP launch note")

    sent = account.epistularium_messages.find_by(provider_message_id: "sent:202")
    expect(sent.mailbox).to eq("sent")
    expect(sent.unread).to eq(false)
  end

  it "imports nested multipart IMAP messages without raising the multipart decode error" do
    _user, _workspace, account = build_stack(suffix: "nested-multipart")
    imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:list).and_return([ instance_double(Net::IMAP::MailboxList) ])
    allow(imap).to receive(:select)
    allow(imap).to receive(:uid_search).and_return([ 101 ], [])
    allow(imap).to receive(:uid_fetch).and_return(
      [
        Struct.new(:attr).new(
          {
            "RFC822" => <<~MAIL,
              From: Alex <alex@example.com>
              To: Team <team@example.com>
              Subject: Nested multipart
              Date: Tue, 18 Mar 2026 16:00:00 +1100
              Message-ID: <imap-nested@example.com>
              MIME-Version: 1.0
              Content-Type: multipart/mixed; boundary="mix"

              --mix
              Content-Type: multipart/alternative; boundary="alt"

              --alt
              Content-Type: text/plain; charset=UTF-8

              Plain body from nested multipart.
              --alt
              Content-Type: text/html; charset=UTF-8

              <p><strong>HTML body</strong> from nested multipart.</p>
              --alt--
              --mix--
            MAIL
            "FLAGS" => [],
            "INTERNALDATE" => Time.utc(2026, 3, 18, 5, 0, 0)
          }
        )
      ],
      []
    )

    expect { described_class.new(account: account).sync! }.not_to raise_error

    message = account.epistularium_messages.find_by!(provider_message_id: "inbox:101")
    expect(message.body_text).to include("Plain body from nested multipart.")
    expect(message.body_html).to include("<strong>HTML body</strong> from nested multipart.")
  end

  it "strips stylesheet markup from imported HTML emails while preserving readable body content" do
    _user, _workspace, account = build_stack(suffix: "html-clean")
    imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:list).and_return([ instance_double(Net::IMAP::MailboxList) ])
    allow(imap).to receive(:select)
    allow(imap).to receive(:uid_search).and_return([ 101 ], [])
    allow(imap).to receive(:uid_fetch).and_return(
      [
        Struct.new(:attr).new(
          {
            "RFC822" => <<~MAIL,
              From: Alex <alex@example.com>
              To: Team <team@example.com>
              Subject: Styled HTML mail
              Date: Tue, 18 Mar 2026 16:00:00 +1100
              Message-ID: <imap-html@example.com>
              MIME-Version: 1.0
              Content-Type: text/html; charset=UTF-8

              <html>
                <head>
                  <style>
                    .email-body { font-family: Helvetica; }
                  </style>
                </head>
                <body>
                  <div class="preheader">This should stay hidden.</div>
                  <div class="email-body">
                    <p>Readable newsletter body.</p>
                  </div>
                </body>
              </html>
            MAIL
            "FLAGS" => [],
            "INTERNALDATE" => Time.utc(2026, 3, 18, 5, 0, 0)
          }
        )
      ],
      []
    )

    described_class.new(account: account).sync!

    message = account.epistularium_messages.find_by!(provider_message_id: "inbox:101")
    expect(message.body_html).to include("Readable newsletter body.")
    expect(message.body_html).not_to include("font-family")
    expect(message.body_html).not_to include("This should stay hidden.")
    expect(message.body_text).to include("Readable newsletter body.")
    expect(message.body_text).not_to include("This should stay hidden.")
  end

  it "stores html-like text/plain IMAP bodies as renderable html" do
    _user, _workspace, account = build_stack(suffix: "html-in-text")
    imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:list).and_return([ instance_double(Net::IMAP::MailboxList) ])
    allow(imap).to receive(:select)
    allow(imap).to receive(:uid_search).and_return([ 101 ], [])
    allow(imap).to receive(:uid_fetch).and_return(
      [
        Struct.new(:attr).new(
          {
            "RFC822" => <<~MAIL,
              From: Alex <alex@example.com>
              To: Team <team@example.com>
              Subject: HTML disguised as text
              Date: Tue, 18 Mar 2026 16:00:00 +1100
              Message-ID: <imap-html-text@example.com>
              MIME-Version: 1.0
              Content-Type: text/plain; charset=UTF-8

              <div class="preheader">This should stay hidden.</div>
              <p>Hello from HTML-like text/plain content.</p>
              <p><strong>Formatting should survive.</strong></p>
            MAIL
            "FLAGS" => [],
            "INTERNALDATE" => Time.utc(2026, 3, 18, 5, 0, 0)
          }
        )
      ],
      []
    )

    described_class.new(account: account).sync!

    message = account.epistularium_messages.find_by!(provider_message_id: "inbox:101")
    expect(message.body_html).to include("Hello from HTML-like text/plain content.")
    expect(message.body_html).to include("<strong>Formatting should survive.</strong>")
    expect(message.body_html).not_to include("This should stay hidden.")
    expect(message.body_text).to include("Hello from HTML-like text/plain content.")
    expect(message.body_text).not_to include("<strong>")
  end

  it "removes leading css boilerplate from malformed html email bodies" do
    _user, _workspace, account = build_stack(suffix: "css-preamble")
    imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:list).and_return([ instance_double(Net::IMAP::MailboxList) ])
    allow(imap).to receive(:select)
    allow(imap).to receive(:uid_search).and_return([ 101 ], [])
    allow(imap).to receive(:uid_fetch).and_return(
      [
        Struct.new(:attr).new(
          {
            "RFC822" => <<~MAIL,
              From: Alex <alex@example.com>
              To: Team <team@example.com>
              Subject: CSS preamble html
              Date: Tue, 18 Mar 2026 16:00:00 +1100
              Message-ID: <imap-css-preamble@example.com>
              MIME-Version: 1.0
              Content-Type: text/html; charset=UTF-8

              /* What it does: Stops email clients resizing small text. */
              * { -ms-text-size-adjust: 100%; -webkit-text-size-adjust: 100%; }
              table, td { border-collapse: collapse !important; mso-table-lspace: 0pt !important; }
              @media screen and (max-width: 600px) { .email-container { width: 100% !important; } }
              <table>
                <tr>
                  <td>
                    <h1>Parent Teacher Student Interviews</h1>
                    <p>Dear family, the interview schedule is now available.</p>
                  </td>
                </tr>
              </table>
            MAIL
            "FLAGS" => [],
            "INTERNALDATE" => Time.utc(2026, 3, 18, 5, 0, 0)
          }
        )
      ],
      []
    )

    described_class.new(account: account).sync!

    message = account.epistularium_messages.find_by!(provider_message_id: "inbox:101")
    expect(message.body_html).to include("Parent Teacher Student Interviews")
    expect(message.body_html).to include("Dear family, the interview schedule is now available.")
    expect(message.body_html).not_to include("-webkit-text-size-adjust")
    expect(message.body_html).not_to include("border-collapse")
    expect(message.body_text).to include("Parent Teacher Student Interviews")
    expect(message.body_text).not_to include("-webkit-text-size-adjust")
  end

  it "can bootstrap only the newest IMAP messages without advancing full-backfill state" do
    _user, _workspace, account = build_stack(suffix: "bootstrap")
    imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:list).and_return([ instance_double(Net::IMAP::MailboxList) ])
    allow(imap).to receive(:select)
    allow(imap).to receive(:uid_search).and_return([ 101, 102, 103 ], [ 201, 202 ])

    fetch_payloads = {
      103 => Struct.new(:attr).new(
        {
          "RFC822" => <<~MAIL,
            From: Alex <alex@example.com>
            To: Team <team@example.com>
            Subject: Latest inbox message
            Date: Tue, 18 Mar 2026 19:00:00 +1100
            Message-ID: <imap-bootstrap-inbox@example.com>
            MIME-Version: 1.0
            Content-Type: text/plain; charset=UTF-8

            Latest inbox body.
          MAIL
          "FLAGS" => [],
          "INTERNALDATE" => Time.utc(2026, 3, 18, 8, 0, 0)
        }
      ),
      202 => Struct.new(:attr).new(
        {
          "RFC822" => <<~MAIL,
            From: Me <me@example.com>
            To: Alex <alex@example.com>
            Subject: Latest sent message
            Date: Tue, 18 Mar 2026 20:00:00 +1100
            Message-ID: <imap-bootstrap-sent@example.com>
            MIME-Version: 1.0
            Content-Type: text/plain; charset=UTF-8

            Latest sent body.
          MAIL
          "FLAGS" => [ "\\Seen" ],
          "INTERNALDATE" => Time.utc(2026, 3, 18, 9, 0, 0)
        }
      )
    }
    allow(imap).to receive(:uid_fetch) { |uid, _fields| [ fetch_payloads.fetch(uid) ] }

    described_class.new(account: account).sync!(
      full_backfill: false,
      max_messages_per_mailbox: 1,
      update_cursor: false
    )

    expect(account.reload.sync_cursor).to be_blank
    expect(account.settings_json["full_backfill_completed_at"]).to be_blank
    expect(account.epistularium_messages.pluck(:provider_message_id)).to contain_exactly("inbox:103", "sent:202")
  end

  it "processes IMAP full backfills in bounded batches and reports when more history remains" do
    _user, _workspace, account = build_stack(suffix: "batched-backfill")
    imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:list).and_return([ instance_double(Net::IMAP::MailboxList) ])
    allow(imap).to receive(:select)
    allow(imap).to receive(:uid_search).and_return([ 101, 102, 103 ], [ 201, 202, 203 ])

    fetch_payloads = {
      102 => Struct.new(:attr).new(
        {
          "RFC822" => <<~MAIL,
            From: Alex <alex@example.com>
            To: Team <team@example.com>
            Subject: Inbox batch item 102
            Date: Tue, 18 Mar 2026 18:00:00 +1100
            Message-ID: <imap-batch-102@example.com>
            MIME-Version: 1.0
            Content-Type: text/plain; charset=UTF-8

            Inbox batch 102.
          MAIL
          "FLAGS" => [],
          "INTERNALDATE" => Time.utc(2026, 3, 18, 7, 0, 0)
        }
      ),
      103 => Struct.new(:attr).new(
        {
          "RFC822" => <<~MAIL,
            From: Alex <alex@example.com>
            To: Team <team@example.com>
            Subject: Inbox batch item 103
            Date: Tue, 18 Mar 2026 19:00:00 +1100
            Message-ID: <imap-batch-103@example.com>
            MIME-Version: 1.0
            Content-Type: text/plain; charset=UTF-8

            Inbox batch 103.
          MAIL
          "FLAGS" => [],
          "INTERNALDATE" => Time.utc(2026, 3, 18, 8, 0, 0)
        }
      ),
      202 => Struct.new(:attr).new(
        {
          "RFC822" => <<~MAIL,
            From: Me <me@example.com>
            To: Alex <alex@example.com>
            Subject: Sent batch item 202
            Date: Tue, 18 Mar 2026 20:00:00 +1100
            Message-ID: <imap-batch-202@example.com>
            MIME-Version: 1.0
            Content-Type: text/plain; charset=UTF-8

            Sent batch 202.
          MAIL
          "FLAGS" => [ "\\Seen" ],
          "INTERNALDATE" => Time.utc(2026, 3, 18, 9, 0, 0)
        }
      ),
      203 => Struct.new(:attr).new(
        {
          "RFC822" => <<~MAIL,
            From: Me <me@example.com>
            To: Alex <alex@example.com>
            Subject: Sent batch item 203
            Date: Tue, 18 Mar 2026 21:00:00 +1100
            Message-ID: <imap-batch-203@example.com>
            MIME-Version: 1.0
            Content-Type: text/plain; charset=UTF-8

            Sent batch 203.
          MAIL
          "FLAGS" => [ "\\Seen" ],
          "INTERNALDATE" => Time.utc(2026, 3, 18, 10, 0, 0)
        }
      )
    }
    allow(imap).to receive(:uid_fetch) { |uid, _fields| [ fetch_payloads.fetch(uid) ] }

    result = described_class.new(account: account).sync!(
      full_backfill: true,
      max_messages_per_mailbox: 2,
      update_cursor: true
    )

    expect(result).to include(backfill_remaining: true)
    expect(account.reload.settings_json["imap_backfill_before_uid_inbox"]).to eq(102)
    expect(account.settings_json["imap_backfill_before_uid_sent"]).to eq(202)
    expect(account.settings_json["full_backfill_completed_at"]).to be_blank
    expect(account.epistularium_messages.pluck(:provider_message_id)).to contain_exactly("inbox:102", "inbox:103", "sent:202", "sent:203")
  end

  it "limits IMAP full-backfill searches to the last 12 months and defaults batches to 50 messages per mailbox" do
    _user, _workspace, account = build_stack(suffix: "backfill-window")
    imap = instance_double(Net::IMAP)
    allow(Net::IMAP).to receive(:new).and_return(imap)
    allow(imap).to receive(:login)
    allow(imap).to receive(:logout)
    allow(imap).to receive(:disconnect)
    allow(imap).to receive(:list).and_return([ instance_double(Net::IMAP::MailboxList) ])
    allow(imap).to receive(:select)

    cutoff = Epistularium::SyncConfig.backfill_cutoff_date.strftime("%d-%b-%Y")
    allow(imap).to receive(:uid_search).with([ "SINCE", cutoff ]).and_return((1..60).to_a, (101..160).to_a)
    allow(imap).to receive(:uid_fetch) do |uid, _fields|
      mailbox = uid < 100 ? "Inbox" : "Sent"
      from_line = uid < 100 ? "From: Alex <alex@example.com>\nTo: Team <team@example.com>" : "From: Me <me@example.com>\nTo: Alex <alex@example.com>"
      seen_flags = uid < 100 ? [] : [ "\\Seen" ]
      [
        Struct.new(:attr).new(
          {
            "RFC822" => <<~MAIL,
              #{from_line}
              Subject: #{mailbox} batch item #{uid}
              Date: Tue, 18 Mar 2026 18:00:00 +1100
              Message-ID: <imap-backfill-window-#{uid}@example.com>
              MIME-Version: 1.0
              Content-Type: text/plain; charset=UTF-8

              #{mailbox} batch #{uid}.
            MAIL
            "FLAGS" => seen_flags,
            "INTERNALDATE" => Time.utc(2026, 3, 18, 7, 0, 0)
          }
        )
      ]
    end

    result = described_class.new(account: account).sync!(
      full_backfill: true,
      update_cursor: true
    )

    expect(result).to include(backfill_remaining: true)
    expect(account.reload.settings_json["imap_backfill_before_uid_inbox"]).to eq(11)
    expect(account.settings_json["imap_backfill_before_uid_sent"]).to eq(111)
    expect(account.epistularium_messages.where(mailbox: "inbox").count).to eq(50)
    expect(account.epistularium_messages.where(mailbox: "sent").count).to eq(50)
  end

  it "translates SMTP endpoint protocol failures into a clearer IMAP host error" do
    _user, _workspace, account = build_stack(suffix: "smtp-endpoint")
    account.update_columns(
      provider: "amazon_workmail",
      settings_json: account.settings_json.to_h.merge("imap_host" => "smtp.eu-west-1.mail.awsapps.com"),
      updated_at: Time.current
    )

    response = instance_double("Net::IMAP::UntaggedResponse", data: instance_double("Net::IMAP::ResponseText", text: 'bad response type "SMTP.EU-WEST-1.MAIL.AWSAPPS.COM", expected OK or NO or BAD'))
    allow(Net::IMAP).to receive(:new).and_raise(Net::IMAP::BadResponseError.new(response))

    expect do
      described_class.new(account: account).sync!
    end.to raise_error(RuntimeError, /Amazon WorkMail IMAP host is pointing at SMTP/)
  end

  it "translates Amazon WorkMail access denied responses into actionable auth guidance" do
    _user, _workspace, account = build_stack(suffix: "access-denied")
    account.update_columns(
      provider: "amazon_workmail",
      provider_username: "errol",
      settings_json: account.settings_json.to_h.merge("imap_host" => "imap.mail.eu-west-1.awsapps.com"),
      updated_at: Time.current
    )

    response = instance_double("Net::IMAP::UntaggedResponse", data: instance_double("Net::IMAP::ResponseText", text: "Access Denied."))
    allow(Net::IMAP).to receive(:new).and_raise(Net::IMAP::NoResponseError.new(response))

    expect do
      described_class.new(account: account).sync!
    end.to raise_error(RuntimeError, /Use the full mailbox email address as the username/)
  end
end

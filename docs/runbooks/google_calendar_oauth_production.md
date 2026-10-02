# Google Calendar OAuth production setup

Notae requests these least-privilege Calendar scopes:

- `https://www.googleapis.com/auth/calendar.events`
- `https://www.googleapis.com/auth/calendar.calendarlist.readonly`

The production OAuth client must use this exact redirect URI:

```text
https://notae.esquarenews.tech/kalendarium/google/callback
```

## Google Cloud setup

After deploying the public legal pages, use these Branding URLs:

- Homepage: `https://notae.esquarenews.tech/`
- Privacy policy: `https://notae.esquarenews.tech/privacy`
- Terms of use: `https://notae.esquarenews.tech/terms`

Confirm both policy URLs return HTTP 200 without authentication before submitting verification.

1. Use a dedicated Google Cloud project for production and enable the Google Calendar API.
2. In Google Auth Platform > Branding, set the app name, support email, homepage, privacy policy, terms URL, authorized domain, and developer contacts. Verify ownership of the production domain.
3. In Audience, choose External for consumer Google accounts, then select **Publish app**. If Notae is restricted to one Google Workspace organization, an Internal audience can be used instead and does not require external verification.
4. In Data Access, declare both scopes above. Explain that Notae lists calendars read-only and reads, creates, updates, and deletes calendar events selected by the user.
5. Submit the sensitive-scope verification request. Include a demo video showing sign-in, the consent screen, calendar selection, event sync, event creation/editing/deletion, and account disconnection.
6. In Clients, create or update the production Web application client and add the exact redirect URI above. Do not include local or staging redirect URIs in the production client.
7. Set the production `GOOGLE_OAUTH_CLIENT_ID` and `GOOGLE_OAUTH_CLIENT_SECRET`, deploy, and restart the application.
8. Disconnect and reconnect each existing Google Calendar connection once so Google issues a refresh token for the production client and the new scopes.

Keep a separate Testing project/client for local development. External apps left in Testing issue refresh tokens that expire after seven days.

Official references:

- https://developers.google.com/identity/protocols/oauth2/production-readiness/overview
- https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification
- https://developers.google.com/workspace/calendar/api/auth

# Notae Google Meet Transcript Extension

This unpacked Chrome extension captures live Google Meet captions and uploads the transcript to Notae.

## Load locally

1. Open `chrome://extensions`.
2. Turn on **Developer mode**.
3. Click **Load unpacked**.
4. Choose the `browser_extensions/notae_google_meet_transcript` folder from this repo.

## Configure

Open Notae -> **Meetings** and generate a **Google Meet extension token** for the target workspace.

Then open the extension popup and enter:

- Notae base URL, for example `http://localhost:4000`
- Workspace slug
- Extension token

If you already have the target Notae workspace open in another tab in the same browser window, the popup will offer a **Use detected workspace** button to fill the base URL and workspace slug for you.

## Use

1. Join a Google Meet in Chrome.
2. Turn on captions in Meet.
3. Open the extension popup and click **Start capture**.
4. When the meeting is done, click **Stop & sync**.
5. Use **Open Nota** from the popup or open the linked meeting Nota in Notae.

## Notes

- This extension captures transcript text only. It does not record raw audio or video.
- The current implementation is intended for internal testing and uses broad host permissions so it can talk to local development and deployed Notae environments.

# CallNotes

CallNotes is an iPhone app for capturing spoken call notes after you explicitly start recording. It records from the microphone, sends the finished audio to OpenAI for multilingual transcription and task extraction, and can optionally save selected tasks to Apple Reminders.

## What It Does

- Starts and stops recording from the app.
- Exposes App Shortcuts for quick start and stop.
- Includes a WidgetKit quick-start widget.
- Includes a Live Activity surface for visible recording state and a quick stop action.
- Uploads the final recording to OpenAI after you stop.
- Extracts a focused list of follow-up tasks from the transcript.
- Stores recordings and metadata locally in the app container.

## What It Does Not Do

- It cannot monitor or intercept all incoming calls from Phone, FaceTime, WhatsApp, Teams, Zoom, or other apps.
- It does not capture other apps' call audio.
- It does not auto-start recording.
- It does not rely on BackgroundTasks for precise real-time triggers.

The user must start capture manually from the app, widget, App Shortcut, or a reminder notification action. Background execution is limited by iOS and should be treated as opportunistic.

## Permissions And Capabilities

- `NSMicrophoneUsageDescription`: required for recording.
- `NSRemindersUsageDescription`: required for exporting action items to Reminders.
- `UserNotifications`: optional reminder prompts with `Start`, `Later`, and `Dismiss`.
- `ActivityKit`: lock screen and Dynamic Island recording visibility.
- `BackgroundTasks`: deferred post-processing and cleanup only.

## Project Structure

- `project.yml`: XcodeGen spec for the app, widget extension, Live Activity widget, intents, and tests.
- `App/`: app entry point, root tabs, container, and shared settings.
- `Features/`: recording, sessions, summary review, and settings UI.
- `Services/`: audio capture, transcription, extraction, reminders, notifications, background tasks, and persistence.
- `Models/`: session, transcript, summary, action item, and permission models.
- `Widgets/`, `LiveActivity/`, `Shortcuts/`: quick-entry surfaces outside the main app.
- `Tests/`: unit and UI tests.

## How To Run

1. Install XcodeGen if needed: `brew install xcodegen`
2. Generate the project: `xcodegen generate`
3. Open `CallNotes.xcodeproj` in Xcode.
4. Set a development team and signing configuration.
5. Add an OpenAI API key in Settings, or provide `OPENAI_API_KEY` in the app Info.plist for development.
6. Run on an iPhone simulator or device with microphone and notification capabilities available.

## Reminders

Reminders export is always explicit. After a session ends, CallNotes shows the extracted tasks, lets the user edit titles, details, owners, and due dates, and only creates reminders for items the user leaves selected and confirms.

## Privacy Notes

- Recording happens only after an explicit user action.
- Recording state is visible in the UI and Live Activity.
- After recording stops, CallNotes uploads the saved audio to OpenAI so it can transcribe the conversation and extract tasks.
- Reminders are only created after review and approval.

## Known iOS Limitations

- Task quality depends on the quality of the OpenAI transcription and extraction responses.
- Widgets and App Shortcuts can launch into the app flow, but iOS still governs what can happen in the background.
- The app cannot automatically detect that another call app has started.
- Background task execution timing is not guaranteed.

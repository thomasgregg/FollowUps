import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appViewModel: AppViewModel

    var body: some View {
        NavigationStack {
            List {
                Section("OpenAI") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("OpenAI API Key")
                            .font(.body)

                        SecureField("sk-...", text: $appViewModel.settings.openAIAPIKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Text("Audio is sent to OpenAI after recording stops so FollowUps can transcribe it and extract tasks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Task Extraction") {
                    Picker("Extraction Style", selection: $appViewModel.settings.extractionStyle) {
                        ForEach(ExtractionStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }

                    Text(appViewModel.settings.extractionStyle.helperText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Custom Instructions")
                            .font(.body)

                        TextEditor(text: $appViewModel.settings.customExtractionInstructions)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                        Text("Optional. Add preferences like “prefer German task titles”, “be more aggressive”, or “only include very explicit tasks”.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Storage") {
                    Toggle("Automatically delete older sessions", isOn: $appViewModel.settings.retentionCleanupEnabled)

                    Stepper("Retention: \(appViewModel.settings.retentionDays) days", value: $appViewModel.settings.retentionDays, in: 7...90)
                        .disabled(!appViewModel.settings.retentionCleanupEnabled)
                        .opacity(appViewModel.settings.retentionCleanupEnabled ? 1 : 0.45)

                    Text(appViewModel.settings.retentionCleanupEnabled
                         ? "Sessions older than this are automatically deleted together with their recordings to save space."
                         : "Automatic cleanup is off. Sessions and their recordings stay on this device until you delete them manually.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("FollowUps only records after you start it manually. It does not intercept phone calls or audio from other apps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .onChange(of: appViewModel.settings.retentionCleanupEnabled) { _, _ in
                persistSettings()
            }
            .onChange(of: appViewModel.settings.retentionDays) { _, _ in
                persistSettings()
            }
            .onChange(of: appViewModel.settings.openAIAPIKey) { _, _ in
                persistSettings()
            }
            .onChange(of: appViewModel.settings.extractionStyle) { _, _ in
                persistSettings()
            }
            .onChange(of: appViewModel.settings.customExtractionInstructions) { _, _ in
                persistSettings()
            }
        }
    }

    private func persistSettings() {
        appViewModel.save(settings: appViewModel.settings)
    }
}

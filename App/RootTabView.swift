import SwiftUI

struct RootTabView: View {
    @EnvironmentObject private var appViewModel: AppViewModel
    @EnvironmentObject private var recordingViewModel: RecordingViewModel

    var body: some View {
        TabView(selection: $appViewModel.selectedTab) {
            RecordHomeView()
                .tag(AppTab.record)
                .tabItem {
                    Label("Record", systemImage: "mic.circle.fill")
                }

            SessionsListView()
                .tag(AppTab.sessions)
                .tabItem {
                    Label("Sessions", systemImage: "list.bullet.rectangle")
                }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .sheet(item: $recordingViewModel.reviewSession) { session in
            SummaryReviewView(session: session)
                .environmentObject(appViewModel)
        }
        .onChange(of: appViewModel.pendingReviewSessionID) { _, _ in
            presentPendingReviewSessionIfPossible()
        }
        .onChange(of: appViewModel.sessions) { _, _ in
            presentPendingReviewSessionIfPossible()
        }
        .alert("Recording Error", isPresented: $recordingViewModel.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recordingViewModel.errorMessage)
        }
    }

    private func presentPendingReviewSessionIfPossible() {
        guard let sessionID = appViewModel.pendingReviewSessionID else { return }
        guard let session = appViewModel.sessions.first(where: { $0.id == sessionID }) else { return }

        appViewModel.selectedTab = .record
        recordingViewModel.presentReviewSession(session)
        appViewModel.pendingReviewSessionID = nil
    }
}

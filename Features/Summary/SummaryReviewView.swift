import SwiftUI

struct SummaryReviewView: View {
    let session: CallSession

    var body: some View {
        NavigationStack {
            SessionDetailView(session: session, presentation: .review)
        }
    }
}

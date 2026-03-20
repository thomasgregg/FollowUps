import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var stateLabel: String
    }

    var sessionID: String
}

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            VStack(alignment: .leading) {
                Text("Recording")
                    .font(.headline)
                Text("\(context.state.elapsedSeconds / 60)m \(context.state.elapsedSeconds % 60)s")
                    .monospacedDigit()
                HStack {
                    Link("Stop", destination: URL(string: "followups://record/stop")!)
                }
            }
            .padding()
            .activityBackgroundTint(.red.opacity(0.12))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Recording")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Link("Stop", destination: URL(string: "followups://record/stop")!)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.stateLabel)
                }
            } compactLeading: {
                Image(systemName: "record.circle.fill")
            } compactTrailing: {
                Text("\(context.state.elapsedSeconds / 60)m")
            } minimal: {
                Image(systemName: "mic.fill")
            }
        }
    }
}

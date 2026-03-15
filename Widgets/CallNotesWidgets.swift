import AppIntents
import SwiftUI
import WidgetKit

struct QuickStartEntry: TimelineEntry {
    let date: Date
}

struct QuickStartProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStartEntry { QuickStartEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickStartEntry) -> Void) { completion(.init(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStartEntry>) -> Void) {
        completion(Timeline(entries: [.init(date: .now)], policy: .after(.now.addingTimeInterval(1800))))
    }
}

struct QuickStartWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: QuickStartEntry

    var body: some View {
        Link(destination: URL(string: "callnotes://record/start")!) {
            Group {
                if family == .systemMedium {
                    HStack(spacing: 18) {
                        micIcon(backgroundSize: 92, iconSize: 74)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("FollowUps")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text("Tap to record")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                } else {
                    VStack(spacing: 12) {
                        Spacer(minLength: 0)

                        micIcon(backgroundSize: 92, iconSize: 76)

                        Text("Tap to record")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)
                }
            }
        }
        .buttonStyle(.plain)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func micIcon(backgroundSize: CGFloat, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.16))
                .frame(width: backgroundSize, height: backgroundSize)

            Image(systemName: "mic.circle.fill")
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(.blue, Color.accentColor.opacity(0.18))
        }
    }
}

struct QuickStartWidget: Widget {
    let kind = "QuickStartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickStartProvider()) { entry in
            QuickStartWidgetView(entry: entry)
        }
        .configurationDisplayName("FollowUps")
        .description("Start FollowUps quickly from your Home Screen or Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CallNotesWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickStartWidget()
        RecordingLiveActivityWidget()
    }
}

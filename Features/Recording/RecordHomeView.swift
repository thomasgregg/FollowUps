import SwiftUI

struct RecordHomeView: View {
    @EnvironmentObject private var recordingViewModel: RecordingViewModel

    var body: some View {
        NavigationStack {
            Group {
                if case .recording = recordingViewModel.state {
                    ActiveRecordingView()
                } else if case .stopping = recordingViewModel.state {
                    VStack(spacing: 0) {
                        ProcessingRecordingCard()
                            .padding(.horizontal, 16)
                        Spacer()
                    }
                } else {
                    RecordMicrophoneCenter(
                        accent: .accentColor,
                        secondaryAccent: Color(red: 0.69, green: 0.84, blue: 0.98),
                        outerAccent: Color(red: 0.83, green: 0.91, blue: 0.99),
                        pulseOpacity: 0,
                        title: "Tap to start recording",
                        detail: nil,
                        accessibilityLabel: "Start recording"
                    ) {
                        recordingViewModel.startRecordingFromPrimaryAction()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Record")
            .alert("Send recordings to OpenAI?", isPresented: $recordingViewModel.isShowingCloudConsent) {
                Button("Not now", role: .cancel) {
                    recordingViewModel.dismissCloudConsent()
                }
                Button("Allow and continue") {
                    recordingViewModel.confirmCloudConsentAndStart()
                }
            } message: {
                Text("After you stop recording, FollowUps sends the recording audio and transcript text to OpenAI to extract tasks. Nothing is sent until you allow this.")
            }
        }
    }
}

struct ActiveRecordingView: View {
    @EnvironmentObject private var recordingViewModel: RecordingViewModel
    @State private var isPulsing = false

    var body: some View {
        RecordMicrophoneCenter(
            accent: .red,
            secondaryAccent: Color.red.opacity(0.24),
            outerAccent: Color.red.opacity(0.18),
            pulseOpacity: isPulsing ? 0.16 : 0.05,
            title: recordingViewModel.elapsedTime.formattedClock,
            detail: "Recording in progress. Tap the microphone again to stop.",
            accessibilityLabel: "Stop recording"
        ) {
            Task { await recordingViewModel.stopRecording() }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onDisappear {
            isPulsing = false
        }
    }
}

struct RecordMicrophoneCenter: View {
    let accent: Color
    let secondaryAccent: Color
    let outerAccent: Color
    let pulseOpacity: Double
    let title: String
    let detail: String?
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(outerAccent)
                        .frame(width: 196, height: 196)

                    Circle()
                        .fill(accent.opacity(pulseOpacity))
                        .frame(width: 196, height: 196)

                    Button(action: action) {
                        ZStack {
                            Circle()
                                .fill(secondaryAccent)
                                .frame(width: 156, height: 156)

                            Image(systemName: "mic.fill")
                                .font(.system(size: 94, weight: .regular))
                                .foregroundStyle(accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(accessibilityLabel)
                }
                .frame(height: 196)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if let detail {
                        Text(detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 320)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
                .frame(width: 320, height: 116, alignment: .top)
            }
            .offset(y: -56)
        }
    }
}

struct ProcessingRecordingCard: View {
    @EnvironmentObject private var recordingViewModel: RecordingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Working on it", systemImage: "sparkles")
                .font(.title3.weight(.semibold))
                .padding(.bottom, 34)

            AnimatedProcessingBar()
                .padding(.bottom, 48)

            VStack(alignment: .leading, spacing: 24) {
                ForEach(Array(recordingViewModel.processingSteps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(color(for: index))
                                .frame(width: 24, height: 24)
                            if index < recordingViewModel.processingStepIndex {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            } else if index == recordingViewModel.processingStepIndex {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 8, height: 8)
                            }
                        }

                        Text(step)
                            .font(.title3)
                            .foregroundStyle(index <= recordingViewModel.processingStepIndex ? .primary : .secondary)
                    }
                }
            }
            .padding(.bottom, 44)

            Text("You can leave the app. FollowUps keeps working in the background and will notify you when your tasks are ready.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 36)

            Button {
                recordingViewModel.abortProcessing()
            } label: {
                Text("Abort")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func color(for index: Int) -> Color {
        if index < recordingViewModel.processingStepIndex {
            return .green
        }
        if index == recordingViewModel.processingStepIndex {
            return .blue
        }
        return Color(.systemGray4)
    }
}

struct AnimatedProcessingBar: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            GeometryReader { proxy in
                let segmentCount = 12
                let width = max((proxy.size.width - CGFloat(segmentCount - 1) * 8) / CGFloat(segmentCount), 8)

                HStack(spacing: 8) {
                    ForEach(0..<segmentCount, id: \.self) { index in
                        let phase = (time * 2.4) + Double(index) * 0.22
                        let opacity = 0.25 + (max(sin(phase), 0) * 0.75)

                        Capsule()
                            .fill(Color.blue.opacity(opacity))
                            .frame(width: width)
                    }
                }
            }
        }
        .frame(height: 10)
    }
}

struct LiveAudioWaveform: View {
    let levels: [Double]
    let currentLevel: Double

    var body: some View {
        let waveformLevels = Array(levels.suffix(24))

        GeometryReader { proxy in
            let spacing: CGFloat = 6
            let availableWidth = proxy.size.width - 24
            let barWidth = max((availableWidth - CGFloat(max(waveformLevels.count - 1, 0)) * spacing) / CGFloat(max(waveformLevels.count, 1)), 4)

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(waveformLevels.enumerated()), id: \.offset) { index, level in
                    let emphasizedLevel = index == waveformLevels.count - 1 ? max(level, currentLevel) : level
                    let height = max(8, 8 + CGFloat(emphasizedLevel) * 42)

                    Capsule()
                        .fill(index >= waveformLevels.count - 3 ? Color.red : Color.red.opacity(0.8))
                        .frame(width: barWidth, height: height)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
            }
            .frame(width: availableWidth, height: proxy.size.height, alignment: .center)
            .padding(.horizontal, 12)
        }
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.red.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private extension TimeInterval {
    var formattedClock: String {
        let total = Int(self)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

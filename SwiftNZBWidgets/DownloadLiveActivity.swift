//
//  DownloadLiveActivity.swift
//  SwiftNZBWidgets
//
//  Lock Screen + Dynamic Island presentation of the active download / post-processing job.
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

struct DownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            // No forced background tint: on iOS 26 the system renders Live Activities on adaptive
            // glass, so an opaque black tint looks foreign in light environments / StandBy.
            lockScreen(context)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                // Leading/trailing sit beside the camera and are only a few points wide: an icon
                // and a single-line value fit there, a job name does not. The name goes in the
                // center (the title slot), and the progress bar spans the full bottom width.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: icon(state))
                        .font(.title3)
                        .foregroundStyle(tint(state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(verbatim: percentText(state))
                        .font(.callout)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.jobName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: state.fractionComplete)
                            .tint(tint(state))
                        HStack {
                            subtitle(state)
                                .foregroundStyle(.secondary)
                            Spacer()
                            eta(state)
                            actionButton(context)
                        }
                        .font(.caption)
                    }
                }
            } compactLeading: {
                Image(systemName: icon(state))
                    .foregroundStyle(tint(state))
            } compactTrailing: {
                // The canonical Island download indicator: a small circular gauge.
                ProgressView(value: state.fractionComplete)
                    .progressViewStyle(.circular)
                    .tint(tint(state))
            } minimal: {
                Image(systemName: icon(state))
                    .foregroundStyle(tint(state))
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<DownloadActivityAttributes>) -> some View {
        let state = context.state
        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(state.jobName, systemImage: icon(state))
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(tint(state))
                    subtitle(state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(verbatim: percentText(state))
                        .font(.title3)
                        .monospacedDigit()
                    eta(state)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                actionButton(context)
            }
            ProgressView(value: state.fractionComplete)
                .tint(tint(state))
        }
    }

    /// Interactive pause/resume. Runs `PauseJobIntent` / `ResumeJobIntent` in the app process.
    /// Live Activities don't support glass button styles, so a tinted 44pt circle gives the
    /// required hit target.
    @ViewBuilder
    private func actionButton(_ context: ActivityViewContext<DownloadActivityAttributes>) -> some View {
        if context.state.isPaused {
            Button(intent: ResumeJobIntent(jobID: context.attributes.jobID)) {
                Image(systemName: "play.fill")
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: .circle)
            }
            .buttonStyle(.plain)
            .tint(.green)
            .accessibilityLabel(Text("Resume"))
        } else {
            Button(intent: PauseJobIntent(jobID: context.attributes.jobID)) {
                Image(systemName: "pause.fill")
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: .circle)
            }
            .buttonStyle(.plain)
            .tint(.orange)
            .accessibilityLabel(Text("Pause"))
        }
    }

    @ViewBuilder
    private func eta(_ state: DownloadActivityAttributes.ContentState) -> some View {
        // Only render the self-updating countdown while the deadline is still in the future —
        // `Text(timerInterval:)` with a past lowerBound traps.
        if let deadline = state.etaDeadline, !state.isPaused, state.stepRaw == nil, deadline > .now {
            Text(timerInterval: Date.now...deadline, countsDown: true)
                .monospacedDigit()
        } else {
            EmptyView()
        }
    }

    private func percentText(_ state: DownloadActivityAttributes.ContentState) -> String {
        "\(Int((state.fractionComplete * 100).rounded()))%"
    }

    /// Status / speed line. While downloading this is the throughput; otherwise a localized state
    /// label. Post-processing steps are mapped from their raw value to a readable label.
    @ViewBuilder
    private func subtitle(_ state: DownloadActivityAttributes.ContentState) -> some View {
        if state.isWaitingForNetwork {
            Text("Waiting for network…")
        } else if let step = state.stepRaw {
            Text(stepLabel(step))
        } else if state.isPaused {
            Text("Paused")
        } else {
            Text(verbatim: "\(Int64(state.bytesPerSecond).formatted(.byteCount(style: .file)))/s")
        }
    }

    private func stepLabel(_ raw: String) -> LocalizedStringKey {
        switch raw {
        case "assemble": return "Assembling"
        case "verify": return "Verifying"
        case "repair": return "Repairing"
        case "extract": return "Extracting"
        case "cleanup": return "Cleaning up"
        default: return "Processing"
        }
    }

    private func icon(_ state: DownloadActivityAttributes.ContentState) -> String {
        if state.isWaitingForNetwork { return "wifi.exclamationmark" }
        if state.isPaused { return "pause.circle" }
        if state.stepRaw != nil { return "wand.and.stars" }
        return "arrow.down.circle"
    }

    private func tint(_ state: DownloadActivityAttributes.ContentState) -> Color {
        if state.isWaitingForNetwork { return .orange }
        if state.isPaused { return .orange }
        return .accentColor
    }
}

#if DEBUG
private extension DownloadActivityAttributes.ContentState {
    static let paused = Self(jobName: "ubuntu-24.04-desktop-amd64", fractionComplete: 0.64,
                             bytesPerSecond: 0, etaDeadline: nil, stepRaw: nil,
                             isPaused: true, isWaitingForNetwork: false, additionalJobCount: 0)
    static let downloading = Self(jobName: "ubuntu-24.04-desktop-amd64", fractionComplete: 0.37,
                                  bytesPerSecond: 48_000_000, etaDeadline: .now.addingTimeInterval(754),
                                  stepRaw: nil, isPaused: false, isWaitingForNetwork: false,
                                  additionalJobCount: 0)
}

private let previewAttributes = DownloadActivityAttributes(jobID: "preview")

#Preview("Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    DownloadLiveActivity()
} contentStates: {
    DownloadActivityAttributes.ContentState.paused
    DownloadActivityAttributes.ContentState.downloading
}

#Preview("Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    DownloadLiveActivity()
} contentStates: {
    DownloadActivityAttributes.ContentState.downloading
}

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    DownloadLiveActivity()
} contentStates: {
    DownloadActivityAttributes.ContentState.paused
}
#endif

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
            lockScreen(context)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(state.jobName, systemImage: icon(state))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(tint(state))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(verbatim: percentText(state))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.center) {
                    ProgressView(value: state.fractionComplete)
                        .tint(tint(state))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(verbatim: subtitle(state))
                            .foregroundStyle(.secondary)
                        Spacer()
                        eta(state)
                        actionButton(context)
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: icon(state))
                    .foregroundStyle(tint(state))
            } compactTrailing: {
                Text(verbatim: percentText(state))
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
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
                    Text(verbatim: subtitle(state))
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
    @ViewBuilder
    private func actionButton(_ context: ActivityViewContext<DownloadActivityAttributes>) -> some View {
        if context.state.isPaused {
            Button(intent: ResumeJobIntent(jobID: context.attributes.jobID)) {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .tint(.green)
        } else {
            Button(intent: PauseJobIntent(jobID: context.attributes.jobID)) {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(.plain)
            .tint(.orange)
        }
    }

    @ViewBuilder
    private func eta(_ state: DownloadActivityAttributes.ContentState) -> some View {
        if let deadline = state.etaDeadline, !state.isPaused, state.stepRaw == nil {
            Text(timerInterval: Date.now...deadline, countsDown: true)
                .monospacedDigit()
        } else {
            EmptyView()
        }
    }

    private func percentText(_ state: DownloadActivityAttributes.ContentState) -> String {
        "\(Int((state.fractionComplete * 100).rounded()))%"
    }

    /// Status / speed line. While downloading this is the throughput; otherwise a state label.
    private func subtitle(_ state: DownloadActivityAttributes.ContentState) -> String {
        if state.isWaitingForNetwork { return "Waiting for network…" }
        if let step = state.stepRaw { return step.capitalized }
        if state.isPaused { return "Paused" }
        let rate = Int64(state.bytesPerSecond).formatted(.byteCount(style: .file))
        return "\(rate)/s"
    }

    private func icon(_ state: DownloadActivityAttributes.ContentState) -> String {
        if state.isWaitingForNetwork { return "wifi.exclamationmark" }
        if state.isPaused { return "pause.circle" }
        if state.stepRaw != nil { return "wand.and.stars" }
        return "arrow.down.circle"
    }

    private func tint(_ state: DownloadActivityAttributes.ContentState) -> Color {
        if state.isWaitingForNetwork { return .orange }
        if state.isPaused { return .secondary }
        return .accentColor
    }
}

//
//  DownloadIntents.swift
//  SwiftNZB
//
//  Interactive Live Activity buttons. Compiled into BOTH the app and the widget; the
//  DownloadManager calls are gated behind SWIFTNZB_APP (set only on the app target) so the
//  widget extension compiles without the app's services.
//

import AppIntents

struct PauseJobIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Download"

    @Parameter(title: "Job") var jobID: String

    init() {}
    init(jobID: String) { self.jobID = jobID }

    func perform() async throws -> some IntentResult {
        #if SWIFTNZB_APP
        if let id = UUID(uuidString: jobID) {
            await MainActor.run { DownloadManager.shared.pause(id) }
        }
        #endif
        return .result()
    }
}

struct ResumeJobIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume Download"

    @Parameter(title: "Job") var jobID: String

    init() {}
    init(jobID: String) { self.jobID = jobID }

    func perform() async throws -> some IntentResult {
        #if SWIFTNZB_APP
        if let id = UUID(uuidString: jobID) {
            await MainActor.run { DownloadManager.shared.resume(id) }
        }
        #endif
        return .result()
    }
}

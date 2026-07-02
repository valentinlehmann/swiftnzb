//
//  DownloadSettings.swift
//  SwiftNZB
//

import SwiftUI

/// How completed output is laid out under the Files-visible completed folder.
enum FolderMode: String, Codable, CaseIterable, Sendable {
    case perJobSubfolder    // complete/<job name>/…
    case flat               // complete/…

    var title: LocalizedStringKey {
        switch self {
        case .perJobSubfolder: return "Subfolder per Download"
        case .flat: return "Single Folder"
        }
    }
}

/// User-tunable engine + post-processing preferences. Persisted by `SettingsStore`
/// (UserDefaults locally, with the non-secret subset mirrored to iCloud KVS).
struct DownloadSettings: Codable, Equatable, Sendable {
    /// Hard ceiling on simultaneous connections across all servers.
    var maxGlobalConnections: Int
    var par2VerifyEnabled: Bool
    var par2RepairEnabled: Bool
    var unrarEnabled: Bool
    var deleteArchivesAfterExtract: Bool
    var folderMode: FolderMode
    /// 0 = unlimited; otherwise a soft cap in KB/s.
    var bandwidthCapKBps: Int
    /// Park downloads while on a cellular / expensive interface.
    var pauseOnCellular: Bool
    /// Only run opportunistic background processing while charging.
    var requireExternalPowerForBackground: Bool
    /// Auto-prune completed history older than this many days (0 = keep forever).
    var keepCompletedHistoryDays: Int
    /// Preselected server in the import sheet; updated to whatever the user last picked there.
    var defaultServerID: UUID?

    static let `default` = DownloadSettings(
        maxGlobalConnections: 20,
        par2VerifyEnabled: true,
        par2RepairEnabled: true,
        unrarEnabled: true,
        deleteArchivesAfterExtract: true,
        folderMode: .perJobSubfolder,
        bandwidthCapKBps: 0,
        pauseOnCellular: false,
        requireExternalPowerForBackground: true,
        keepCompletedHistoryDays: 30,
        defaultServerID: nil
    )

    // Migration-safe decoder so adding a preference later doesn't break stored/synced settings.
    init(from decoder: Decoder) throws {
        let d = Self.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        maxGlobalConnections = try c.decodeIfPresent(Int.self, forKey: .maxGlobalConnections) ?? d.maxGlobalConnections
        par2VerifyEnabled = try c.decodeIfPresent(Bool.self, forKey: .par2VerifyEnabled) ?? d.par2VerifyEnabled
        par2RepairEnabled = try c.decodeIfPresent(Bool.self, forKey: .par2RepairEnabled) ?? d.par2RepairEnabled
        unrarEnabled = try c.decodeIfPresent(Bool.self, forKey: .unrarEnabled) ?? d.unrarEnabled
        deleteArchivesAfterExtract = try c.decodeIfPresent(Bool.self, forKey: .deleteArchivesAfterExtract) ?? d.deleteArchivesAfterExtract
        folderMode = try c.decodeIfPresent(FolderMode.self, forKey: .folderMode) ?? d.folderMode
        bandwidthCapKBps = try c.decodeIfPresent(Int.self, forKey: .bandwidthCapKBps) ?? d.bandwidthCapKBps
        pauseOnCellular = try c.decodeIfPresent(Bool.self, forKey: .pauseOnCellular) ?? d.pauseOnCellular
        requireExternalPowerForBackground = try c.decodeIfPresent(Bool.self, forKey: .requireExternalPowerForBackground) ?? d.requireExternalPowerForBackground
        keepCompletedHistoryDays = try c.decodeIfPresent(Int.self, forKey: .keepCompletedHistoryDays) ?? d.keepCompletedHistoryDays
        defaultServerID = try c.decodeIfPresent(UUID.self, forKey: .defaultServerID)
    }

    init(
        maxGlobalConnections: Int,
        par2VerifyEnabled: Bool,
        par2RepairEnabled: Bool,
        unrarEnabled: Bool,
        deleteArchivesAfterExtract: Bool,
        folderMode: FolderMode,
        bandwidthCapKBps: Int,
        pauseOnCellular: Bool,
        requireExternalPowerForBackground: Bool,
        keepCompletedHistoryDays: Int,
        defaultServerID: UUID? = nil
    ) {
        self.maxGlobalConnections = maxGlobalConnections
        self.par2VerifyEnabled = par2VerifyEnabled
        self.par2RepairEnabled = par2RepairEnabled
        self.unrarEnabled = unrarEnabled
        self.deleteArchivesAfterExtract = deleteArchivesAfterExtract
        self.folderMode = folderMode
        self.bandwidthCapKBps = bandwidthCapKBps
        self.pauseOnCellular = pauseOnCellular
        self.requireExternalPowerForBackground = requireExternalPowerForBackground
        self.keepCompletedHistoryDays = keepCompletedHistoryDays
        self.defaultServerID = defaultServerID
    }
}

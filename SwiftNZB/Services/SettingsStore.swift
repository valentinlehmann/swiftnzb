//
//  SettingsStore.swift
//  SwiftNZB
//

import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    private let key = "settings.v1"
    private let defaults = UserDefaults.standard

    var settings: DownloadSettings {
        didSet { persist() }
    }

    private init() {
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(DownloadSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}

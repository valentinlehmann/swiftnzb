//
//  AboutView.swift
//  SwiftNZB
//

import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version") { Text(verbatim: appVersion) }
                Link(destination: URL(string: "https://github.com/valentinlehmann/swiftnzb")!) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
            Section {
                Text("SwiftNZB — a native Usenet NZB downloader. Bring your own server and NZB files. PAR2 verification/repair is a clean-room implementation; RAR extraction uses the UnRAR library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

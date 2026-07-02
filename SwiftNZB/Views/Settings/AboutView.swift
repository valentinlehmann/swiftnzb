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
                Text("SwiftNZB is a native client for the Usenet (NNTP) protocol. Bring your own Usenet provider account and NZB files. PAR2 verification and repair is a clean-room implementation; RAR extraction uses the UnRAR library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("SwiftNZB contains no content and no search. You are responsible for the content you access, and should only download material you have the right to.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

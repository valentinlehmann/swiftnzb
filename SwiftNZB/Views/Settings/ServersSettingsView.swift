//
//  ServersSettingsView.swift
//  SwiftNZB
//

import SwiftUI

struct ServersSettingsView: View {
    @State private var servers = ServerStore.shared
    @Bindable private var settingsStore = SettingsStore.shared

    private var effectiveDefaultServerID: UUID? {
        settingsStore.settings.defaultServerID ?? servers.primaryServer?.id
    }

    private var defaultServerBinding: Binding<UUID?> {
        Binding(get: { effectiveDefaultServerID },
                set: { settingsStore.settings.defaultServerID = $0 })
    }

    var body: some View {
        List {
            Section {
                ForEach(servers.accounts) { account in
                    NavigationLink {
                        AddServerView(existing: account)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                Text(verbatim: "\(account.host):\(account.port)\(account.useSSL ? " · SSL" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if account.id == effectiveDefaultServerID {
                                Spacer()
                                Text("Default")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { servers.remove(account.id) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                NavigationLink { AddServerView() } label: {
                    Label("Add Server", systemImage: "plus")
                }
            } footer: {
                Text("Your Usenet provider's host, port, login, and how many connections it allows.")
            }

            if servers.accounts.count > 1 {
                Section {
                    Picker("Default server", selection: defaultServerBinding) {
                        ForEach(servers.accounts) { account in
                            Text(account.name).tag(UUID?.some(account.id))
                        }
                    }
                } footer: {
                    Text("Preselected when you add a download. Picking a different one in the add sheet updates this.")
                }
            }
        }
        .navigationTitle("Servers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

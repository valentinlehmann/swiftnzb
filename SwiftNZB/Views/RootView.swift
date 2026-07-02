//
//  RootView.swift
//  SwiftNZB
//

import SwiftUI

struct RootView: View {
    @State private var servers = ServerStore.shared
    @State private var importer = ImportCoordinator.shared

    var body: some View {
        Group {
            if servers.hasServers {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
        .sheet(isPresented: $importer.isPresentingConfirm) {
            if let job = importer.pendingJob {
                ImportConfirmView(job: job)
                    .presentationSizing(.form)
            }
        }
        .alert("Import Failed", isPresented: $importer.isPresentingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importer.errorMessage ?? "")
        }
    }
}

/// Shown until the user adds their first Usenet server.
private struct OnboardingView: View {
    @State private var showingAddServer = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Welcome to SwiftNZB", systemImage: "arrow.down.circle")
            } description: {
                Text("Add your Usenet server to start downloading NZB files.")
            } actions: {
                Button("Add Server") { showingAddServer = true }
                    .buttonStyle(.glassProminent)
            }
            .navigationTitle("SwiftNZB")
        }
        .sheet(isPresented: $showingAddServer) {
            NavigationStack { AddServerView(isModal: true) }
                .presentationSizing(.form)
        }
    }
}

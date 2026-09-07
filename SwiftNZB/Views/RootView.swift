//
//  RootView.swift
//  SwiftNZB
//

import SwiftUI

struct RootView: View {
    @State private var servers = ServerStore.shared
    @State private var importer = ImportCoordinator.shared

    var body: some View {
        // A ZStack, not a Group: modifiers on a Group attach to each child, so the sheets below
        // would be torn down whenever `hasServers` swaps the content and their isPresenting flag
        // would stick true. A stable container keeps one host for both presentations.
        ZStack {
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
        .sheet(isPresented: $importer.isPresentingPaywall) {
            // Mutually exclusive with the confirm sheet: handle(url:) sets exactly one of them.
            NavigationStack { PaywallView(reason: .limitReached, isModal: true) }
                .presentationSizing(.form)
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
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Welcome to SwiftNZB", systemImage: "arrow.down.circle")
            } description: {
                Text("Add your Usenet server, then import an NZB to start downloading.")
            } actions: {
                Button("Add Server") { showingAddServer = true }
                    .buttonStyle(.glassProminent)
            }
            .navigationTitle("SwiftNZB")
            .toolbar {
                // This screen has no tab bar, so without this there is no route to the purchase
                // screen at all until a server exists — which is how App Review ends up unable to
                // find the in-app purchases.
                ToolbarItem(placement: .topBarTrailing) {
                    // Text, not icon-only: a bare glyph is too easy for a reviewer to miss, and
                    // the review notes name this button by its label.
                    Button("SwiftNZB Pro") { showingPaywall = true }
                }
            }
        }
        .sheet(isPresented: $showingAddServer) {
            NavigationStack { AddServerView(isModal: true) }
                .presentationSizing(.form)
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack { PaywallView(isModal: true) }
                .presentationSizing(.form)
        }
    }
}

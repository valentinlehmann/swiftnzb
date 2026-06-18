//
//  HistoryView.swift
//  SwiftNZB
//

import SwiftUI

enum HistorySort: String, CaseIterable, Identifiable {
    case date, size, name
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .date: return "Date"
        case .size: return "Size"
        case .name: return "Name"
        }
    }
    /// Direction used when this option is first picked (matches what users expect by default).
    var defaultAscending: Bool {
        switch self {
        case .date: return false   // newest first
        case .size: return false   // largest first
        case .name: return true    // A–Z
        }
    }
    /// Short description of the current direction, shown under the selected option.
    func directionLabel(ascending: Bool) -> LocalizedStringKey {
        switch self {
        case .date: return ascending ? "Oldest first" : "Newest first"
        case .size: return ascending ? "Smallest first" : "Largest first"
        case .name: return ascending ? "A–Z" : "Z–A"
        }
    }
}

struct HistoryView: View {
    @State private var manager = DownloadManager.shared
    @State private var sort: HistorySort = .date
    @State private var ascending = false
    @State private var editing = false
    @State private var selection = Set<UUID>()

    private var jobs: [DownloadJob] { sorted(manager.historyJobs) }

    var body: some View {
        Group {
            if manager.historyJobs.isEmpty {
                EmptyStateView(title: "No History", systemImage: "checkmark.circle",
                               message: "Completed and cancelled downloads appear here.")
            } else {
                listContent
            }
        }
        .navigationTitle("History")
        .navigationDestination(for: UUID.self) { JobDetailView(jobID: $0) }
        .toolbar { toolbar }
        .onChange(of: editing) { _, isEditing in if !isEditing { selection.removeAll() } }
    }

    // MARK: - List

    private var listContent: some View {
        List {
            ForEach(jobs) { job in
                if editing {
                    Button { toggle(job.id) } label: {
                        HStack(spacing: 12) {
                            selectionMark(job.id)
                            row(job)
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink(value: job.id) { row(job) }
                        .swipeActions {
                            Button(role: .destructive) { manager.removeFromHistory(job.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    private func row(_ job: DownloadJob) -> some View {
        HStack {
            Image(systemName: job.status.systemImage)
                .foregroundStyle(job.status.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name).lineLimit(1)
                Text(verbatim: "\(Format.bytes(job.totalBytes)) · \(dateText(job))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func selectionMark(_ id: UUID) -> some View {
        CheckboxView(isChecked: selection.contains(id))
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !manager.historyJobs.isEmpty {
                Button(editing ? "Done" : "Edit") {
                    withAnimation { editing.toggle() }
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if editing {
                Button(role: .destructive) {
                    manager.removeFromHistory(selection)
                    selection.removeAll()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selection.isEmpty)
            } else if !manager.historyJobs.isEmpty {
                Menu {
                    Section("Sort By") {
                        ForEach(HistorySort.allCases) { option in
                            sortButton(option)
                        }
                    }
                    Divider()
                    Button(role: .destructive) { manager.clearHistory() } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    /// A sort row: tapping the already-selected option flips the direction (like Files).
    @ViewBuilder
    private func sortButton(_ option: HistorySort) -> some View {
        Button {
            if sort == option {
                ascending.toggle()
            } else {
                sort = option
                ascending = option.defaultAscending
            }
        } label: {
            if sort == option {
                // The arrow doubles as the selection indicator and shows the direction.
                Label {
                    Text(option.label)
                    Text(option.directionLabel(ascending: ascending))
                } icon: {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                }
            } else {
                Text(option.label)
            }
        }
    }

    // MARK: - Helpers

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func dateText(_ job: DownloadJob) -> String {
        (job.completedAt ?? job.addedAt).formatted(date: .abbreviated, time: .omitted)
    }

    private func sorted(_ list: [DownloadJob]) -> [DownloadJob] {
        let ascendingOrder: [DownloadJob]
        switch sort {
        case .date:
            ascendingOrder = list.sorted { ($0.completedAt ?? $0.addedAt) < ($1.completedAt ?? $1.addedAt) }
        case .size:
            ascendingOrder = list.sorted { $0.totalBytes < $1.totalBytes }
        case .name:
            ascendingOrder = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return ascending ? ascendingOrder : ascendingOrder.reversed()
    }
}

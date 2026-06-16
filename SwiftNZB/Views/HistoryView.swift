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
    var systemImage: String {
        switch self {
        case .date: return "calendar"
        case .size: return "internaldrive"
        case .name: return "textformat"
        }
    }
}

struct HistoryView: View {
    @State private var manager = DownloadManager.shared
    @State private var sort: HistorySort = .date
    @State private var grid = false
    @State private var editing = false
    @State private var selection = Set<UUID>()

    private var jobs: [DownloadJob] { sorted(manager.historyJobs) }

    var body: some View {
        Group {
            if manager.historyJobs.isEmpty {
                EmptyStateView(title: "No History", systemImage: "checkmark.circle",
                               message: "Completed and cancelled downloads appear here.")
            } else if grid {
                gridContent
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

    // MARK: - Grid

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(jobs) { job in
                    if editing {
                        gridCell(job)
                            .overlay(alignment: .topTrailing) { selectionMark(job.id).padding(8) }
                            .onTapGesture { toggle(job.id) }
                    } else {
                        NavigationLink(value: job.id) { gridCell(job) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
    }

    private func gridCell(_ job: DownloadJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: job.status.systemImage).foregroundStyle(job.status.tint)
                Spacer()
                StatusChip(status: job.status)
            }
            Text(job.name).font(.subheadline.weight(.medium)).lineLimit(2)
            Spacer(minLength: 0)
            Text(verbatim: Format.bytes(job.totalBytes)).font(.caption.monospacedDigit())
            Text(verbatim: dateText(job)).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
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
                    Picker("Sort by", selection: $sort) {
                        ForEach(HistorySort.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                    Button {
                        withAnimation { grid.toggle() }
                    } label: {
                        Label(grid ? "List View" : "Grid View", systemImage: grid ? "list.bullet" : "square.grid.2x2")
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

    // MARK: - Helpers

    private func toggle(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func dateText(_ job: DownloadJob) -> String {
        (job.completedAt ?? job.addedAt).formatted(date: .abbreviated, time: .omitted)
    }

    private func sorted(_ list: [DownloadJob]) -> [DownloadJob] {
        switch sort {
        case .date: return list.sorted { ($0.completedAt ?? $0.addedAt) > ($1.completedAt ?? $1.addedAt) }
        case .size: return list.sorted { $0.totalBytes > $1.totalBytes }
        case .name: return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }
}

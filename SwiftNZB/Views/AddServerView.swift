//
//  AddServerView.swift
//  SwiftNZB
//

import SwiftUI

struct AddServerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: AddServerViewModel
    /// True when presented as a sheet (no navigation back button), so a Cancel button is shown.
    /// When pushed (e.g. from Settings), the navigation back button already cancels.
    private let isModal: Bool

    init(existing: ServerAccount? = nil, isModal: Bool = false) {
        _viewModel = State(initialValue: AddServerViewModel(existing: existing))
        self.isModal = isModal
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Name", text: $viewModel.name)
                TextField("Host", text: $viewModel.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Toggle("Use SSL", isOn: $viewModel.useSSL)
                TextField("Port", text: $viewModel.portText)
                    .keyboardType(.numberPad)
            }

            Section("Authentication") {
                TextField("Username", text: $viewModel.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $viewModel.password)
            }

            Section("Performance") {
                TextField("Max connections", text: $viewModel.maxConnectionsText)
                    .keyboardType(.numberPad)
            }

            Section {
                Button {
                    Task { await viewModel.test() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        switch viewModel.testState {
                        case .idle: EmptyView()
                        case .testing: ProgressView()
                        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                }
                .disabled(!viewModel.canSave || viewModel.testState == .testing)

                if case let .failure(message) = viewModel.testState {
                    Text(message).font(.caption).foregroundStyle(.red)
                } else if case .success = viewModel.testState {
                    Text("Connected successfully.").font(.caption).foregroundStyle(.green)
                } else if !viewModel.isEditing {
                    Text("Test the connection before adding this server.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit Server" : "Add Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save()
                    dismiss()
                }
                .disabled(!viewModel.canCommit)
            }
            if isModal {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

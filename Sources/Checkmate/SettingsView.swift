import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: Store
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Checkmate").font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label("Token")
                    HStack(spacing: 6) {
                        SecureField("GitHub token", text: $store.token)
                        Button("Paste") {
                            if let pasted = NSPasteboard.general.string(forType: .string) { store.token = pasted }
                        }
                    }
                }
                GridRow {
                    label("Repository")
                    HStack(spacing: 6) {
                        TextField("owner/repo", text: $store.repo)
                        Menu {
                            ForEach(store.repos) { repo in
                                Button(repo.fullName) { store.repo = repo.fullName }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .disabled(store.repos.isEmpty)
                    }
                }
                GridRow {
                    label("Workflow")
                    Picker("Workflow", selection: $store.workflowID) {
                        Text("Choose…").tag(Int?.none)
                        ForEach(store.workflows) { workflow in
                            Text(workflow.name).tag(Int?.some(workflow.id))
                        }
                    }
                    .labelsHidden()
                    .disabled(store.workflows.isEmpty)
                }
                GridRow {
                    label("Branch")
                    TextField("All branches", text: $store.branch)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle("Only my runs", isOn: $store.onlyMine)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle("Launch at login", isOn: $store.launchAtLogin)
                }
            }

            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Quit") { NSApp.terminate(nil) }
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.isConfigured)
            }
        }
        .padding(16)
        .task {
            await store.loadRepos()
            await store.loadWorkflows()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }
}

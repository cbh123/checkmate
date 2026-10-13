import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var store: Store
    @State private var showingSettings: Bool

    init(startInSettings: Bool) {
        _showingSettings = State(initialValue: startInSettings)
    }

    var body: some View {
        Group {
            if showingSettings {
                SettingsView(onDone: { showingSettings = false })
            } else {
                RunsView(onOpenSettings: { showingSettings = true })
            }
        }
        .frame(width: 400)
    }
}

private struct RunsView: View {
    @EnvironmentObject private var store: Store
    let onOpenSettings: () -> Void

    private var rows: [WorkflowRun] { Array(store.runs.prefix(10)) }

    private var subtitle: String {
        var parts = [store.repo]
        if !store.branch.isEmpty { parts.append(store.branch) }
        if store.onlyMine { parts.append("mine") }
        if let estimate = store.estimate { parts.append("usually \(formatDuration(estimate))") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.workflowName.isEmpty ? "Workflow" : store.workflowName).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
            }
            .buttonStyle(.borderless)
            .padding(12)

            Divider()

            if let error = store.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            if rows.isEmpty {
                Text(store.lastUpdated == nil ? "Loading…" : "No runs yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { run in
                        RunRow(run: run)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                if let lastUpdated = store.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

private struct RunRow: View {
    @EnvironmentObject private var store: Store
    let run: WorkflowRun
    @State private var isHovered = false

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private var details: String {
        var parts = ["#\(run.runNumber)"]
        if let branch = run.headBranch, branch != store.defaultBranch { parts.append(branch) }
        if let login = run.actor?.login { parts.append(login) }
        parts.append(Self.relativeFormatter.localizedString(for: run.createdAt, relativeTo: store.now))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button { NSWorkspace.shared.open(run.htmlUrl) } label: {
            HStack(spacing: 10) {
                StatusIcon(state: run.state).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.displayTitle).lineLimit(1)
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(store.rowDetail(of: run))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if run.isActive {
                        DurationBar(fraction: store.progress(of: run), color: Color(nsColor: store.color(of: run)))
                            .frame(width: 72, height: 4)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct StatusIcon: View {
    let state: WorkflowRun.State

    var body: some View {
        switch state {
        case .success: Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.green)
        case .failure: Image(systemName: "xmark").fontWeight(.semibold).foregroundStyle(.red)
        case .cancelled: Image(systemName: "minus").foregroundStyle(.secondary)
        case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
        case .running: ProgressView().controlSize(.small)
        }
    }
}

private struct DurationBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: geometry.size.width * min(max(fraction, 0), 1))
            }
        }
    }
}

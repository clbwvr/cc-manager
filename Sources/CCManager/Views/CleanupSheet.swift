import SwiftUI

/// Bulk-cleanup interface for pruning stale conversations by age.
/// Lists everything older than a chosen threshold (bases protected by default),
/// lets the user deselect any they want to keep, then moves the rest to Trash.
struct CleanupSheet: View {
    @EnvironmentObject var store: ConversationStore
    @Environment(\.dismiss) private var dismiss

    enum Threshold: Int, CaseIterable, Identifiable {
        case week = 7
        case twoWeeks = 14
        case month = 30
        case twoMonths = 60
        case quarter = 90
        case halfYear = 180
        case year = 365

        var id: Int { rawValue }
        var label: String {
            switch self {
            case .week: "1 week"
            case .twoWeeks: "2 weeks"
            case .month: "1 month"
            case .twoMonths: "2 months"
            case .quarter: "3 months"
            case .halfYear: "6 months"
            case .year: "1 year"
            }
        }
    }

    @State private var threshold: Threshold = .month
    @State private var excludeBases = true
    @State private var onlyUnassigned = false
    @State private var selected: Set<String> = []
    @State private var showConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if candidates.isEmpty {
                ContentUnavailableView(
                    "Nothing to clean up",
                    systemImage: "sparkles",
                    description: Text("No conversations are older than \(threshold.label).")
                )
                .frame(maxHeight: .infinity)
            } else {
                candidateList
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 560)
        .onAppear { resetSelection() }
        .onChange(of: threshold) { _, _ in resetSelection() }
        .onChange(of: excludeBases) { _, _ in resetSelection() }
        .onChange(of: onlyUnassigned) { _, _ in resetSelection() }
        .confirmationDialog(
            "Move \(selected.count) conversation\(selected.count == 1 ? "" : "s") to Trash?",
            isPresented: $showConfirm
        ) {
            Button("Move to Trash", role: .destructive) {
                store.deleteMany(chosen)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The conversation files will be moved to the macOS Trash. This can be undone from Finder.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clean Up Old Chats")
                .font(.title2).bold()

            HStack {
                Text("Older than")
                Picker("", selection: $threshold) {
                    ForEach(Threshold.allCases) { t in
                        Text(t.label).tag(t)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }

            HStack(spacing: 20) {
                Toggle("Keep bases", isOn: $excludeBases)
                Toggle("Only unassigned", isOn: $onlyUnassigned)
            }
            .toggleStyle(.checkbox)
            .font(.callout)
        }
        .padding()
    }

    private var candidateList: some View {
        List {
            ForEach(candidates) { c in
                CleanupRow(
                    conversation: c,
                    isOn: Binding(
                        get: { selected.contains(c.id) },
                        set: { on in
                            if on { selected.insert(c.id) } else { selected.remove(c.id) }
                        }
                    )
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(selected.count == candidates.count ? "Deselect All" : "Select All") {
                if selected.count == candidates.count {
                    selected.removeAll()
                } else {
                    selected = Set(candidates.map(\.id))
                }
            }
            .disabled(candidates.isEmpty)

            Spacer()

            Text("\(selected.count) of \(candidates.count) selected")
                .foregroundStyle(.secondary)
                .font(.callout)

            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Move to Trash") { showConfirm = true }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
        }
        .padding()
    }

    // MARK: - Data

    private var cutoff: Date {
        Calendar.current.date(byAdding: .day, value: -threshold.rawValue, to: Date()) ?? Date()
    }

    private var candidates: [Conversation] {
        store.conversations
            .filter { $0.lastModified < cutoff }
            .filter { !(excludeBases && $0.isBase) }
            .filter { !(onlyUnassigned && $0.projectId != nil) }
            .sorted { $0.lastModified < $1.lastModified } // oldest first
    }

    private var chosen: [Conversation] {
        candidates.filter { selected.contains($0.id) }
    }

    private func resetSelection() {
        selected = Set(candidates.map(\.id))
    }
}

private struct CleanupRow: View {
    let conversation: Conversation
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 8) {
                if conversation.isBase {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .padding(.top, 2)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(conversation.title)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(conversation.projectName.isEmpty ? "—" : conversation.projectName)
                        Text("·")
                        Text("\(conversation.messageCount) msgs")
                        Text("·")
                        Text(conversation.lastModified, format: .relative(presentation: .named))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}

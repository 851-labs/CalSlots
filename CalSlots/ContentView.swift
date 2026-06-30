import SwiftUI

struct ContentView: View {
    @Environment(SyncEngine.self) private var engine

    var body: some View {
        NavigationStack {
            List {
                statusSection
                calendarSection
                syncSection
            }
            .navigationTitle("CalSlots")
        }
    }

    private var statusSection: some View {
        Section("Status") {
            LabeledContent("Workouts synced", value: "\(engine.syncedCount)")

            LabeledContent("Last sync") {
                if let date = engine.lastSyncDate {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Never")
                }
            }

            statusRow
        }
    }

    private var calendarSection: some View {
        Section("Calendar") {
            if engine.calendarAuthorized {
                Picker("Sync workouts to", selection: Binding(
                    get: { engine.selectedCalendarID ?? "" },
                    set: { engine.selectCalendar(id: $0) }
                )) {
                    Text("Choose a calendar…").tag("")
                    ForEach(engine.availableCalendars) { option in
                        Text(option.title).tag(option.id)
                    }
                }
            } else {
                Text("Calendar access is needed to choose a destination.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syncSection: some View {
        Section {
            Button {
                Task { await engine.sync() }
            } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(engine.status == .syncing || engine.selectedCalendarID == nil)
        } footer: {
            Text("Workouts from Health are added to the calendar you choose and kept in sync automatically.")
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        switch engine.status {
        case .idle:
            if engine.needsCalendarSelection {
                Label("Choose a calendar to start syncing", systemImage: "calendar.badge.plus")
                    .foregroundStyle(.secondary)
            } else {
                Label("Up to date", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            }
        case .syncing:
            HStack {
                ProgressView()
                Text("Syncing…")
            }
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    ContentView()
        .environment(SyncEngine.shared)
}

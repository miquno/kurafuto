import SwiftUI

/// Task scheduler: interval, weekday, cron or chained task (after another task + delay).
struct SchedulesView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var state: Loadable<[Schedule]> = .idle
    @State private var editing: Schedule?

    var body: some View {
        LoadableView(state: state, retry: load) { list in
            List {
                Group {
                    ForEach(list) { s in
                        Button { editing = s } label: {
                            HStack {
                                IconTile(symbol: icon(s.action), color: s.enabled ? Theme.accent : Theme.secondaryText, size: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(s.name).font(.headline).foregroundStyle(.primary)
                                    Text(s.summary).font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                                    if let next = s.nextRun, s.enabled {
                                        Text("Next run \(next, style: .relative)").font(.caption2).foregroundStyle(Theme.secondaryText)
                                    }
                                }
                                Spacer()
                                Toggle("", isOn: Binding(get: { s.enabled }, set: { v in
                                    Task { var c = s; c.enabled = v; try? await app.service.updateSchedule(c, serverID: server.id); await load() }
                                })).labelsHidden()
                            }
                        }
                    }
                    .onDelete { idx in
                        Task {
                            for i in idx { try? await app.service.deleteSchedule(id: list[i].id, serverID: server.id) }
                            await load()
                        }
                    }
                }
                .themedRows()
            }
            .themedBackground()
            .entrance()
            .overlay { if list.isEmpty { ContentUnavailableView("No Schedules", systemImage: "calendar") } }
        }
        .navigationTitle("Schedules")
        .toolbar {
            Button { editing = Schedule(id: 0, name: "", enabled: true, action: .restart, interval: 1, intervalType: .days,
                                        command: nil, parent: nil, oneTime: false, cronString: nil, delay: 0, nextRun: nil) }
            label: { Image(systemName: "plus") }
            .accessibilityLabel("New schedule")
        }
        .sheet(item: $editing) { s in
            ScheduleEditor(schedule: s, all: state.value ?? []) { saved in
                Task {
                    if saved.id == 0 { try? await app.service.createSchedule(saved, serverID: server.id) }
                    else { try? await app.service.updateSchedule(saved, serverID: server.id) }
                    await load()
                }
            }
        }
        .task { await load() }
    }

    private func icon(_ a: ScheduleAction) -> String {
        switch a {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        case .backup: "externaldrive.fill"
        case .command, .customCommand: "terminal"
        }
    }

    private func load() async {
        do { state = .loaded(try await app.service.schedules(serverID: server.id)) } catch { state = .failed(error) }
    }
}

struct ScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var schedule: Schedule
    let all: [Schedule]
    let onSave: (Schedule) -> Void
    @State private var mode: Mode = .interval

    enum Mode: String, CaseIterable { case interval = "Interval", cron = "Cron", chain = "After Task" }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    TextField("Name", text: $schedule.name)
                    Picker("Action", selection: $schedule.action) {
                        ForEach([ScheduleAction.start, .stop, .restart, .backup, .customCommand]) { Text($0.label).tag($0) }
                    }
                    if schedule.action == .customCommand || schedule.action == .command {
                        TextField("Command (e.g. say Hello)", text: Binding($schedule.command, replacingNilWith: ""))
                            .monospaced().textInputAutocapitalization(.never)
                    }
                    Section("When") {
                        Picker("Type", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }
                            .pickerStyle(.segmented)
                        switch mode {
                        case .interval:
                            Stepper("Every \(schedule.interval)", value: $schedule.interval, in: 1...999)
                            Picker("Unit", selection: $schedule.intervalType) {
                                ForEach(IntervalType.allCases.filter { $0 != .reaction }) { Text($0.label).tag($0) }
                            }
                        case .cron:
                            TextField("0 4 * * *", text: Binding($schedule.cronString, replacingNilWith: "")).monospaced()
                            Text("minute hour day month weekday").font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                        case .chain:
                            Picker("After", selection: $schedule.parent) {
                                Text("–").tag(Int?.none)
                                ForEach(all.filter { $0.id != schedule.id }) { Text($0.name).tag(Optional($0.id)) }
                            }
                            Stepper("Delay: \(schedule.delay) s", value: $schedule.delay, in: -3600...3600, step: 30)
                        }
                        Toggle("Run only once", isOn: $schedule.oneTime)
                    }
                    Toggle("Enabled", isOn: $schedule.enabled)
                }
                .themedRows()
            }
            .themedBackground()
            .navigationTitle(schedule.id == 0 ? "New Schedule" : "Schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if mode == .interval { schedule.cronString = nil; schedule.parent = nil }
                        if mode == .chain { schedule.intervalType = .reaction; schedule.cronString = nil }
                        onSave(schedule); dismiss()
                    }.disabled(schedule.name.isEmpty)
                }
            }
            .onAppear {
                if schedule.parent != nil { mode = .chain }
                else if !(schedule.cronString ?? "").isEmpty { mode = .cron }
            }
        }
    }
}

extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

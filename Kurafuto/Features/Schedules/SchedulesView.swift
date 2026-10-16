import SwiftUI

/// Task scheduler: interval, cron or chained task (after another task + delay).
/// Crafty 4.7–4.11 cannot list schedules over the API; the screen then only adds new ones.
struct SchedulesView: View {
    @Environment(AppState.self) private var app
    let server: Server
    @State private var state: Loadable<[Schedule]?> = .idle
    @State private var editing: Schedule?
    @State private var confirm: ConfirmAction?
    @State private var actionError: Error?
    @State private var added: [String] = []
    /// Targets for backup schedules; stays empty without the server's backup permission.
    @State private var backupConfigs: [BackupConfig] = []

    var body: some View {
        LoadableView(state: state, retry: load) { list in
            if let list { listed(list) } else { unlisted }
        }
        .navigationTitle("Schedules")
        .destructiveConfirmation($confirm)
        .errorAlert($actionError)
        .toolbar {
            Button { editing = Self.newSchedule } label: { Image(systemName: "plus") }
                .accessibilityLabel("New schedule")
        }
        .sheet(item: $editing) { s in
            ScheduleEditor(schedule: s, all: state.value.flatMap { $0 } ?? [], backupConfigs: backupConfigs) { saved in
                Task {
                    let ok = await $actionError.capture {
                        if saved.id == 0 { try await app.service.createSchedule(saved, serverID: server.id) }
                        else { try await app.service.updateSchedule(saved, serverID: server.id) }
                    }
                    if ok, saved.id == 0 { added.append(saved.name) }
                    await load()
                }
            }
        }
        .task { await load() }
    }

    private static let newSchedule = Schedule(id: 0, name: "", enabled: true, action: .restart, interval: 1, intervalType: .days,
                                              command: nil, parent: nil, oneTime: false, cronString: nil, delay: 0, nextRun: nil)

    private func listed(_ list: [Schedule]) -> some View {
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
                            Toggle("Enabled", isOn: Binding(get: { s.enabled }, set: { v in
                                Task {
                                    var c = s; c.enabled = v
                                    await $actionError.capture { try await app.service.updateSchedule(c, serverID: server.id) }
                                    await load()
                                }
                            })).labelsHidden()
                        }
                    }
                }
                .onDelete { idx in
                    let doomed = idx.map { list[$0] }
                    confirm = ConfirmAction(title: String(localized: "Delete \(doomed.count) schedules?"),
                                            message: doomed.map(\.name).joined(separator: ", "),
                                            buttonLabel: String(localized: "Delete")) {
                        await $actionError.capture {
                            for s in doomed { try await app.service.deleteSchedule(id: s.id, serverID: server.id) }
                        }
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

    private var unlisted: some View {
        ContentUnavailableView {
            Label("Schedules Not Listed", systemImage: "calendar.badge.clock")
        } description: {
            VStack(spacing: 8) {
                Text("Crafty's API cannot list schedules yet. New schedules you add here run on the panel; view, edit and delete them in the web panel.")
                if !added.isEmpty {
                    Text("Added: \(added.joined(separator: ", "))").font(.footnote).foregroundStyle(Theme.accent)
                }
            }
        } actions: {
            Button("New Schedule") { editing = Self.newSchedule }
                .buttonStyle(InstrumentButtonStyle()).frame(width: 200)
            if let url = app.webPanelURL(serverID: server.id, subpage: "schedules") {
                Link("Open Web Panel", destination: url).font(.subheadline).tint(Theme.accent)
            }
        }
        .themedBackground()
        .entrance()
    }

    private func icon(_ a: ScheduleAction) -> String {
        switch a {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        case .backup: "externaldrive.fill"
        case .command: "terminal"
        }
    }

    private func load() async {
        do { state = .loaded(try await app.service.schedules(serverID: server.id)) } catch { state = .failed(error) }
        if backupConfigs.isEmpty { backupConfigs = (try? await app.service.backupConfigs(serverID: server.id)) ?? [] }
    }
}

struct ScheduleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var schedule: Schedule
    let all: [Schedule]
    let backupConfigs: [BackupConfig]
    let onSave: (Schedule) -> Void
    @State private var mode: Mode = .interval

    enum Mode: CaseIterable {
        case interval, cron, chain

        var label: String {
            switch self {
            case .interval: String(localized: "Interval")
            case .cron: String(localized: "Cron")
            case .chain: String(localized: "After Task")
            }
        }
    }

    private var parents: [Schedule] { all.filter { $0.id != schedule.id } }
    private var modes: [Mode] { parents.isEmpty && mode != .chain ? [.interval, .cron] : Mode.allCases }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    TextField("Name", text: $schedule.name)
                    Picker("Action", selection: $schedule.action) {
                        ForEach(actions) { Text($0.label).tag($0) }
                    }
                    if schedule.action == .backup {
                        Picker("Backup", selection: $schedule.backupID) {
                            if schedule.backupID == nil { Text(verbatim: "–").tag(String?.none) }
                            ForEach(backupConfigs) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    if schedule.action == .command {
                        TextField("Command (e.g. say Hello)", text: Binding($schedule.command, replacingNilWith: ""))
                            .monospaced().textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    Section("When") {
                        Picker("Type", selection: $mode) { ForEach(modes, id: \.self) { Text($0.label) } }
                            .pickerStyle(.segmented)
                        switch mode {
                        case .interval:
                            Stepper("Every \(schedule.interval)", value: $schedule.interval, in: 1...999)
                            Picker("Unit", selection: $schedule.intervalType) {
                                ForEach([IntervalType.minutes, .hours, .days]) { Text($0.label).tag($0) }
                            }
                            if schedule.intervalType == .days {
                                DatePicker("At (panel time)", selection: startTime, displayedComponents: .hourAndMinute)
                            }
                        case .cron:
                            TextField("0 4 * * *", text: Binding($schedule.cronString, replacingNilWith: ""))
                                .monospaced().textInputAutocapitalization(.never).autocorrectionDisabled()
                            Text("minute hour day month weekday").font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
                        case .chain:
                            Picker("Run after", selection: $schedule.parent) {
                                Text(verbatim: "–").tag(Int?.none)
                                ForEach(parents) { Text($0.name).tag(Optional($0.id)) }
                            }
                            Stepper("Delay: \(schedule.delay) s", value: $schedule.delay, in: 0...3600, step: 30)
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
                    Button("Save") { onSave(prepared); dismiss() }.disabled(!isComplete)
                }
            }
            .onAppear {
                switch schedule.intervalType {
                case .reaction: mode = .chain
                case .cron: mode = .cron
                case .minutes, .hours, .days: mode = .interval
                }
            }
            .onChange(of: schedule.action) { _, new in
                if new == .backup, schedule.backupID == nil { schedule.backupID = backupConfigs.first?.id }
            }
            .onChange(of: mode) { _, new in
                if new == .interval, ![.minutes, .hours, .days].contains(schedule.intervalType) { schedule.intervalType = .days }
            }
        }
    }

    /// Backup schedules need a backup config to run.
    private var actions: [ScheduleAction] {
        [.start, .stop, .restart] + (backupConfigs.isEmpty && schedule.action != .backup ? [] : [.backup]) + [.command]
    }

    private var isComplete: Bool {
        guard !schedule.name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if schedule.action == .command, (schedule.command ?? "").trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if schedule.action == .backup, schedule.backupID == nil { return false }
        switch mode {
        case .interval: return true
        case .cron: return !(schedule.cronString ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        case .chain: return schedule.parent != nil
        }
    }

    private var prepared: Schedule {
        var s = schedule
        switch mode {
        case .interval: break
        case .cron: s.intervalType = .cron; s.cronString = s.cronString?.trimmingCharacters(in: .whitespaces)
        case .chain: s.intervalType = .reaction
        }
        return s
    }

    private var startTime: Binding<Date> {
        Binding(get: {
            let parts = schedule.startTime.split(separator: ":").compactMap { Int($0) }
            let comps = DateComponents(hour: parts.first ?? 0, minute: parts.count > 1 ? parts[1] : 0)
            return Calendar.current.date(from: comps) ?? .now
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            schedule.startTime = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        })
    }
}

extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith fallback: String) {
        self.init(get: { source.wrappedValue ?? fallback }, set: { source.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

#Preview {
    NavigationStack { SchedulesView(server: MockData.servers[0]) }.environment(AppState.preview)
}

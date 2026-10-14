import SwiftUI

/// Host overview: CPU/RAM/disk of the machine, panel version, announcements from the panel.
struct PanelOverviewView: View {
    @Environment(AppState.self) private var app
    @State private var host: HostStats?
    @State private var news: [Announcement] = []

    var body: some View {
        NavigationStack {
            List {
                if let h = host {
                    Section("Host") {
                        HStack(spacing: 10) {
                            MetricCard(title: "CPU", value: h.cpuPercent, caption: String(format: "%.0f%%", h.cpuPercent))
                            MetricCard(title: "RAM", value: h.memPercent, caption: String(format: "%.0f%%", h.memPercent))
                        }
                        .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                        ForEach(h.diskUsage) { d in
                            VStack(alignment: .leading) {
                                HStack { Text(d.mount).monospaced(); Spacer()
                                    Text("\(Int(d.usedGB)) / \(Int(d.totalGB)) GB").font(.caption).foregroundStyle(.secondary) }
                                ProgressView(value: d.usedGB, total: d.totalGB)
                            }
                        }
                        LabeledContent("Panel version", value: h.craftyVersion)
                    }
                } else {
                    ProgressView()
                }

                Section("Announcements") {
                    if news.isEmpty { Text("No new announcements").foregroundStyle(.secondary) }
                    ForEach(news) { n in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(n.title).font(.headline)
                            Text(n.desc).font(.subheadline).foregroundStyle(.secondary)
                            Text(n.date).font(.caption2).foregroundStyle(.tertiary)
                        }
                        .swipeActions {
                            Button("Dismiss") {
                                Task { try? await app.service.clearAnnouncement(id: n.id); news.removeAll { $0.id == n.id } }
                            }.tint(Theme.accent)
                        }
                    }
                }
            }
            .navigationTitle("Panel")
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private func load() async {
        host = try? await app.service.hostStats()
        news = (try? await app.service.announcements()) ?? []
    }
}

#Preview { PanelOverviewView().environment(AppState.preview) }

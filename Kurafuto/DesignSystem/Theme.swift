import SwiftUI

/// Own visual identity – deliberately do NOT copy the Crafty or Minecraft logo/color scheme
/// (trademark law, App Review guideline 4.1).
enum Theme {
    static let accent = Color(red: 0.25, green: 0.73, blue: 0.31)     // "grass green", our own color
    static let console = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let cardRadius: CGFloat = 16

    static func color(for status: ServerStatus) -> Color {
        switch status {
        case .online: .green
        case .offline: .secondary
        case .starting, .updating: .orange
        case .crashed: .red
        }
    }
}

struct StatusBadge: View {
    let status: ServerStatus
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.color(for: status)).frame(width: 8, height: 8)
                .overlay {
                    if status == .starting || status == .updating {
                        Circle().stroke(Theme.color(for: status).opacity(0.4), lineWidth: 4)
                            .scaleEffect(1.6)
                    }
                }
            Text(status.label).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.color(for: status).opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct MetricCard: View {
    let title: String
    let value: Double   // 0…100
    let caption: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(caption).font(.title3.monospacedDigit().weight(.semibold))
            ProgressView(value: min(max(value, 0), 100), total: 100)
                .tint(value > 85 ? .red : value > 65 ? .orange : Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// Uniform loading/error wrapper for every list.
enum Loadable<T> {
    case idle, loading, loaded(T), failed(Error)

    var value: T? { if case .loaded(let v) = self { v } else { nil } }
}

struct LoadableView<T, Content: View>: View {
    let state: Loadable<T>
    let retry: () async -> Void
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Error", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await retry() } }.buttonStyle(.borderedProminent)
            }
        case .loaded(let v):
            content(v)
        }
    }
}

extension Int64 {
    var byteString: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

/// Confirmation helper for dangerous actions (stop, kill, delete).
struct ConfirmAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let buttonLabel: String
    let perform: () async -> Void
}

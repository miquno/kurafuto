import SwiftUI

/// "Instrument" design: graphite surfaces, monospaced data, one accent color per metric.
/// Own visual identity – deliberately do NOT copy the Crafty or Minecraft logo/color scheme
/// (trademark law, App Review guideline 4.1).
/// Colors read `Appearance.shared`, so any view using them redraws when the user changes the look.
@MainActor
enum Theme {
    static let cardRadius: CGFloat = 20
    static let tileRadius: CGFloat = 14

    private static var mode: ThemeMode { Appearance.shared.mode }

    // MARK: Surfaces

    static var background: Color { background(for: mode) }
    static var surface: Color { surface(for: mode) }

    /// Per-mode variants, e.g. for the theme previews in Settings.
    static func background(for mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x0A0C0F)
        case .gray: Color(hex: 0x1C2026)
        case .light: Color(hex: 0xF2F4F6)
        }
    }

    static func surface(for mode: ThemeMode) -> Color {
        switch mode {
        case .dark: Color(hex: 0x12161B)
        case .gray: Color(hex: 0x262B32)
        case .light: Color(hex: 0xFFFFFF)
        }
    }

    static func primaryText(for mode: ThemeMode) -> Color {
        mode == .light ? Color(hex: 0x0D0F12) : Color(hex: 0xEDEFF2)
    }

    /// Inset areas inside a card (gauge tiles, icon tiles).
    static var sunken: Color {
        switch mode {
        case .dark: Color(hex: 0x0D1014)
        case .gray: Color(hex: 0x20252B)
        case .light: Color(hex: 0xF4F6F8)
        }
    }

    static var stroke: Color {
        switch mode {
        case .dark: Color(hex: 0x252B33)
        case .gray: Color(hex: 0x363D46)
        case .light: Color(hex: 0xE1E5EA)
        }
    }

    static var divider: Color {
        switch mode {
        case .dark: Color(hex: 0x1E242B)
        case .gray: Color(hex: 0x2F353D)
        case .light: Color(hex: 0xE8EBEF)
        }
    }

    /// Ring and meter tracks.
    static var track: Color {
        switch mode {
        case .dark: Color(hex: 0x232930)
        case .gray: Color(hex: 0x353C45)
        case .light: Color(hex: 0xE4E8EC)
        }
    }

    static var secondaryText: Color {
        switch mode {
        case .dark: Color(hex: 0x8D96A1)
        case .gray: Color(hex: 0xA3ACB7)
        case .light: Color(hex: 0x5A626D)
        }
    }

    /// The console stays dark in every mode, so its line colors always use the dark-mode shades.
    static let console = Color(hex: 0x07090B)
    static let consoleText = Color(hex: 0xC3C9D0)
    static let consoleWarning = AccentPreset.amber.color(for: .dark)
    static let consoleError = Color(hex: 0xFF6B5E)
    static var consoleCommand: Color { Appearance.shared.preset(for: .accent).color(for: .dark) }
    static var consoleChat: Color { Appearance.shared.preset(for: .players).color(for: .dark) }

    // MARK: Accents

    static var accent: Color { Appearance.shared.color(for: .accent) }
    static var cpu: Color { Appearance.shared.color(for: .cpu) }
    static var ram: Color { Appearance.shared.color(for: .ram) }
    static var players: Color { Appearance.shared.color(for: .players) }
    static var storage: Color { Appearance.shared.color(for: .storage) }

    /// Text and icons placed on an accent fill.
    static var onAccent: Color { mode == .light ? .white : Color(hex: 0x0A0C0F) }

    static var danger: Color { mode == .light ? Color(hex: 0xC62828) : consoleError }
    static var warning: Color { AccentPreset.amber.color(for: mode) }

    static func color(for status: ServerStatus) -> Color {
        switch status {
        case .online: accent
        case .offline: secondaryText
        case .starting, .updating: warning
        case .crashed: danger
        }
    }
}

extension Font {
    /// Monospaced data font (SF Mono) that still follows Dynamic Type.
    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

// MARK: - Surfaces

extension View {
    /// The standard raised card: surface fill, hairline stroke, large radius.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Screen background for scroll views, lists and forms.
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }

    /// Row styling for `List`/`Form` content. Apply to a `Group` around the sections.
    func themedRows() -> some View {
        modifier(ThemedRows())
    }
}

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.stroke))
    }
}

private struct ThemedBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            // List cells keep the separator tint they were created with, so a mode switch
            // would leave dark separators on light rows. A new identity rebuilds the cells;
            // screen state is unaffected because it lives outside the list.
            .id(Appearance.shared.mode)
            .background(Theme.background.ignoresSafeArea())
    }
}

private struct ThemedRows: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Theme.surface)
            .listRowSeparatorTint(Theme.divider)
    }
}

/// Small uppercase monospaced label above a group of cards.
struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(.mono(.caption2, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Rounded square holding a symbol, as used in list rows and the panel header.
struct IconTile: View {
    let symbol: String
    var color: Color = Theme.accent
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(Theme.stroke))
            .accessibilityHidden(true)
    }
}

// MARK: - Status

/// Status dot with a halo; online and starting servers "breathe" unless Reduce Motion is on.
struct StatusDot: View {
    let status: ServerStatus
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var animated: Bool { !reduceMotion && [.online, .starting, .updating].contains(status) }

    var body: some View {
        let color = Theme.color(for: status)
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(color.opacity(pulse ? 0.05 : 0.22))
                    .frame(width: size * (pulse ? 2.8 : 2), height: size * (pulse ? 2.8 : 2))
            }
            .frame(width: size * 2.8, height: size * 2.8)
            .onAppear { startPulse() }
            .onChange(of: status) { pulse = false; startPulse() }
            .accessibilityHidden(true)
    }

    private func startPulse() {
        guard animated else { return }
        let speed = status == .online ? 1.6 : 0.7
        withAnimation(.easeInOut(duration: speed).repeatForever(autoreverses: true)) { pulse = true }
    }
}

struct StatusBadge: View {
    let status: ServerStatus
    var body: some View {
        HStack(spacing: 2) {
            StatusDot(status: status, size: 6)
            Text(status.label.uppercased()).font(.mono(.caption2, weight: .semibold))
        }
        .foregroundStyle(Theme.color(for: status))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Gauges

/// Circular gauge for a 0…100 value. Fills up when it appears and follows live changes.
struct RingGauge: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 6
    var delay: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var clamped: Double { min(max(value, 0), 100) }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(clamped.rounded()))%")
                .font(.mono(.subheadline, weight: .semibold))
                .contentTransition(.numericText(value: clamped))
                .animation(.snappy, value: clamped)
        }
        .padding(lineWidth / 2)
        .onAppear {
            if reduceMotion { shown = clamped; return }
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(delay)) { shown = clamped }
        }
        .onChange(of: clamped) { _, new in
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85)) { shown = new }
        }
    }
}

/// Inset tile with a ring gauge and a caption, as in the dashboard's featured server.
struct GaugeTile: View {
    let title: String
    let value: Double
    let color: Color
    var caption: String?
    var delay: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            RingGauge(value: value, color: color, delay: delay)
                .frame(width: 64, height: 64)
            Text(caption.map { "\(title) \($0)" } ?? title)
                .font(.mono(.caption2))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(caption.map { "\(Int(value.rounded())) percent, \($0)" } ?? "\(Int(value.rounded())) percent")
    }
}

/// Inset tile with a single value, the gauge tiles' plain sibling.
struct ValueTile: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.mono(.caption2)).foregroundStyle(Theme.secondaryText)
            Text(value).font(.mono(.title3, weight: .semibold)).foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Thin horizontal meter for a value within a total.
struct MeterBar: View {
    let value: Double
    var total: Double = 100
    let color: Color
    var height: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var fraction: Double { total > 0 ? min(max(value / total, 0), 1) : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: geo.size.width * shown)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) { shown = fraction }
        }
        .onChange(of: fraction) { _, new in
            withAnimation(reduceMotion ? nil : .snappy) { shown = new }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

extension View {
    /// Build-up animation: content rises, sharpens and fades in, staggered by `index`.
    /// Reduce Motion keeps only a short fade.
    func entrance(_ index: Int = 0) -> some View {
        modifier(EntranceModifier(index: index))
    }
}

private struct EntranceModifier: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 18)
            .scaleEffect(visible || reduceMotion ? 1 : 0.97)
            .blur(radius: visible || reduceMotion ? 0 : 6)
            .onAppear {
                guard !visible else { return }
                let animation: Animation = reduceMotion
                    ? .easeOut(duration: 0.2)
                    : .spring(response: 0.6, dampingFraction: 0.82).delay(Double(min(index, 12)) * 0.06)
                withAnimation(animation) { visible = true }
            }
    }
}

/// Primary and tinted buttons in the Instrument look.
struct InstrumentButtonStyle: ButtonStyle {
    enum Kind { case filled, tinted, outline }
    var kind: Kind = .filled
    var color: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        InstrumentButton(configuration: configuration, kind: kind, color: color)
    }

    private struct InstrumentButton: View {
        let configuration: Configuration
        let kind: Kind
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
                .overlay {
                    if kind == .outline {
                        RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous).strokeBorder(Theme.stroke)
                    }
                }
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.snappy(duration: 0.2), value: configuration.isPressed)
        }

        private var foreground: Color {
            switch kind {
            case .filled: Theme.onAccent
            case .tinted: color
            case .outline: .primary
            }
        }

        private var background: Color {
            switch kind {
            case .filled: color
            case .tinted: color.opacity(0.14)
            case .outline: Theme.sunken
            }
        }
    }
}

// MARK: - Loading

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
            ProgressView().tint(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
        case .failed(let error):
            ContentUnavailableView {
                Label("Error", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error.localizedDescription)
            } actions: {
                Button("Try Again") { Task { await retry() } }
                    .buttonStyle(InstrumentButtonStyle()).frame(width: 160)
            }
            .background(Theme.background.ignoresSafeArea())
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

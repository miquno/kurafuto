import SwiftUI

/// "4/20" players, with an animated count.
struct PlayerCount: View {
    let online: Int
    let max: Int
    var large = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: "\(online)")
                .font(.mono(large ? .title : .subheadline, weight: .semibold))
                .contentTransition(.numericText(value: Double(online)))
                .animation(.snappy, value: online)
            Text(verbatim: "/\(max)")
                .font(.mono(large ? .subheadline : .caption))
                .foregroundStyle(Theme.secondaryText)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Players: \(online) of \(max)")
    }
}

/// The server's own icon from the panel, or a symbol for its type.
struct ServerIcon: View {
    let base64: String?
    let type: ServerType
    var body: some View {
        if let b = base64, let d = Data(base64Encoded: b), let img = UIImage(data: d) {
            Image(uiImage: img).resizable().interpolation(.none)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
        } else {
            IconTile(symbol: type.symbol, size: 44)
        }
    }
}

import LocalAuthentication
import SwiftUI

/// What the device offers for `deviceOwnerAuthentication`: biometrics with passcode fallback, or the passcode alone.
enum DeviceAuthKind: Equatable {
    case faceID, touchID, opticID, passcode, unavailable

    var label: String {
        switch self {
        case .faceID: String(localized: "Face ID")
        case .touchID: String(localized: "Touch ID")
        case .opticID: String(localized: "Optic ID")
        case .passcode, .unavailable: String(localized: "Passcode")
        }
    }

    var symbol: String {
        switch self {
        case .faceID: "faceid"
        case .touchID: "touchid"
        case .opticID: "opticid"
        case .passcode, .unavailable: "lock.fill"
        }
    }
}

protocol DeviceAuthenticating: Sendable {
    func kind() -> DeviceAuthKind
    func authenticate(reason: String) async -> Bool
}

/// iOS shows the prompt and only answers yes or no; Kurafuto never sees biometric data.
struct SystemAuthenticator: DeviceAuthenticating {
    func kind() -> DeviceAuthKind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return .unavailable }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .passcode
        }
    }

    func authenticate(reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Optional app lock: Face ID (or the passcode) when Kurafuto opens or returns from the background,
/// and before destructive actions.
@Observable
final class AppLock {
    static let defaultsKey = "faceID"

    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private var isAuthenticating = false
    private let authenticator: DeviceAuthenticating
    private let defaults: UserDefaults?

    /// `defaults: nil` gives a lock that is off and not persisted (previews, demo builds of views).
    init(authenticator: DeviceAuthenticating = SystemAuthenticator(), defaults: UserDefaults? = .standard) {
        self.authenticator = authenticator
        self.defaults = defaults
        let enabled = defaults?.bool(forKey: Self.defaultsKey) ?? false
        isEnabled = enabled
        isLocked = enabled
    }

    var kind: DeviceAuthKind { authenticator.kind() }

    @MainActor
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(String(localized: "Unlock Kurafuto")) { isLocked = false }
    }

    @MainActor
    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    /// Gate for destructive actions. Always true while the lock is off.
    @MainActor
    func authorize(_ reason: String) async -> Bool {
        guard isEnabled else { return true }
        return await authenticate(reason)
    }

    /// Turning the lock on or off needs a successful check, so it can't be switched off by someone else
    /// and can't be switched on when the device can't authenticate.
    @MainActor
    func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled, kind != .unavailable,
              await authenticate(enabled ? String(localized: "Turn on the app lock") : String(localized: "Turn off the app lock")) else { return }
        isEnabled = enabled
        defaults?.set(enabled, forKey: Self.defaultsKey)
    }

    @MainActor
    private func authenticate(_ reason: String) async -> Bool {
        // Without a passcode there is nothing to check against; removing the passcode already needs it,
        // so letting the user in here never locks them out of their own servers.
        guard kind != .unavailable else { return true }
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        return await authenticator.authenticate(reason: reason)
    }
}

/// Covers the whole app while it is locked.
struct LockView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Kurafuto is locked")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Button {
                Task { await app.lock.unlock() }
            } label: {
                Label("Unlock with \(app.lock.kind.label)", systemImage: app.lock.kind.symbol)
            }
            .buttonStyle(InstrumentButtonStyle())
            .frame(maxWidth: 280)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ignoresSafeArea()
    }
}

extension View {
    /// Confirmation dialog for a `ConfirmAction`. With the app lock on, the action also needs Face ID or the passcode.
    func destructiveConfirmation(_ confirm: Binding<ConfirmAction?>) -> some View {
        modifier(DestructiveConfirmation(confirm: confirm))
    }
}

private struct DestructiveConfirmation: ViewModifier {
    @Environment(AppState.self) private var app
    @Binding var confirm: ConfirmAction?

    func body(content: Content) -> some View {
        content.confirmationDialog(confirm?.title ?? "", isPresented: .constant(confirm != nil), titleVisibility: .visible,
                                   presenting: confirm) { c in
            Button(c.buttonLabel, role: .destructive) {
                confirm = nil
                Task { if await app.lock.authorize(c.title) { await c.perform() } }
            }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { Text($0.message) }
    }
}

#Preview { LockView().environment(AppState.preview) }

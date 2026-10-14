import SwiftUI

@main
struct KurafutoApp: App {
    @State private var app = AppState.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

/// Global state: active instance + service. The whole UI depends only on `service: CraftyService`.
@Observable
final class AppState {
    var instanceStore: InstanceStore
    var activeInstance: Instance?
    var service: CraftyService
    var isMock: Bool
    var requireFaceID = false
    var isUnlocked = true
    /// Panel-wide rights of the signed-in user; nil until loaded or when loading failed.
    var access: PanelAccess?

    init(instanceStore: InstanceStore, service: CraftyService, activeInstance: Instance?, isMock: Bool) {
        self.instanceStore = instanceStore
        self.service = service
        self.activeInstance = activeInstance
        self.isMock = isMock
    }

    static func bootstrap() -> AppState {
        if ProcessInfo.processInfo.arguments.contains("-mock") {
            return .preview
        }
        let store = InstanceStore()
        let first = store.instances.first
        let service: CraftyService = first.map { inst in
            LiveCraftyService(client: APIClient(baseURL: inst.baseURL, token: store.token(for: inst),
                                                pinnedSHA256: inst.pinnedCertificateSHA256))
        } ?? MockCraftyService()
        return AppState(instanceStore: store, service: service, activeInstance: first, isMock: first == nil)
    }

    static var preview: AppState {
        AppState(instanceStore: InstanceStore(preview: [MockData.instance]),
                 service: MockCraftyService(latency: .milliseconds(250)),
                 activeInstance: MockData.instance, isMock: true)
    }

    func switchTo(_ instance: Instance) {
        // Re-selecting the active panel must not rebuild the service: in demo mode that would
        // replace the mock with a live client pointed at the sample address.
        guard instance.id != activeInstance?.id else { return }
        activeInstance = instance
        access = nil
        service = LiveCraftyService(client: APIClient(baseURL: instance.baseURL,
                                                      token: instanceStore.token(for: instance),
                                                      pinnedSHA256: instance.pinnedCertificateSHA256))
        isMock = false
    }

    func startDemo() {
        activeInstance = MockData.instance
        access = nil
        service = MockCraftyService()
        isMock = true
    }

    func signOut() {
        if let i = activeInstance, !isMock { instanceStore.remove(i) }
        activeInstance = nil
        access = nil
    }
}

extension AppState {
    @MainActor
    func refreshAccess() async {
        access = try? await service.panelAccess()
    }

    // While the rights are unknown, the UI stays complete: the panel enforces them on every request
    // and its errors are shown, which beats hiding the Admin tab from a superuser on a slow network.
    var canCreateServers: Bool { access?.canCreateServers ?? true }
    var canAddUsers: Bool { access?.canAddUsers ?? true }
    var canAddRoles: Bool { access?.canAddRoles ?? true }
    var canManageUsers: Bool { access?.canManageUsers ?? true }
    var canManageRoles: Bool { access?.canManageRoles ?? true }
    var showsAdmin: Bool { access?.showsAdmin ?? true }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if app.activeInstance == nil {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(Appearance.shared.mode.colorScheme)
        // Hides panel addresses, IPs and console output from the app switcher snapshot.
        .overlay {
            if scenePhase != .active {
                ZStack {
                    Rectangle().fill(Theme.background)
                    Image(systemName: "cube.transparent.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
                }
                .ignoresSafeArea()
            }
        }
    }
}

struct MainTabView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Servers", systemImage: "server.rack") }
            PanelOverviewView()
                .tabItem { Label("Panel", systemImage: "gauge.with.dots.needle.50percent") }
            if app.showsAdmin {
                AdminView()
                    .tabItem { Label("Admin", systemImage: "person.2.badge.gearshape") }
            }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task(id: app.activeInstance?.id) { await app.refreshAccess() }
    }
}

#Preview { RootView().environment(AppState.preview) }

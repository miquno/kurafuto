import SwiftUI

@main
struct KurafutoApp: App {
    @State private var app = AppState.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.accent)
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
        activeInstance = instance
        service = LiveCraftyService(client: APIClient(baseURL: instance.baseURL,
                                                      token: instanceStore.token(for: instance),
                                                      pinnedSHA256: instance.pinnedCertificateSHA256))
        isMock = false
    }

    func startDemo() {
        activeInstance = MockData.instance
        service = MockCraftyService()
        isMock = true
    }

    func signOut() {
        if let i = activeInstance, !isMock { instanceStore.remove(i) }
        activeInstance = nil
    }
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
        // Hides panel addresses, IPs and console output from the app switcher snapshot.
        .overlay {
            if scenePhase != .active {
                ZStack {
                    Rectangle().fill(.background)
                    Image(systemName: "cube.transparent.fill").font(.system(size: 56)).foregroundStyle(Theme.accent)
                }
                .ignoresSafeArea()
            }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Servers", systemImage: "server.rack") }
            PanelOverviewView()
                .tabItem { Label("Panel", systemImage: "gauge.with.dots.needle.50percent") }
            AdminView()
                .tabItem { Label("Admin", systemImage: "person.2.badge.gearshape") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview { RootView().environment(AppState.preview) }

import SwiftUI
import Combine

@MainActor
final class AppBootstrap: ObservableObject {
    @Published var store: AppStore?
    @Published var errorMessage: String?

    init() { load() }

    func load() {
        do {
            store = AppStore(repo: try FocusRepository.open())
            errorMessage = nil
        } catch {
            errorMessage = "No se pudo abrir tu historial. \(error.localizedDescription)"
        }
    }
}

@main
@MainActor
struct FocusTimeApp: App {
    @StateObject private var bootstrap = AppBootstrap()
    @StateObject private var manualUsage = ManualUsageStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if let store = bootstrap.store {
                    RootTabView()
                        .environmentObject(store)
                        .environmentObject(manualUsage)
                        .task {
                            manualUsage.becameActive()
                            await store.becameActive()
                        }
                        .onChange(of: scenePhase) { _, phase in
                            if phase == .active {
                                manualUsage.becameActive()
                                Task { await store.becameActive() }
                            } else if phase == .background {
                                store.becameInactive()
                                manualUsage.becameInactive()
                            }
                        }
                } else {
                    ContentUnavailableView {
                        Label("No se pudo abrir FocusTime", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(bootstrap.errorMessage ?? "Inténtalo de nuevo.")
                    } actions: {
                        Button("Reintentar") { bootstrap.load() }
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "es"))
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            HomeView().tabItem { Label("Inicio", systemImage: "house.fill") }
            ApplicationAccessView().tabItem { Label("Apps", systemImage: "apps.iphone") }
            ProgressDashboardView().tabItem { Label("Progreso", systemImage: "chart.bar.fill") }
            SettingsView().tabItem { Label("Configuración", systemImage: "gearshape.fill") }
        }
        .tint(Theme.primary)
        .alert("Aviso", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

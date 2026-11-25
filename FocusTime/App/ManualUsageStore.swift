import Foundation
import Combine

/// Contadores iniciados y detenidos por la persona. No observa otras apps.
@MainActor
final class ManualUsageStore: ObservableObject {
    @Published private(set) var snapshot = ManualUsageSnapshot.empty
    @Published private(set) var now = Date()
    @Published private(set) var isAvailable = false
    @Published var errorMessage: String?

    private var repository: ManualUsageRepository?
    private var ticker: AnyCancellable?

    init() { reload() }

    func reload() {
        now = Date()
        do {
            let opened = try ManualUsageRepository.open()
            repository = opened
            snapshot = opened.snapshot()
            isAvailable = true
            errorMessage = nil
        } catch {
            repository = nil
            isAvailable = false
            errorMessage = "No se pudo abrir el registro manual. \(error.localizedDescription)"
        }
    }

    func becameActive() {
        reload()
        guard ticker == nil else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] in self?.now = $0 }
    }

    func becameInactive() {
        ticker?.cancel()
        ticker = nil
    }

    @discardableResult
    func addApp(name: String) -> Bool { perform { try $0.addApp(name: name) } }

    @discardableResult
    func renameApp(id: UUID, name: String) -> Bool { perform { try $0.renameApp(id: id, name: name) } }

    @discardableResult
    func deleteApp(id: UUID) -> Bool { perform { try $0.deleteApp(id: id) } }

    @discardableResult
    func start(appID: UUID) -> Bool { perform { try $0.start(appID: appID, at: now) } }

    @discardableResult
    func stop() -> Bool { perform { try $0.stop(at: now) } }

    @discardableResult
    func clearHistory() -> Bool { perform { try $0.clearHistory() } }

    private func perform(_ action: (ManualUsageRepository) throws -> Void) -> Bool {
        now = Date()
        guard let repository, isAvailable else {
            errorMessage = "El registro manual no está disponible. Toca Reintentar antes de guardar."
            return false
        }
        do {
            try action(repository)
            snapshot = repository.snapshot()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

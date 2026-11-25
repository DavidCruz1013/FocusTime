import Foundation
import Combine

enum Validation {
    static func range(_ value: Int, _ range: ClosedRange<Int>, _ field: String) throws {
        guard range.contains(value) else {
            throw AppError.validation("\(field) debe ser un entero entre \(range.lowerBound) y \(range.upperBound).")
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var settings = Settings()
    @Published private(set) var session: FocusSession?
    @Published private(set) var activeBreak: BreakRecord?
    @Published private(set) var todayGoal: GoalItem?
    @Published private(set) var today = DayStat.empty
    @Published private(set) var weekly: [DailyBar] = []
    @Published private(set) var now = Date()
    @Published private(set) var savingSettings = false
    @Published private(set) var notificationsAuthorized = false
    @Published var errorMessage: String?
    @Published var suggestBreak = false

    private let repo: FocusRepository
    private let notifier = NotificationManager()
    private var ticker: AnyCancellable?

    init(repo: FocusRepository) {
        self.repo = repo
        notifier.onError = { [weak self] in self?.errorMessage = $0 }
        reload()
        startTicker()
    }

    func becameActive() async {
        reload()
        startTicker()
        notificationsAuthorized = await notifier.isAuthorized()
        // Una preferencia antigua o un permiso revocado nunca habilita la función.
        if settings.notifications && !notificationsAuthorized {
            var updated = settings
            updated.notifications = false
            perform { try repo.saveSettings(updated) }
        }
        syncNotifications()
    }

    func becameInactive() {
        ticker?.cancel()
        ticker = nil
        syncNotifications()
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] in self?.tick($0) }
    }

    func reload() { perform { try autoClose() } }

    private func tick(_ date: Date) {
        let previousDay = DateCodec.dayKey(now)
        now = date
        let sessionDone = session.map { $0.isRunning && $0.remainingSeconds(at: date) == 0 } ?? false
        let breakDone = activeBreak.map { $0.remaining(at: date) == 0 } ?? false
        if sessionDone || breakDone || previousDay != DateCodec.dayKey(date) { reload() }
    }

    /// El cierre se registra en la fecha límite, aunque iOS suspenda el proceso
    /// hasta que el usuario vuelva. El aviso lo entrega iOS, no el Timer de la UI.
    private func autoClose() throws {
        if let s = try repo.activeSession(), s.isRunning, s.remainingSeconds(at: now) == 0 {
            try repo.finish(s, at: s.deadline ?? now, completed: true)
            suggestBreak = true
        }
        if let b = try repo.activeBreak(), b.remaining(at: now) == 0 {
            try repo.finishBreak(b, at: b.deadline, completed: true)
        }
    }

    @discardableResult
    func startSession(minutes: Int) -> Bool {
        perform {
            try autoClose()
            try Validation.range(minutes, 1...180, "La duración")
            try repo.startSession(seconds: minutes * 60, at: now)
            suggestBreak = false
        }
    }

    func pauseSession() {
        perform {
            try autoClose()
            if let s = try repo.activeSession(), s.isRunning { try repo.pause(s, at: now) }
        }
    }

    func resumeSession() {
        perform {
            try autoClose()
            if let s = try repo.activeSession(), !s.isRunning { try repo.resume(s, at: now) }
        }
    }

    func finishSession(completed: Bool) {
        perform {
            try autoClose()
            if let s = try repo.activeSession() {
                try repo.finish(s, at: now, completed: completed)
                if completed { suggestBreak = true }
            }
        }
    }

    func startBreak() {
        perform {
            try autoClose()
            try repo.startBreak(seconds: settings.breakMinutes * 60, at: now)
            suggestBreak = false
        }
    }

    func cancelBreak() {
        perform {
            try autoClose()
            if let b = try repo.activeBreak() { try repo.finishBreak(b, at: now, completed: false) }
        }
    }

    /// Valida primero; el diálogo del sistema aparece únicamente tras Guardar
    /// con la opción de notificaciones activada por el usuario.
    func saveSettings(_ draft: Settings) async -> Bool {
        guard !savingSettings else { return false }
        savingSettings = true
        defer { savingSettings = false }
        do {
            try Validation.range(draft.sessionMinutes, 1...180, "La duración de concentración")
            try Validation.range(draft.workMinutes, 1...180, "El intervalo de trabajo")
            try Validation.range(draft.breakMinutes, 1...60, "La duración del descanso")
            var updated = draft
            // El control real de apps se administra de manera independiente.
            updated.limitsEnabled = false
            if draft.notifications {
                notificationsAuthorized = try await notifier.requestAuthorizationIfNeeded()
                guard notificationsAuthorized else {
                    errorMessage = "No se activaron las notificaciones. Autorízalas en Ajustes del iPhone > Notificaciones > FocusTime y vuelve a guardar."
                    return false
                }
            }
            return perform { try repo.saveSettings(updated) }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func goals(on day: Date) -> [GoalItem] {
        do { return try repo.goals(on: DateCodec.dayKey(day)) }
        catch { return [] }
    }

    @discardableResult
    func saveGoal(_ type: GoalType, target: Int, day: Date) -> Bool {
        perform {
            try Validation.range(target, 1...10_000, "El objetivo")
            try repo.saveGoal(type, target: target, day: DateCodec.dayKey(day))
        }
    }

    func clearHistory() { perform { try autoClose(); try repo.clearHistory() } }

    private func syncNotifications() {
        var notices: [ScheduledNotice] = []
        if settings.notifications {
            if let s = session, s.isRunning, let deadline = s.deadline {
                notices.append(ScheduledNotice(id: NotificationID.sessionEnd, title: "¡Sesión completada!",
                    body: "Tómate un descanso de \(settings.breakMinutes) minutos.", deadline: deadline))
                let elapsed = s.effectiveSeconds + s.segmentSeconds(at: now)
                let untilBreak = settings.workMinutes * 60 - elapsed
                if settings.reminders && untilBreak > 0 && untilBreak < s.remainingSeconds(at: now) {
                    notices.append(ScheduledNotice(id: NotificationID.breakReminder, title: "Hora de descansar",
                        body: "Llevas \(settings.workMinutes) minutos concentrado. Puedes pausar tu sesión.",
                        deadline: now.addingTimeInterval(TimeInterval(untilBreak))))
                }
            }
            if let b = activeBreak {
                notices.append(ScheduledNotice(id: NotificationID.breakEnd, title: "Fin del descanso",
                    body: "Es hora de volver a concentrarte.", deadline: b.deadline))
            }
        }
        notifier.replace(with: notices)
    }

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        now = Date()
        var success = true
        do { try work() } catch { errorMessage = error.localizedDescription; success = false }
        do { try load() } catch { errorMessage = error.localizedDescription; success = false }
        syncNotifications()
        return success
    }

    private func load() throws {
        settings = try repo.settings()
        session = try repo.activeSession()
        activeBreak = try repo.activeBreak()
        let day = DateCodec.dayKey(now)
        todayGoal = try repo.goals(on: day).first
        today = try repo.dayStat(on: day)
        weekly = try makeWeekly()
    }

    private func makeWeekly() throws -> [DailyBar] {
        let cal = Calendar.current
        let dates = (0..<7).reversed().compactMap { cal.date(byAdding: .day, value: -$0, to: now) }
        let keys = dates.map(DateCodec.dayKey)
        let minutes = try repo.focusMinutesByDay(keys)
        return zip(dates, keys).map { date, key in
            DailyBar(id: key, label: date.formatted(.dateTime.weekday(.abbreviated).day()), minutes: minutes[key] ?? 0)
        }
    }
}

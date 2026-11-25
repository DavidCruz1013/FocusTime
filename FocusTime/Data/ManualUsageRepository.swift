import Foundation

/// Nombres definidos por la persona; no son identificadores de apps instaladas.
struct ManualTrackedApp: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
}

/// Un intervalo iniciado y detenido por la persona, nunca detectado por iOS.
struct ManualUsageRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let appID: UUID
    let nameSnapshot: String
    let startedAt: Date
    var endedAt: Date?

    func elapsed(at now: Date) -> Int {
        Self.wholeSeconds((endedAt ?? now).timeIntervalSince(startedAt))
    }

    fileprivate static func wholeSeconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite, interval > 0 else { return 0 }
        if interval >= Double(Int.max) { return Int.max }
        return Int(interval)
    }
}

struct ManualUsageSnapshot: Codable, Equatable {
    var apps: [ManualTrackedApp] = []
    var records: [ManualUsageRecord] = []
    static let empty = ManualUsageSnapshot()

    var active: ManualUsageRecord? { records.first { $0.endedAt == nil } }

    /// Intersección con el día consultado, también para intervalos que cruzan
    /// medianoche. Un registro activo incluye el tiempo hasta `now`.
    func seconds(on day: Date, appID: UUID? = nil, at now: Date = Date(),
                 calendar: Calendar = .current) -> Int {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return 0 }
        let total = records.reduce(TimeInterval.zero) { sum, record in
            guard appID == nil || record.appID == appID else { return sum }
            let start = max(interval.start, record.startedAt)
            let end = min(interval.end, record.endedAt ?? now)
            return sum + max(0, end.timeIntervalSince(start))
        }
        return ManualUsageRecord.wholeSeconds(total)
    }
}

/// Archivo local privado, independiente de App Groups y de Family Controls.
/// La interfaz usa una sola instancia en el actor principal. Se escribe antes
/// de cambiar el estado en memoria para que un fallo no aparente un guardado.
final class ManualUsageRepository {
    private let url: URL
    private var value: ManualUsageSnapshot

    init(url: URL) throws {
        guard url.isFileURL else {
            throw AppError.validation("El registro manual necesita un archivo local.")
        }
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            value = try decoder.decode(ManualUsageSnapshot.self, from: Data(contentsOf: url))
            try Self.validate(value)
        } else {
            value = .empty
        }
    }

    static func open() throws -> ManualUsageRepository {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return try ManualUsageRepository(url: directory.appendingPathComponent("manual-usage.json"))
    }

    func snapshot() -> ManualUsageSnapshot { value }

    func addApp(name: String) throws {
        let trimmed = try validatedName(name)
        var next = value
        next.apps.append(ManualTrackedApp(id: UUID(), name: trimmed))
        try commit(next)
    }

    func renameApp(id: UUID, name: String) throws {
        guard let index = value.apps.firstIndex(where: { $0.id == id }) else {
            throw AppError.business("La aplicación ya no está en tu lista.")
        }
        let trimmed = try validatedName(name, excluding: id)
        var next = value
        next.apps[index].name = trimmed
        // Los registros conservan el nombre que tenían al iniciarse.
        try commit(next)
    }

    func deleteApp(id: UUID) throws {
        guard value.apps.contains(where: { $0.id == id }) else {
            throw AppError.business("La aplicación ya no está en tu lista.")
        }
        guard value.active?.appID != id else {
            throw AppError.business("Detén el registro manual antes de eliminar esta aplicación.")
        }
        var next = value
        next.apps.removeAll { $0.id == id }
        // El historial conserva el nombre y el intervalo, aunque se quite la app.
        try commit(next)
    }

    func start(appID: UUID, at now: Date) throws {
        guard now.timeIntervalSince1970.isFinite else {
            throw AppError.validation("La fecha de inicio no es válida.")
        }
        guard value.active == nil else {
            throw AppError.business("Detén el registro actual antes de iniciar otro.")
        }
        guard let application = value.apps.first(where: { $0.id == appID }) else {
            throw AppError.business("Elige una aplicación de tu lista.")
        }
        var next = value
        next.records.append(ManualUsageRecord(id: UUID(), appID: appID,
            nameSnapshot: application.name, startedAt: now, endedAt: nil))
        try commit(next)
    }

    func stop(at now: Date) throws {
        guard now.timeIntervalSince1970.isFinite else {
            throw AppError.validation("La fecha de finalización no es válida.")
        }
        guard let index = value.records.firstIndex(where: { $0.endedAt == nil }) else {
            throw AppError.business("No hay un registro manual en curso.")
        }
        var next = value
        // Cambiar el reloj hacia atrás nunca genera una duración negativa.
        next.records[index].endedAt = max(now, next.records[index].startedAt)
        try commit(next)
    }

    func clearHistory() throws {
        var next = value
        next.records.removeAll { $0.endedAt != nil }
        try commit(next)
    }

    private func validatedName(_ name: String, excluding id: UUID? = nil) throws -> String {
        let trimmed = try Self.cleanedName(name)
        guard !value.apps.contains(where: { $0.id != id && Self.nameKey($0.name) == Self.nameKey(trimmed) }) else {
            throw AppError.validation("Ya agregaste una aplicación con ese nombre.")
        }
        return trimmed
    }

    private static func cleanedName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw AppError.validation("Escribe un nombre de 1 a 60 caracteres, sin saltos de línea.")
        }
        return trimmed
    }

    private static func nameKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive],
                     locale: Locale(identifier: "es"))
    }

    private static func validate(_ snapshot: ManualUsageSnapshot) throws {
        guard Set(snapshot.apps.map(\.id)).count == snapshot.apps.count,
              Set(snapshot.records.map(\.id)).count == snapshot.records.count,
              snapshot.records.filter({ $0.endedAt == nil }).count <= 1 else {
            throw AppError.validation("El archivo de registro manual contiene datos incompatibles.")
        }
        var names = Set<String>()
        for app in snapshot.apps {
            let name = try cleanedName(app.name)
            guard name == app.name, names.insert(nameKey(name)).inserted else {
                throw AppError.validation("El archivo de registro manual contiene nombres duplicados.")
            }
        }
        for record in snapshot.records {
            _ = try cleanedName(record.nameSnapshot)
            guard record.startedAt.timeIntervalSince1970.isFinite,
                  record.endedAt.map({ $0.timeIntervalSince1970.isFinite && $0 >= record.startedAt }) ?? true,
                  record.endedAt != nil || snapshot.apps.contains(where: { $0.id == record.appID }) else {
                throw AppError.validation("El archivo de registro manual contiene un intervalo incompatible.")
            }
        }
    }

    private func commit(_ next: ManualUsageSnapshot) throws {
        try Self.validate(next)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try encoder.encode(next).write(to: url, options: options)
        value = next
    }
}

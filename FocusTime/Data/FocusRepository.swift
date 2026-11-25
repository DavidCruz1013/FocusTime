//
//  FocusRepository.swift
//  FocusTime
//
//  Created by hamilton jafet vasquez chiquillo on 19/10/26.
//


import Foundation

final class FocusRepository {
    private let db: Database
    private init(db: Database) { self.db = db }

    /// El perfil es local y único (id_perfil = 1).
    static func open() throws -> FocusRepository {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: nil, create: true)
        return try open(path: dir.appendingPathComponent("focustime.sqlite").path)
    }

    /// Permite probar la persistencia con una base temporal o en memoria.
    static func open(path: String) throws -> FocusRepository {
        let repo = FocusRepository(db: try Database(path: path))
        try repo.db.transaction {
            for sql in Schema.statements { try repo.db.run(sql) }
            try repo.db.run("INSERT OR IGNORE INTO perfil (id_perfil, fecha_creacion) VALUES (1, ?)",
                            [.text(DateCodec.string(Date()))])
            try repo.db.run("""
                INSERT OR IGNORE INTO configuracion
                (id_perfil, concentracion_min, intervalo_trabajo_min, descanso_min,
                 notificaciones, recordatorios, limites_habilitados)
                VALUES (1, 25, 50, 10, 0, 1, 0)
                """)
            // No se pueden reconstruir los tramos pausados de versiones anteriores.
            // Conservamos sus segundos acumulados en la fecha que ya tenían guardada.
            try repo.db.run("""
                INSERT INTO concentracion_diaria (id_sesion, fecha, segundos)
                SELECT id_sesion, fecha_local, tiempo_efectivo_seg
                FROM sesion_concentracion s
                WHERE tiempo_efectivo_seg > 0 AND NOT EXISTS (
                    SELECT 1 FROM concentracion_diaria d WHERE d.id_sesion = s.id_sesion)
                """)
            // Versiones previas permitían un descanso simultáneo o varios abiertos.
            let breaks = try repo.db.rows("""
                SELECT id_descanso, inicio, duracion_objetivo_seg
                FROM descanso WHERE estado = 'activo' ORDER BY id_descanso DESC
                """).compactMap(BreakRecord.init(row:))
            let hasSession = try repo.activeSession() != nil
            for (index, record) in breaks.enumerated() where hasSession || index > 0 {
                try repo.closeBreak(record, at: Date(), allowCompletion: false)
            }
            try repo.db.run("""
                CREATE UNIQUE INDEX IF NOT EXISTS un_descanso_abierto
                ON descanso(id_perfil) WHERE estado = 'activo'
                """)
        }
        return repo
    }

    // MARK: - Configuración

    func settings() throws -> Settings {
        guard let r = try db.rows("""
            SELECT concentracion_min, intervalo_trabajo_min, descanso_min,
                   notificaciones, recordatorios, limites_habilitados
            FROM configuracion WHERE id_perfil = 1
            """).first else { return Settings() }
        return Settings(sessionMinutes: r.int(0), workMinutes: r.int(1), breakMinutes: r.int(2),
                        notifications: r.int(3) == 1, reminders: r.int(4) == 1,
                        limitsEnabled: r.int(5) == 1)
    }

    func saveSettings(_ s: Settings) throws {
        try require((1...180).contains(s.sessionMinutes), "La duración de concentración debe estar entre 1 y 180 minutos.")
        try require((1...180).contains(s.workMinutes), "El intervalo de trabajo debe estar entre 1 y 180 minutos.")
        try require((1...60).contains(s.breakMinutes), "El descanso debe estar entre 1 y 60 minutos.")
        try db.run("""
            UPDATE configuracion SET concentracion_min = ?, intervalo_trabajo_min = ?,
            descanso_min = ?, notificaciones = ?, recordatorios = ?, limites_habilitados = ?
            WHERE id_perfil = 1
            """, [.int(s.sessionMinutes), .int(s.workMinutes), .int(s.breakMinutes),
                  .int(s.notifications ? 1 : 0), .int(s.reminders ? 1 : 0),
                  .int(s.limitsEnabled ? 1 : 0)])
    }

    // MARK: - Sesiones de concentración

    func activeSession() throws -> FocusSession? {
        try db.rows("""
            SELECT id_sesion, fecha_local, duracion_objetivo_seg, tiempo_efectivo_seg,
                   ultimo_inicio_tramo, estado
            FROM sesion_concentracion WHERE estado IN ('activa','pausada') LIMIT 1
            """).first.flatMap(FocusSession.init(row:))
    }

    func startSession(seconds: Int, at now: Date) throws {
        try require((60...10_800).contains(seconds), "La duración debe estar entre 1 y 180 minutos.")
        try db.transaction {
            guard try activeSession() == nil else { throw AppError.business("Ya tienes una sesión en curso.") }
            guard try activeBreak() == nil else { throw AppError.business("Finaliza el descanso antes de iniciar una sesión.") }
            try db.run("""
                INSERT INTO sesion_concentracion
                (id_perfil, inicio, fecha_local, duracion_objetivo_seg, tiempo_efectivo_seg,
                 ultimo_inicio_tramo, estado)
                VALUES (1, ?, ?, ?, 0, ?, 'activa')
                """, [.text(DateCodec.string(now)), .text(DateCodec.dayKey(now)),
                      .int(seconds), .text(DateCodec.string(now))])
        }
    }

    func pause(_ s: FocusSession, at now: Date) throws {
        guard let current = try activeSession(), current.id == s.id, current.isRunning else { return }
        if current.remainingSeconds(at: now) == 0 {
            try finish(current, at: now, completed: true)
            return
        }
        try db.transaction {
            try recordSegment(current, until: now)
            try db.run("""
                UPDATE sesion_concentracion
                SET tiempo_efectivo_seg = MIN(duracion_objetivo_seg, tiempo_efectivo_seg + ?),
                    ultimo_inicio_tramo = NULL, estado = 'pausada'
                WHERE id_sesion = ? AND estado = 'activa'
                """, [.int(current.segmentSeconds(at: now)), .int(current.id)])
        }
    }

    func resume(_ s: FocusSession, at now: Date) throws {
        guard let current = try activeSession(), current.id == s.id, !current.isRunning else { return }
        guard try activeBreak() == nil else { throw AppError.business("Finaliza el descanso antes de reanudar.") }
        try db.run("""
            UPDATE sesion_concentracion SET ultimo_inicio_tramo = ?, estado = 'activa'
            WHERE id_sesion = ? AND estado = 'pausada'
            """, [.text(DateCodec.string(now)), .int(current.id)])
    }

    func finish(_ s: FocusSession, at now: Date, completed: Bool) throws {
        guard let current = try activeSession(), current.id == s.id else { return }
        let reachedTarget = current.remainingSeconds(at: now) == 0
        guard !completed || reachedTarget else {
            throw AppError.business("La sesión todavía no ha completado su duración. Puedes cancelarla.")
        }
        // Al regresar horas después, registrar la hora real en que venció el temporizador.
        let finishedAt = reachedTarget ? (current.deadline ?? now) : now
        try db.transaction {
            try recordSegment(current, until: finishedAt)
            try db.run("""
                UPDATE sesion_concentracion
                SET tiempo_efectivo_seg = MIN(duracion_objetivo_seg, tiempo_efectivo_seg + ?),
                    ultimo_inicio_tramo = NULL, fin = ?, fecha_local = ?, estado = ?
                WHERE id_sesion = ? AND estado IN ('activa','pausada')
                """, [.int(current.segmentSeconds(at: finishedAt)), .text(DateCodec.string(finishedAt)),
                      .text(DateCodec.dayKey(finishedAt)), .text(reachedTarget ? "completada" : "cancelada"), .int(current.id)])
        }
    }

    /// Guarda cada tramo efectivo por día local; las pausas nunca suman minutos.
    private func recordSegment(_ session: FocusSession, until end: Date) throws {
        guard session.isRunning, let start = session.segmentStart else { return }
        let seconds = min(max(0, session.targetSeconds - session.effectiveSeconds), session.segmentSeconds(at: end))
        var remaining = seconds
        var cursor = start
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        while remaining > 0 {
            guard let dayEnd = calendar.dateInterval(of: .day, for: cursor)?.end else {
                throw AppError.validation("No se pudo calcular el día de concentración.")
            }
            let portion = min(remaining, max(1, Int(ceil(dayEnd.timeIntervalSince(cursor)))))
            try db.run("""
                INSERT INTO concentracion_diaria (id_sesion, fecha, segundos) VALUES (?, ?, ?)
                ON CONFLICT(id_sesion, fecha) DO UPDATE SET segundos = segundos + excluded.segundos
                """, [.int(session.id), .text(DateCodec.dayKey(cursor)), .int(portion)])
            remaining -= portion
            cursor = dayEnd
        }
    }

    // MARK: - Descansos

    func activeBreak() throws -> BreakRecord? {
        try db.rows("""
            SELECT id_descanso, inicio, duracion_objetivo_seg
            FROM descanso WHERE estado = 'activo' LIMIT 1
            """).first.flatMap(BreakRecord.init(row:))
    }

    func startBreak(seconds: Int, at now: Date) throws {
        try require((60...3600).contains(seconds), "El descanso debe estar entre 1 y 60 minutos.")
        try db.transaction {
            guard try activeSession() == nil else { throw AppError.business("Finaliza la sesión antes de iniciar un descanso.") }
            guard try activeBreak() == nil else { throw AppError.business("Ya tienes un descanso en curso.") }
            try db.run("""
                INSERT INTO descanso (id_perfil, id_sesion, inicio, fecha_local,
                                      duracion_objetivo_seg, tiempo_efectivo_seg, estado)
                VALUES (1, (SELECT id_sesion FROM sesion_concentracion
                            WHERE estado = 'completada' ORDER BY fin DESC LIMIT 1), ?, ?, ?, 0, 'activo')
                """, [.text(DateCodec.string(now)), .text(DateCodec.dayKey(now)), .int(seconds)])
        }
    }

    func finishBreak(_ b: BreakRecord, at now: Date, completed: Bool) throws {
        guard let current = try activeBreak(), current.id == b.id else { return }
        guard !completed || current.remaining(at: now) == 0 else {
            throw AppError.business("El descanso todavía no ha completado su duración.")
        }
        try closeBreak(current, at: now)
    }

    private func closeBreak(_ b: BreakRecord, at now: Date, allowCompletion: Bool = true) throws {
        let reachedTarget = allowCompletion && b.remaining(at: now) == 0
        let finishedAt = reachedTarget ? b.deadline : now
        try db.run("""
            UPDATE descanso SET fin = ?, fecha_local = ?, tiempo_efectivo_seg = ?, estado = ?
            WHERE id_descanso = ? AND estado = 'activo'
            """, [.text(DateCodec.string(finishedAt)), .text(DateCodec.dayKey(finishedAt)), .int(b.elapsed(at: finishedAt)),
                  .text(reachedTarget ? "completado" : "cancelado"), .int(b.id)])
    }

    // MARK: - Metas

    func goals(on day: String) throws -> [GoalItem] {
        try db.rows("SELECT tipo, objetivo FROM meta_diaria WHERE id_perfil = 1 AND fecha = ? ORDER BY id_meta",
                    [.text(day)]).compactMap { r in
            guard let type = GoalType(rawValue: r.string(0) ?? "") else { return nil }
            return GoalItem(type: type, target: r.int(1), achieved: try achieved(type, on: day))
        }
    }

    /// Una meta por tipo y fecha (UNIQUE en la tabla): si existe, actualiza el objetivo.
    func saveGoal(_ type: GoalType, target: Int, day: String) throws {
        try require((1...10_000).contains(target), "La meta debe estar entre 1 y 10000.")
        try db.run("""
            INSERT INTO meta_diaria (id_perfil, fecha, tipo, objetivo, fecha_creacion)
            VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(id_perfil, fecha, tipo) DO UPDATE SET objetivo = excluded.objetivo
            """, [.text(day), .text(type.rawValue), .int(target), .text(DateCodec.string(Date()))])
    }

    private func achieved(_ type: GoalType, on day: String) throws -> Int {
        switch type {
        case .sesiones:
            return try count("SELECT COUNT(*) FROM sesion_concentracion WHERE id_perfil = 1 AND fecha_local = ? AND estado = 'completada'", day)
        case .minutos_concentracion:
            return try count("SELECT COALESCE(SUM(d.segundos), 0) / 60 FROM concentracion_diaria d JOIN sesion_concentracion s ON s.id_sesion = d.id_sesion WHERE s.id_perfil = 1 AND d.fecha = ? AND s.estado IN ('completada','cancelada')", day)
        case .descansos:
            return try count("SELECT COUNT(*) FROM descanso WHERE id_perfil = 1 AND fecha_local = ? AND estado = 'completado'", day)
        }
    }

    private func count(_ sql: String, _ day: String) throws -> Int {
        try db.rows(sql, [.text(day)]).first?.int(0) ?? 0
    }

    // MARK: - Progreso

    func dayStat(on day: String) throws -> DayStat {
        DayStat(sessions: try achieved(.sesiones, on: day),
                focusMinutes: try achieved(.minutos_concentracion, on: day),
                breaks: try achieved(.descansos, on: day))
    }

    func focusMinutesByDay(_ days: [String]) throws -> [String: Int] {
        guard let first = days.min(), let last = days.max() else { return [:] }
        var result: [String: Int] = [:]
        let rows = try db.rows("""
            SELECT d.fecha, COALESCE(SUM(d.segundos), 0) / 60
            FROM concentracion_diaria d
            JOIN sesion_concentracion s ON s.id_sesion = d.id_sesion
            WHERE s.id_perfil = 1 AND d.fecha BETWEEN ? AND ?
              AND s.estado IN ('completada','cancelada')
            GROUP BY d.fecha
            """, [.text(first), .text(last)])
        for r in rows { result[r.string(0) ?? ""] = r.int(1) }
        return result
    }

    // MARK: - Límites de aplicaciones

    func limits() throws -> [AppLimit] {
        try db.rows("""
            SELECT o.id_objetivo, o.nombre_visible, l.limite_diario_min, l.habilitado
            FROM limite_aplicacion l
            JOIN objetivo_control o ON o.id_objetivo = l.id_objetivo
            WHERE o.id_perfil = 1 ORDER BY o.nombre_visible
            """).map { r in
            AppLimit(id: r.int(0), name: r.string(1) ?? "Sin nombre",
                     minutes: r.int(2), enabled: r.int(3) == 1)
        }
    }

    func saveLimit(objectiveId: Int?, name: String, minutes: Int, enabled: Bool) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try require(!name.isEmpty, "Escribe el nombre de la aplicación.")
        try require((1...1440).contains(minutes), "El límite debe estar entre 1 y 1440 minutos.")
        try db.transaction {
            let objective: Int
            if let id = objectiveId {
                try db.run("UPDATE objetivo_control SET nombre_visible = ? WHERE id_objetivo = ?",
                           [.text(name), .int(id)])
                objective = id
            } else {
                try db.run("INSERT INTO objetivo_control (id_perfil, tipo, nombre_visible) VALUES (1, 'aplicacion', ?)",
                           [.text(name)])
                objective = db.lastId()
            }
            try db.run("""
                INSERT INTO limite_aplicacion (id_objetivo, limite_diario_min, habilitado)
                VALUES (?, ?, ?)
                ON CONFLICT(id_objetivo) DO UPDATE SET
                    limite_diario_min = excluded.limite_diario_min,
                    habilitado = excluded.habilitado
                """, [.int(objective), .int(minutes), .int(enabled ? 1 : 0)])
        }
    }

    /// Al borrar el objetivo se borra su límite (ON DELETE CASCADE).
    func deleteLimit(objectiveId: Int) throws {
        try db.run("DELETE FROM objetivo_control WHERE id_objetivo = ?", [.int(objectiveId)])
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw AppError.validation(message) }
    }

    // MARK: - Historial

    func clearHistory() throws {
        try db.transaction {
            try db.run("DELETE FROM sesion_concentracion WHERE estado IN ('completada','cancelada')")
            try db.run("DELETE FROM descanso WHERE estado IN ('completado','cancelado')")
        }
    }
}

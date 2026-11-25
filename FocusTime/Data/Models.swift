//
//  Models.swift
//  FocusTime
//
//  Created by hamilton jafet vasquez chiquillo on 19/10/26.
//

import Foundation

enum SessionState: String { case activa, pausada, completada, cancelada }

enum GoalType: String, CaseIterable, Identifiable {
    case sesiones, minutos_concentracion, descansos
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sesiones: return "Sesiones completadas"
        case .minutos_concentracion: return "Minutos de concentración"
        case .descansos: return "Descansos completados"
        }
    }
}

struct Settings {
    var sessionMinutes = 25
    var workMinutes = 50
    var breakMinutes = 10
    var notifications = false
    var reminders = true
    var limitsEnabled = false
}

struct FocusSession: Identifiable {
    let id: Int
    let targetSeconds: Int
    let effectiveSeconds: Int   // tiempo acumulado sin el tramo en curso
    let segmentStart: Date?     // inicio del tramo en curso (nil si está pausada)
    let state: SessionState

    var isRunning: Bool { state == .activa }

    /// Instante de finalización del tramo activo, incluso si iOS suspende la app.
    var deadline: Date? {
        guard isRunning, let segmentStart else { return nil }
        return segmentStart.addingTimeInterval(TimeInterval(max(0, targetSeconds - effectiveSeconds)))
    }

    func segmentSeconds(at now: Date) -> Int {
        guard isRunning, let start = segmentStart else { return 0 }
        return max(0, Int(now.timeIntervalSince(start)))
    }

    func remainingSeconds(at now: Date) -> Int {
        max(0, targetSeconds - effectiveSeconds - segmentSeconds(at: now))
    }

    // SELECT id_sesion, fecha_local, duracion_objetivo_seg, tiempo_efectivo_seg, ultimo_inicio_tramo, estado
    init?(row r: Row) {
        guard let state = SessionState(rawValue: r.string(5) ?? "") else { return nil }
        self.id = r.int(0)
        self.targetSeconds = r.int(2)
        self.effectiveSeconds = r.int(3)
        self.segmentStart = DateCodec.date(r.string(4))
        self.state = state
    }
}

struct BreakRecord: Identifiable {
    let id: Int
    let startedAt: Date
    let targetSeconds: Int

    var deadline: Date { startedAt.addingTimeInterval(TimeInterval(targetSeconds)) }

    func elapsed(at now: Date) -> Int {
        min(targetSeconds, max(0, Int(now.timeIntervalSince(startedAt))))
    }

    func remaining(at now: Date) -> Int { targetSeconds - elapsed(at: now) }

    // SELECT id_descanso, inicio, duracion_objetivo_seg
    init?(row r: Row) {
        guard let start = DateCodec.date(r.string(1)) else { return nil }
        self.id = r.int(0)
        self.startedAt = start
        self.targetSeconds = r.int(2)
    }
}

struct AppLimit: Identifiable {
    let id: Int          // id_objetivo
    let name: String
    let minutes: Int
    let enabled: Bool
}

struct GoalItem: Identifiable {
    let type: GoalType
    let target: Int
    let achieved: Int
    var id: String { type.rawValue }
    var percent: Int { min(100, achieved * 100 / max(target, 1)) }
}

struct DayStat {
    let sessions: Int
    let focusMinutes: Int
    let breaks: Int
    static let empty = DayStat(sessions: 0, focusMinutes: 0, breaks: 0)
}

struct DailyBar: Identifiable {
    let id: String
    let label: String
    let minutes: Int
}

func mmss(_ seconds: Int) -> String {
    let value = max(0, seconds)
    return String(format: "%02d:%02d", value / 60, value % 60)
}

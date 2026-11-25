//
//  Database.swift
//  FocusTime
//
//  Created by hamilton jafet vasquez chiquillo on 19/10/26.
//

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum AppError: LocalizedError {
    case db(String), validation(String), business(String)

    var errorDescription: String? {
        switch self {
        case .db(let m): return "Error de base de datos: \(m)"
        case .validation(let m): return m
        case .business(let m): return m
        }
    }
}

enum SQLValue {
    case int(Int), text(String)
}

/// Copia los valores de la fila mientras el statement sigue activo,
/// para no leer memoria ya liberada por sqlite3_finalize.
struct Row {
    enum Cell {
        case null
        case int(Int)
        case text(String)
    }

    private let cells: [Cell]

    init(stmt: OpaquePointer) {
        let count = sqlite3_column_count(stmt)
        cells = (0..<count).map { i -> Cell in
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_INTEGER:
                return .int(Int(sqlite3_column_int64(stmt, i)))
            case SQLITE_FLOAT:
                return .int(Int(sqlite3_column_double(stmt, i)))
            case SQLITE_TEXT:
                if let c = sqlite3_column_text(stmt, i) {
                    return .text(String(cString: c))
                }
                return .null
            default:
                return .null
            }
        }
    }

    func int(_ i: Int32) -> Int {
        guard i >= 0, Int(i) < cells.count else { return 0 }
        switch cells[Int(i)] {
        case .int(let v): return v
        case .text(let s): return Int(s) ?? 0
        case .null: return 0
        }
    }

    func string(_ i: Int32) -> String? {
        guard i >= 0, Int(i) < cells.count else { return nil }
        switch cells[Int(i)] {
        case .text(let s): return s
        case .int(let v): return String(v)
        case .null: return nil
        }
    }
}

final class Database {
    private var handle: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open(path, &handle) == SQLITE_OK else {
            let failure = message
            sqlite3_close(handle)
            handle = nil
            throw AppError.db(failure)
        }
        sqlite3_busy_timeout(handle, 5_000)
        try run("PRAGMA foreign_keys = ON")
    }

    deinit { sqlite3_close(handle) }

    private var message: String { String(cString: sqlite3_errmsg(handle)) }

    func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw AppError.db(message) }
    }

    func rows(_ sql: String, _ params: [SQLValue] = []) throws -> [Row] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var result: [Row] = []
        var resultCode = sqlite3_step(stmt)
        while resultCode == SQLITE_ROW {
            result.append(Row(stmt: stmt))
            resultCode = sqlite3_step(stmt)
        }
        guard resultCode == SQLITE_DONE else { throw AppError.db(message) }
        return result
    }

    func lastId() -> Int { Int(sqlite3_last_insert_rowid(handle)) }

    func transaction(_ body: () throws -> Void) throws {
        try run("BEGIN IMMEDIATE")
        do {
            try body()
            try run("COMMIT")
        } catch {
            try? run("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer {
        var prepared: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
        guard result == SQLITE_OK, let stmt = prepared else {
            sqlite3_finalize(prepared)
            throw AppError.db(message)
        }
        guard sqlite3_bind_parameter_count(stmt) == Int32(params.count) else {
            sqlite3_finalize(stmt)
            throw AppError.db("La cantidad de parámetros no coincide con la consulta.")
        }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            let bound: Int32
            switch p {
            case .int(let v): bound = sqlite3_bind_int64(stmt, idx, Int64(v))
            case .text(let s): bound = sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT)
            }
            guard bound == SQLITE_OK else {
                let failure = message
                sqlite3_finalize(stmt)
                throw AppError.db(failure)
            }
        }
        return stmt
    }
}

enum DateCodec {
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let legacyISO = ISO8601DateFormatter()

    static func string(_ d: Date) -> String { iso.string(from: d) }
    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? legacyISO.date(from: s)
    }
    static func dayKey(_ d: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: d)
    }
}

enum Schema {
    static let statements: [String] = [
        """
        CREATE TABLE IF NOT EXISTS perfil (
            id_perfil INTEGER PRIMARY KEY,
            nombre TEXT,
            fecha_creacion TEXT NOT NULL)
        """,
        """
        CREATE TABLE IF NOT EXISTS configuracion (
            id_perfil INTEGER PRIMARY KEY REFERENCES perfil(id_perfil) ON DELETE CASCADE,
            concentracion_min INTEGER NOT NULL CHECK (concentracion_min BETWEEN 1 AND 180),
            intervalo_trabajo_min INTEGER NOT NULL CHECK (intervalo_trabajo_min BETWEEN 1 AND 180),
            descanso_min INTEGER NOT NULL CHECK (descanso_min BETWEEN 1 AND 60),
            notificaciones INTEGER NOT NULL CHECK (notificaciones IN (0,1)),
            recordatorios INTEGER NOT NULL CHECK (recordatorios IN (0,1)),
            limites_habilitados INTEGER NOT NULL CHECK (limites_habilitados IN (0,1)))
        """,
        """
        CREATE TABLE IF NOT EXISTS sesion_concentracion (
            id_sesion INTEGER PRIMARY KEY AUTOINCREMENT,
            id_perfil INTEGER NOT NULL REFERENCES perfil(id_perfil) ON DELETE CASCADE,
            inicio TEXT NOT NULL,
            fin TEXT,
            fecha_local TEXT NOT NULL,
            duracion_objetivo_seg INTEGER NOT NULL CHECK (duracion_objetivo_seg > 0),
            tiempo_efectivo_seg INTEGER NOT NULL DEFAULT 0 CHECK (tiempo_efectivo_seg >= 0),
            ultimo_inicio_tramo TEXT,
            estado TEXT NOT NULL CHECK (estado IN ('activa','pausada','completada','cancelada')))
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS una_sesion_abierta ON sesion_concentracion(id_perfil) WHERE estado IN ('activa','pausada')",
        """
        CREATE TABLE IF NOT EXISTS descanso (
            id_descanso INTEGER PRIMARY KEY AUTOINCREMENT,
            id_perfil INTEGER NOT NULL REFERENCES perfil(id_perfil) ON DELETE CASCADE,
            id_sesion INTEGER REFERENCES sesion_concentracion(id_sesion) ON DELETE SET NULL,
            inicio TEXT NOT NULL,
            fin TEXT,
            fecha_local TEXT NOT NULL,
            duracion_objetivo_seg INTEGER NOT NULL CHECK (duracion_objetivo_seg BETWEEN 60 AND 3600),
            tiempo_efectivo_seg INTEGER NOT NULL DEFAULT 0 CHECK (tiempo_efectivo_seg >= 0),
            estado TEXT NOT NULL CHECK (estado IN ('activo','completado','cancelado')))
        """,
        """
        CREATE TABLE IF NOT EXISTS meta_diaria (
            id_meta INTEGER PRIMARY KEY AUTOINCREMENT,
            id_perfil INTEGER NOT NULL REFERENCES perfil(id_perfil) ON DELETE CASCADE,
            fecha TEXT NOT NULL,
            tipo TEXT NOT NULL CHECK (tipo IN ('sesiones','minutos_concentracion','descansos')),
            objetivo INTEGER NOT NULL CHECK (objetivo > 0),
            fecha_creacion TEXT NOT NULL,
            UNIQUE (id_perfil, fecha, tipo))
        """,
        """
        CREATE TABLE IF NOT EXISTS objetivo_control (
            id_objetivo INTEGER PRIMARY KEY AUTOINCREMENT,
            id_perfil INTEGER NOT NULL REFERENCES perfil(id_perfil) ON DELETE CASCADE,
            tipo TEXT NOT NULL CHECK (tipo IN ('aplicacion','categoria')),
            referencia_sistema BLOB,
            nombre_visible TEXT)
        """,
        """
        CREATE TABLE IF NOT EXISTS limite_aplicacion (
            id_limite INTEGER PRIMARY KEY AUTOINCREMENT,
            id_objetivo INTEGER NOT NULL UNIQUE REFERENCES objetivo_control(id_objetivo) ON DELETE CASCADE,
            limite_diario_min INTEGER NOT NULL CHECK (limite_diario_min BETWEEN 1 AND 1440),
            habilitado INTEGER NOT NULL CHECK (habilitado IN (0,1)))
        """,
        """
        CREATE TABLE IF NOT EXISTS concentracion_diaria (
            id_sesion INTEGER NOT NULL REFERENCES sesion_concentracion(id_sesion) ON DELETE CASCADE,
            fecha TEXT NOT NULL,
            segundos INTEGER NOT NULL CHECK (segundos >= 0),
            PRIMARY KEY (id_sesion, fecha))
        """,
        "CREATE INDEX IF NOT EXISTS idx_concentracion_fecha ON concentracion_diaria(fecha)",
        "CREATE INDEX IF NOT EXISTS idx_sesion_fecha ON sesion_concentracion(id_perfil, fecha_local)",
        "CREATE INDEX IF NOT EXISTS idx_descanso_fecha ON descanso(id_perfil, fecha_local)"
    ]
}

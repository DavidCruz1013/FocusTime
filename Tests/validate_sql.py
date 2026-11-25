#!/usr/bin/env python3
"""Exercise SQL extracted from the Swift source using Python's real SQLite engine.

This complements `swift test` on macOS. It does not compile or run Swift/iOS code.
"""
from pathlib import Path
import re
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[1]
DATABASE = (ROOT / "FocusTime/Data/Database.swift").read_text()
REPOSITORY = (ROOT / "FocusTime/Data/FocusRepository.swift").read_text()
SCHEMA = DATABASE.split("enum Schema {", 1)[1]


def strings(source):
    pattern = r'"""(.*?)"""|"((?:[^"\\]|\\.)*)"'
    return [m.group(1) if m.group(1) is not None else m.group(2)
            for m in re.finditer(pattern, source, re.S)]


def normalized(value):
    return " ".join(value.split())


def query(fragment):
    matches = [sql for sql in strings(REPOSITORY) if fragment in normalized(sql)]
    if len(matches) != 1:
        raise ValueError(f"Expected one source query for {fragment!r}, got {len(matches)}")
    return matches[0]


class SQLTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys = ON")
        for statement in strings(SCHEMA):
            self.db.execute(statement)
        self.db.execute(query("INSERT OR IGNORE INTO perfil"), ("2026-10-01T12:00:00Z",))
        self.db.execute(query("INSERT OR IGNORE INTO configuracion"))

    def tearDown(self):
        self.db.close()

    def start_session(self, day="2026-10-01"):
        return self.db.execute(query("VALUES (1, ?, ?, ?, 0, ?, 'activa')"),
                               (f"{day}T12:00:00Z", day, 120, f"{day}T12:00:00Z")).lastrowid

    def test_all_repository_statements_are_valid_sqlite(self):
        queries = [sql for sql in strings(REPOSITORY)
                   if sql.lstrip().upper().startswith(("SELECT ", "INSERT ", "UPDATE ", "DELETE ", "CREATE "))]
        self.assertGreaterEqual(len(queries), 25)
        for statement in queries:
            with self.subTest(sql=normalized(statement)):
                self.db.execute("EXPLAIN " + statement, [None] * statement.count("?")).fetchall()

    def test_settings_default_notifications_disabled(self):
        settings = self.db.execute(query("SELECT concentracion_min, intervalo_trabajo_min")).fetchone()
        self.assertEqual(settings, (25, 50, 10, 0, 1, 0))

    def test_unique_open_session_constraint(self):
        self.start_session()
        with self.assertRaises(sqlite3.IntegrityError):
            self.start_session()

    def test_unique_open_break_and_actual_start_query(self):
        self.db.execute(query("CREATE UNIQUE INDEX IF NOT EXISTS un_descanso_abierto"))
        statement = query("VALUES (1, (SELECT id_sesion FROM sesion_concentracion")
        self.db.execute(statement, ("2026-10-01T12:00:00Z", "2026-10-01", 60))
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(statement, ("2026-10-01T12:01:00Z", "2026-10-01", 60))

    def test_focus_ledger_accumulates_and_queries_each_day(self):
        sid = self.start_session()
        statement = query("ON CONFLICT(id_sesion, fecha) DO UPDATE SET segundos")
        self.db.execute(statement, (sid, "2026-10-01", 30))
        self.db.execute(statement, (sid, "2026-10-01", 30))
        self.db.execute(statement, (sid, "2026-10-02", 60))
        self.db.execute(query("SET tiempo_efectivo_seg = MIN(duracion_objetivo_seg, tiempo_efectivo_seg + ?), ultimo_inicio_tramo = NULL, fin"),
                        (120, "2026-10-02T00:01:00Z", "2026-10-02", "completada", sid))
        daily = query("SELECT COALESCE(SUM(d.segundos), 0) / 60")
        self.assertEqual(self.db.execute(daily, ("2026-10-01",)).fetchone()[0], 1)
        self.assertEqual(self.db.execute(daily, ("2026-10-02",)).fetchone()[0], 1)
        weekly = query("SELECT d.fecha, COALESCE(SUM(d.segundos), 0) / 60")
        self.assertEqual(self.db.execute(weekly, ("2026-10-01", "2026-10-07")).fetchall(),
                         [("2026-10-01", 1), ("2026-10-02", 1)])

    def test_legacy_ledger_migration_is_idempotent(self):
        sid = self.start_session()
        self.db.execute("UPDATE sesion_concentracion SET tiempo_efectivo_seg = 60 WHERE id_sesion = ?", (sid,))
        migration = query("INSERT INTO concentracion_diaria (id_sesion, fecha, segundos) SELECT")
        self.db.execute(migration)
        self.db.execute(migration)
        self.assertEqual(self.db.execute("SELECT segundos FROM concentracion_diaria").fetchall(), [(60,)])

    def test_history_delete_cascades_ledger_preserves_goal_and_active_record(self):
        finished_id = self.start_session()
        self.db.execute(query("ON CONFLICT(id_sesion, fecha) DO UPDATE SET segundos"),
                        (finished_id, "2026-10-01", 120))
        self.db.execute("UPDATE sesion_concentracion SET estado = 'completada' WHERE id_sesion = ?", (finished_id,))
        active_id = self.start_session()
        self.db.execute(query("INSERT INTO meta_diaria"), ("2026-10-01", "sesiones", 2, "2026-10-01T12:00:00Z"))
        self.db.execute(query("DELETE FROM sesion_concentracion WHERE estado"))
        self.db.execute(query("DELETE FROM descanso WHERE estado"))
        self.assertEqual(self.db.execute("SELECT * FROM concentracion_diaria").fetchall(), [])
        self.assertEqual(self.db.execute("SELECT id_sesion FROM sesion_concentracion").fetchall(), [(active_id,)])
        self.assertEqual(self.db.execute("SELECT objetivo FROM meta_diaria").fetchall(), [(2,)])

    def test_foreign_keys_prevent_orphan_ledger(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.db.execute(query("ON CONFLICT(id_sesion, fecha) DO UPDATE SET segundos"), (999, "2026-10-01", 60))


if __name__ == "__main__":
    unittest.main(verbosity=2)

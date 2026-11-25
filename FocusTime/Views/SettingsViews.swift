//
//  SettingsViews.swift
//  FocusTime
//
//  Created by hamilton jafet vasquez chiquillo on 19/10/26.
//

import SwiftUI
import UIKit

// MARK: - Configuración

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var draft = Settings()
    @State private var confirmClear = false
    @State private var savedFeedback = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    sessionCard
                    breakCard
                    notificationsCard
                    goalsCard
                    saveButton
                    dangerCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Configuración")
            .onAppear { draft = store.settings }
            .confirmationDialog("Se eliminarán sesiones de concentración y descansos finalizados. Se conservan las metas, la actividad en curso y los registros manuales de apps.",
                                isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Borrar historial de concentración", role: .destructive) { store.clearHistory() }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    // MARK: - Tarjetas

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Concentración", icon: "timer", tint: Theme.primary)

            Stepper(value: $draft.sessionMinutes, in: 1...180) {
                row(title: "Duración predeterminada", value: "\(draft.sessionMinutes) min")
            }
        }
        .card()
    }

    private var breakCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Descansos", icon: "cup.and.saucer.fill", tint: .orange)

            Stepper(value: $draft.workMinutes, in: 1...180) {
                row(title: "Trabajar durante", value: "\(draft.workMinutes) min")
            }

            Stepper(value: $draft.breakMinutes, in: 1...60) {
                row(title: "Descansar durante", value: "\(draft.breakMinutes) min")
            }

            Divider()

            Toggle(isOn: $draft.reminders) {
                Label("Recordatorio de descanso", systemImage: "bell.badge")
                    .font(.subheadline)
            }
            .tint(.orange)
            .disabled(!draft.notifications)

            Text("El recordatorio avisa una vez durante la sesión si el intervalo es menor que su duración. No pausa la sesión automáticamente.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Notificaciones", icon: "bell.fill", tint: .blue)

            Toggle(isOn: $draft.notifications) {
                Label("Permitir notificaciones", systemImage: "app.badge")
                    .font(.subheadline)
            }
            .tint(.blue)

            Text("Activa la opción y guarda para autorizar los avisos de fin de sesión y descanso. Puedes usar los temporizadores sin notificaciones.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(store.settings.notifications && store.notificationsAuthorized
                 ? "Estado: avisos activados y autorizados."
                 : "Estado: avisos desactivados en FocusTime.")
                .font(.caption.bold()).foregroundStyle(.secondary)

            Link("Abrir ajustes de FocusTime", destination: URL(string: UIApplication.openSettingsURLString)!)
                .font(.subheadline)
        }
        .card()
    }

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Metas", icon: "target", tint: .purple)
            NavigationLink { GoalsView() } label: {
                linkRow(icon: "target", title: "Metas diarias")
            }
            .buttonStyle(.plain)
            Text("Agrega aplicaciones y registra sus intervalos manualmente en la pestaña Apps.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var saveButton: some View {
        Button {
            Task {
                if await store.saveSettings(draft) {
                    draft = store.settings
                    withAnimation { savedFeedback = true }
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { savedFeedback = false }
                } else if !store.notificationsAuthorized {
                    draft.notifications = false
                }
            }
        } label: {
            Label(store.savingSettings ? "Guardando…" : (savedFeedback ? "Guardado" : "Guardar cambios"),
                  systemImage: savedFeedback ? "checkmark.circle.fill" : "square.and.arrow.down")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.primaryGradient)
                )
        }
        .buttonStyle(.plain)
        .disabled(store.savingSettings)
    }

    private var dangerCard: some View {
        Button(role: .destructive) {
            confirmClear = true
        } label: {
            Label("Borrar historial de concentración", systemImage: "trash")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 14)
        .card()
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.headline)
            .foregroundStyle(tint)
    }

    private func row(title: String, value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func linkRow(icon: String, title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(.purple)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.purple.opacity(0.15)))
            Text(title).font(.subheadline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Metas diarias

struct GoalsView: View {
    @EnvironmentObject var store: AppStore
    @State private var day = Date()
    @State private var type: GoalType = .minutos_concentracion
    @State private var target = 120

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Nueva meta", systemImage: "target")
                        .font(.headline)
                        .foregroundStyle(Theme.primary)

                    DatePicker("Fecha", selection: $day, displayedComponents: .date)

                    Picker("Tipo", selection: $type) {
                        ForEach(GoalType.allCases) { Text($0.title).tag($0) }
                    }

                    Stepper("Objetivo: \(target)", value: $target, in: 1...10_000)

                    Button {
                        store.saveGoal(type, target: target, day: day)
                    } label: {
                        Text("Guardar meta")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.primaryGradient)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .card()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Progreso del día seleccionado")
                        .font(.headline)

                    let goals = store.goals(on: day)
                    if goals.isEmpty {
                        Text("Sin meta configurada")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(goals) { g in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(g.type.title): \(g.achieved) de \(g.target) (\(g.percent) %)")
                                .font(.subheadline)
                            ProgressView(value: Double(g.percent), total: 100)
                                .tint(Theme.primary)
                        }
                    }
                }
                .card()
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Metas diarias")
    }
}


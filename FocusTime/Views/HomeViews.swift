//
//  HomeViews.swift
//  FocusTime
//
//  Created by hamilton jafet vasquez chiquillo on 19/10/26.
//


import SwiftUI

// MARK: - Inicio

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showNewSession = false

    private var percent: Int { store.todayGoal?.percent ?? 0 }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Buenos días"
        case 12..<19: return "Buenas tardes"
        default: return "Buenas noches"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    goalCard
                    statRow
                    if store.session != nil {
                        NavigationLink { FocusSessionView() } label: {
                            Label("Ver sesión en curso", systemImage: "timer")
                                .font(.headline).frame(maxWidth: .infinity).padding().card()
                        }
                    } else {
                        startButton
                    }
                    if let b = store.activeBreak {
                        breakCard(b)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showNewSession) {
                NewSessionView()
            }
            .alert("¡Sesión completada!", isPresented: $store.suggestBreak) {
                Button("Iniciar descanso") { store.startBreak() }
                Button("Más tarde", role: .cancel) {}
            } message: {
                Text("Tómate \(store.settings.breakMinutes) minutos para descansar.")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(.largeTitle.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var goalCard: some View {
        VStack(spacing: 14) {
            ZStack {
                RingProgress(progress: Double(percent) / 100, lineWidth: 16)
                VStack(spacing: 2) {
                    Text(store.todayGoal == nil ? "—" : "\(percent)%")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text("de tu meta")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, height: 180)

            if let goal = store.todayGoal {
                Text("\(goal.type.title): \(goal.achieved) de \(goal.target)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Configura una meta diaria en Configuración")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .card()
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            StatTile(icon: "timer", value: "\(store.today.focusMinutes)",
                     title: "min", tint: Theme.primary)
            StatTile(icon: "checkmark.seal.fill", value: "\(store.today.sessions)",
                     title: "sesiones", tint: .blue)
            StatTile(icon: "cup.and.saucer.fill", value: "\(store.today.breaks)",
                     title: "descansos", tint: .orange)
        }
    }

    private var startButton: some View {
        Button {
            showNewSession = true
        } label: {
            Label("Iniciar concentración", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.primaryGradient)
                )
                .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(store.activeBreak != nil)
    }

    private func breakCard(_ b: BreakRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label("Descanso en curso", systemImage: "cup.and.saucer.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(mmss(b.remaining(at: store.now)))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            Spacer()
            Button("Cancelar") { store.cancelBreak() }
                .buttonStyle(.bordered)
                .tint(.orange)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.orange.opacity(0.15))
        )
    }
}

// MARK: - Nueva sesión

struct NewSessionView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selected = 25
    @State private var isCustom = false
    @State private var custom = ""
    @State private var localError: String?
    private let presets = [25, 30, 45, 60]

    private var minutes: Int? {
        isCustom ? Int(custom) : selected
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("¿Cuánto tiempo quieres concentrarte?")
                        .font(.title3.bold())

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(presets, id: \.self) { m in
                            chip(title: "\(m) min", active: !isCustom && selected == m) {
                                selected = m
                                isCustom = false
                            }
                        }
                        chip(title: "Personalizado", active: isCustom) {
                            isCustom = true
                        }
                    }

                    if isCustom {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("Minutos (1 a 180)", text: $custom)
                                .keyboardType(.numberPad)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Theme.cardBackground)
                                )
                            Text("Escribe un número entero entre 1 y 180.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Las pausas no cuentan como tiempo de concentración. Al terminar te sugeriremos un descanso.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .onAppear {
                selected = store.settings.sessionMinutes
                if !presets.contains(selected) { isCustom = true; custom = String(selected) }
            }
            .alert("No se pudo iniciar", isPresented: Binding(
                get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("Entendido", role: .cancel) {}
            } message: { Text(localError ?? "") }
            .navigationTitle("Nueva sesión")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Iniciar") { start() }
                        .disabled(minutes == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func chip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .foregroundStyle(active ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(active ? AnyShapeStyle(Theme.primaryGradient)
                                     : AnyShapeStyle(Theme.cardBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func start() {
        guard let m = minutes, (1...180).contains(m) else {
            localError = "La duración debe ser un entero entre 1 y 180 minutos."
            return
        }
        if store.startSession(minutes: m) { dismiss() }
        else {
            localError = store.errorMessage
            store.errorMessage = nil
        }
    }
}

// MARK: - Sesión activa

struct FocusSessionView: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmEnd = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.focusBackground.ignoresSafeArea()

            if let s = store.session {
                let remaining = s.remainingSeconds(at: store.now)
                let progress = 1 - Double(remaining) / Double(max(s.targetSeconds, 1))

                VStack(spacing: 28) {
                    Text(s.isRunning ? "Sesión de enfoque" : "Sesión en pausa")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 40)

                    Spacer()

                    ZStack {
                        RingProgress(progress: progress, lineWidth: 18, color: Theme.accent)
                        VStack(spacing: 6) {
                            Text(mmss(remaining))
                                .font(.system(size: 64, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("tiempo restante")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(width: 290, height: 290)

                    Text(s.isRunning ? "Mantén tu concentración" : "Reanuda cuando estés listo")
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    VStack(spacing: 14) {
                        Button {
                            if s.isRunning { store.pauseSession() } else { store.resumeSession() }
                        } label: {
                            Label(s.isRunning ? "Pausar" : "Reanudar",
                                  systemImage: s.isRunning ? "pause.fill" : "play.fill")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 18)
                                .background(Capsule().fill(Theme.accent))
                        }
                        .buttonStyle(.plain)

                        Button("Finalizar sesión") { confirmEnd = true }
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.bottom, 20)
                    }
                }
                .padding(.horizontal, 24)
                .foregroundStyle(.white)
                .confirmationDialog("La sesión se registrará como cancelada.",
                                    isPresented: $confirmEnd, titleVisibility: .visible) {
                    Button("Finalizar y cancelar", role: .destructive) {
                        store.finishSession(completed: false)
                    }
                    Button("Seguir enfocado", role: .cancel) {}
                }
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .onChange(of: store.session == nil) { _, ended in
            if ended { dismiss() }
        }
    }
}

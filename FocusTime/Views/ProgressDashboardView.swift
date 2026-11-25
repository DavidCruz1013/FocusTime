//
//  ProgressDashboardView.swift
//  FocusTime
//
//  Created by hamilton jafet vasquez chiquillo on 19/10/26.
//

import SwiftUI
import Charts

struct ProgressDashboardView: View {
    @EnvironmentObject var store: AppStore

    private var percent: Int { store.todayGoal?.percent ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    todayCard
                    weeklyCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mi progreso")
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Hoy").font(.headline)
                Text(Date().formatted(date: .long, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                ZStack {
                    RingProgress(progress: Double(percent) / 100, lineWidth: 12)
                    Text(store.todayGoal == nil ? "—" : "\(percent)%")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                }
                .frame(width: 110, height: 110)

                VStack(alignment: .leading, spacing: 4) {
                    Text(store.todayGoal?.type.title ?? "Sin meta configurada")
                        .font(.subheadline.bold())
                    if let goal = store.todayGoal {
                        Text("\(goal.achieved) de \(goal.target)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Text("Los minutos y las metas incluyen sesiones finalizadas. Las pausas no suman tiempo.")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 14) {
                InfoRow(icon: "checkmark.seal.fill", tint: .blue,
                        title: "Sesiones completadas", value: "\(store.today.sessions)")
                InfoRow(icon: "timer", tint: Theme.primary,
                        title: "Tiempo concentrado", value: "\(store.today.focusMinutes) min")
                InfoRow(icon: "cup.and.saucer.fill", tint: .orange,
                        title: "Descansos realizados", value: "\(store.today.breaks)")
            }
        }
        .card()
    }

    private var weeklyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Actividad semanal").font(.headline)

            if store.weekly.allSatisfy({ $0.minutes == 0 }) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.primary)
                    Text("Aún no hay actividad. Inicia tu primera sesión.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                let todayKey = DateCodec.dayKey(store.now)
                Chart(store.weekly) { bar in
                    BarMark(
                        x: .value("Día", bar.label),
                        y: .value("Minutos", bar.minutes)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(bar.id == todayKey ? Theme.accent : Theme.primary)
                }
                .frame(height: 220)
            }
        }
        .card()
    }
}

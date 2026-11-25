import SwiftUI
import Foundation

/// Los intervalos se registran por una acción explícita del usuario.
/// Esta pantalla no utiliza ni simula la medición de Tiempo en pantalla de iOS.
struct ApplicationAccessView: View {
    @EnvironmentObject private var usage: ManualUsageStore
    @State private var showEditor = false
    @State private var editingID: UUID?
    @State private var editingName = ""
    @State private var deleteID: UUID?
    @State private var deleteName = ""
    @State private var confirmDelete = false
    @State private var confirmClear = false

    private var completedRecords: [ManualUsageRecord] {
        usage.snapshot.records.filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    explanationCard
                    if usage.isAvailable {
                        if let active = usage.snapshot.active {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Registro en curso", systemImage: "record.circle")
                                    .font(.headline).foregroundStyle(Theme.primary)
                                Text(active.nameSnapshot)
                                    .font(.title3.bold())
                                Text(manualDuration(active.elapsed(at: usage.now)))
                                    .font(.system(.largeTitle, design: .rounded).bold())
                                    .monospacedDigit()
                                    .accessibilityLabel("Tiempo registrado: \(manualDuration(active.elapsed(at: usage.now)))")
                                Text("Desde \(active.startedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button {
                                    _ = usage.stop()
                                } label: {
                                    Label("Detener registro", systemImage: "stop.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.primary)
                                Text("Detén el registro cuando dejes de usar esta app. El contador también incluye el tiempo con la pantalla apagada.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            .card()
                        }
                        todayCard
                        applicationsCard
                        historyCard
                    } else {
                        unavailableCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Registro manual")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingID = nil
                        editingName = ""
                        showEditor = true
                    } label: {
                        Label("Agregar aplicación", systemImage: "plus")
                    }
                    .disabled(!usage.isAvailable)
                }
            }
            .sheet(isPresented: $showEditor) {
                ManualAppEditor(appID: editingID, initialName: editingName)
            }
            .confirmationDialog("¿Eliminar \(deleteName) de tu lista?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Eliminar aplicación", role: .destructive) {
                    if let deleteID { _ = usage.deleteApp(id: deleteID) }
                    deleteID = nil
                }
                Button("Cancelar", role: .cancel) { deleteID = nil }
            } message: {
                Text("Los registros anteriores de esta aplicación se conservan.")
            }
            .confirmationDialog("¿Borrar el historial manual?", isPresented: $confirmClear,
                                titleVisibility: .visible) {
                Button("Borrar registros finalizados", role: .destructive) { _ = usage.clearHistory() }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se conservarán tu lista de aplicaciones y el registro que esté en curso. El historial de concentración no cambia.")
            }
            .alert("Registro manual", isPresented: Binding(
                get: { usage.errorMessage != nil },
                set: { if !$0 { usage.errorMessage = nil } }
            )) {
                Button("Entendido", role: .cancel) { usage.errorMessage = nil }
            } message: {
                Text(usage.errorMessage ?? "")
            }
        }
    }

    private var explanationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tú controlas el registro", systemImage: "hand.tap")
                .font(.headline).foregroundStyle(Theme.primary)
            Text("Agrega una app por nombre, inicia el contador antes de usarla y vuelve aquí para detenerlo.")
                .font(.subheadline)
            Text("Este registro mide el intervalo que tú indicas. No detecta qué aplicación está abierta ni obtiene datos de uso de iOS.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .card()
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tiempo registrado hoy", systemImage: "clock")
                .font(.headline)
            Text(manualDuration(usage.snapshot.seconds(on: usage.now, at: usage.now)))
                .font(.system(.title, design: .rounded).bold()).monospacedDigit()
            Text("Incluye el registro en curso. Es independiente de tus sesiones de concentración.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var applicationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mis aplicaciones").font(.headline)
            if usage.snapshot.apps.isEmpty {
                Text("Toca + para agregar la primera aplicación por nombre.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(usage.snapshot.apps) { app in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Label(app.name, systemImage: "app")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Menu {
                            Button("Cambiar nombre", systemImage: "pencil") {
                                editingID = app.id
                                editingName = app.name
                                showEditor = true
                            }
                            Button("Eliminar", systemImage: "trash", role: .destructive) {
                                deleteID = app.id
                                deleteName = app.name
                                confirmDelete = true
                            }
                        } label: {
                            Label("Opciones de \(app.name)", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                        .disabled(usage.snapshot.active?.appID == app.id)
                    }
                    Text("Hoy: \(manualDuration(usage.snapshot.seconds(on: usage.now, appID: app.id, at: usage.now)))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    if usage.snapshot.active?.appID == app.id {
                        Label("Registrando", systemImage: "record.circle")
                            .font(.subheadline).foregroundStyle(Theme.primary)
                    } else {
                        Button {
                            _ = usage.start(appID: app.id)
                        } label: {
                            Label("Iniciar registro", systemImage: "play.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.primary)
                        .disabled(usage.snapshot.active != nil)
                    }
                    if app.id != usage.snapshot.apps.last?.id { Divider() }
                }
            }
            if usage.snapshot.active != nil && usage.snapshot.apps.count > 1 {
                Text("Detén el registro en curso para seleccionar otra aplicación.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Historial manual").font(.headline)
            if completedRecords.isEmpty {
                Text("Los registros aparecerán aquí cuando detengas el contador.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(completedRecords.prefix(50))) { record in
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.nameSnapshot).font(.subheadline.bold())
                    Text(manualDuration(record.elapsed(at: usage.now)))
                        .font(.subheadline).monospacedDigit()
                    Text("Inicio: \(record.startedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                    if let end = record.endedAt {
                        Text("Fin: \(end.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
            if completedRecords.count > 50 {
                Text("Se muestran los 50 registros más recientes. Los anteriores siguen guardados y se incluyen en los totales.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !completedRecords.isEmpty {
                Button("Borrar historial manual", role: .destructive) { confirmClear = true }
                    .font(.subheadline)
            }
        }
        .card()
    }

    private var unavailableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("No se pudo abrir el registro", systemImage: "externaldrive.badge.exclamationmark")
                .font(.headline)
            Text("Tus sesiones de concentración siguen disponibles. Reintenta abrir el registro manual.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Reintentar") { usage.reload() }
                .buttonStyle(.borderedProminent).tint(Theme.primary)
        }
        .card()
    }
}

private struct ManualAppEditor: View {
    let appID: UUID?
    let initialName: String
    @EnvironmentObject private var usage: ManualUsageStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var localError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre de la aplicación") {
                    TextField("Por ejemplo, Instagram", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Text("Es un nombre para tu registro manual. No selecciona una aplicación instalada ni activa un monitoreo automático.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(appID == nil ? "Agregar aplicación" : "Cambiar nombre")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { name = initialName }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        let success: Bool
                        if let appID { success = usage.renameApp(id: appID, name: name) }
                        else { success = usage.addApp(name: name) }
                        if success { dismiss() }
                        else {
                            localError = usage.errorMessage ?? "No se pudo guardar la aplicación."
                            usage.errorMessage = nil
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("No se pudo guardar", isPresented: Binding(
                get: { localError != nil }, set: { if !$0 { localError = nil } }
            )) {
                Button("Entendido", role: .cancel) {}
            } message: { Text(localError ?? "") }
        }
        .presentationDetents([.medium, .large])
    }
}

private func manualDuration(_ seconds: Int) -> String {
    let value = max(0, seconds)
    return String(format: "%02d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
}

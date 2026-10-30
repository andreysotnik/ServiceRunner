import SwiftUI

struct MainWindow: View {
    @EnvironmentObject private var store: ServiceStore
    @State private var editing: ServiceConfig?
    @State private var isAdding = false

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                ForEach(store.services) { service in
                    ServiceRow(service: service)
                        .tag(service.id)
                        .contextMenu { contextMenu(for: service) }
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .overlay {
                if store.services.isEmpty {
                    ContentUnavailableView {
                        Label("Нет сервисов", systemImage: "shippingbox")
                    } actions: {
                        Button("Добавить сервис") { isAdding = true }
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { isAdding = true } label: { Label("Добавить", systemImage: "plus") }
                        .help("Добавить сервис")
                }
            }
        } detail: {
            if let service = store.service(id: store.selection) {
                ServiceDetailView(service: service, onEdit: { editing = service.config })
                    .id(service.id)
            } else {
                Text("Выберите сервис").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isAdding) {
            ServiceEditorView(config: ServiceConfig(name: "", command: ""), isNew: true) { config in
                store.add(config)
            }
        }
        .sheet(item: $editing) { config in
            ServiceEditorView(config: config, isNew: false) { config in
                store.update(config)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for service: ServiceController) -> some View {
        if service.state.isActive {
            Button("Остановить") { service.stop() }
            Button("Перезапустить") { service.restart() }
        } else {
            Button("Запустить") { service.start() }
        }
        Divider()
        Button("Редактировать…") { editing = service.config }
        Button("Удалить", role: .destructive) { store.remove(id: service.id) }
    }
}

struct StatusDot: View {
    let state: ServiceState

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: 9, height: 9)
    }
}

struct ServiceRow: View {
    @ObservedObject var service: ServiceController

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: service.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.config.name).fontWeight(.medium)
                Text(service.state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                service.state.isActive ? service.stop() : service.start()
            } label: {
                Image(systemName: service.state.isActive ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .help(service.state.isActive ? "Остановить" : "Запустить")
        }
        .padding(.vertical, 3)
    }
}

import AppKit
import SwiftUI

/// Always rendered in the menu bar, so it also handles requests to open the main window.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: ServiceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let _ = store.stateRevision
        let running = store.runningCount
        HStack(spacing: 2) {
            Image(systemName: store.hasProblems ? "exclamationmark.triangle.fill" : "server.rack")
            if running > 0 {
                Text("\(running)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMainWindow)) { _ in
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: ServiceStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.services.isEmpty {
                Text("Нет сервисов")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(store.services) { service in
                    MenuBarServiceRow(service: service) { open(service.id) }
                }
                .padding(.vertical, 4)
            }
            Divider()
            HStack {
                Button("Открыть окно") { open(nil) }
                Spacer()
                Button("Остановить все") { store.stopAll {} }
                    .disabled(store.runningCount == 0)
                Button("Выход") { NSApp.terminate(nil) }
            }
            .padding(10)
        }
        .frame(width: 320)
    }

    private func open(_ id: UUID?) {
        if let id { store.selection = id }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarServiceRow: View {
    @ObservedObject var service: ServiceController
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(state: service.state)
            VStack(alignment: .leading, spacing: 1) {
                Text(service.config.name)
                Text(service.state.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpen) { Image(systemName: "text.alignleft") }
                .help("Логи")
            Button {
                service.state.isActive ? service.stop() : service.start()
            } label: {
                Image(systemName: service.state.isActive ? "stop.fill" : "play.fill")
            }
            .help(service.state.isActive ? "Остановить" : "Запустить")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

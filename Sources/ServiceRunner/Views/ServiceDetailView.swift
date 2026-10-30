import AppKit
import SwiftUI

struct ServiceDetailView: View {
    @ObservedObject var service: ServiceController
    let onEdit: () -> Void
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(16)
            Divider()
            logToolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Divider()
            LogView(lines: service.logs.lines, revision: service.logRevision, filter: filter)
        }
        .navigationTitle(service.config.name)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(state: service.state)
                    Text(service.state.title).font(.headline)
                    statusDetails
                        .foregroundStyle(.secondary)
                }
                Text(service.config.command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                if !service.config.workingDirectory.isEmpty {
                    Label(service.config.workingDirectory, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    if service.config.autoStart {
                        Label("Автозапуск", systemImage: "power").font(.caption)
                    }
                    if service.config.autoRestart {
                        Label("Автоперезапуск", systemImage: "arrow.clockwise").font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
            controls
        }
    }

    @ViewBuilder
    private var statusDetails: some View {
        switch service.state {
        case .running(let pid, let since):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("PID \(pid) · \(formatDuration(context.date.timeIntervalSince(since)))")
            }
        case .restarting(let at, _):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("через \(max(0, Int(at.timeIntervalSince(context.date).rounded(.up)))) с")
            }
        case .failed(let message):
            Text(message).lineLimit(1)
        default:
            EmptyView()
        }
    }

    private var controls: some View {
        HStack {
            if service.state.isActive {
                Button { service.stop() } label: { Label("Стоп", systemImage: "stop.fill") }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(service.state == .stopping)
            } else {
                Button { service.start() } label: { Label("Старт", systemImage: "play.fill") }
                    .keyboardShortcut("r", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            Button { service.restart() } label: { Label("Перезапуск", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(action: onEdit) { Label("Изменить", systemImage: "pencil") }
        }
        .controlSize(.large)
    }

    private var logToolbar: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            TextField("Фильтр логов", text: $filter)
                .textFieldStyle(.plain)
            Spacer()
            Button { copyLogs() } label: { Image(systemName: "doc.on.doc") }
                .help("Скопировать логи")
            Button { service.clearLogs() } label: { Image(systemName: "trash") }
                .help("Очистить экран (файл лога сохраняется)")
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([service.logs.fileURL])
            } label: { Image(systemName: "folder") }
                .help("Показать файл лога в Finder")
        }
        .buttonStyle(.borderless)
    }

    private func copyLogs() {
        let lines = service.logs.lines.filter { filter.isEmpty || $0.text.localizedCaseInsensitiveContains(filter) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let total = Int(interval)
    let h = total / 3600, m = total % 3600 / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

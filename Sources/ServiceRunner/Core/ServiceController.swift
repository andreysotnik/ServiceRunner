import Foundation
import SwiftUI

enum ServiceState: Equatable {
    case stopped
    case running(pid: pid_t, since: Date)
    case stopping
    case crashed(ExitReason)
    case failed(String)
    case restarting(at: Date, after: ExitReason)

    var isActive: Bool {
        switch self {
        case .running, .stopping, .restarting: return true
        default: return false
        }
    }

    var isProblem: Bool {
        switch self {
        case .crashed, .failed, .restarting: return true
        default: return false
        }
    }

    var color: Color {
        switch self {
        case .stopped: return .secondary
        case .running: return .green
        case .stopping: return .orange
        case .restarting: return .yellow
        case .crashed, .failed: return .red
        }
    }

    var title: String {
        switch self {
        case .stopped: return "Остановлен"
        case .running: return "Работает"
        case .stopping: return "Останавливается…"
        case .crashed(let reason): return "Упал (\(reason.description))"
        case .failed: return "Ошибка запуска"
        case .restarting: return "Перезапуск…"
        }
    }
}

/// Owns one service: its process, state, logs and auto-restart policy.
@MainActor
final class ServiceController: ObservableObject, Identifiable {
    static let stopTimeout: TimeInterval = 5
    static let maxBackoff: TimeInterval = 30
    static let stableRunDuration: TimeInterval = 60

    @Published var config: ServiceConfig
    @Published private(set) var state: ServiceState = .stopped
    /// Bumped whenever log lines change so views can refresh.
    @Published private(set) var logRevision = 0

    let logs: LogBuffer
    nonisolated let id: UUID

    /// Called when the process ends without being asked to.
    var onUnexpectedExit: ((ServiceController, ExitReason) -> Void)?

    private var runner: ProcessRunner?
    private var stopRequested = false
    private var stopWaiters: [() -> Void] = []
    private var restartTask: Task<Void, Never>?
    private var consecutiveCrashes = 0

    nonisolated(unsafe) private var pendingLines: [(Date, String)] = []
    nonisolated private let pendingLock = NSLock()
    nonisolated(unsafe) private var flushScheduled = false

    init(config: ServiceConfig, logDirectory: URL) {
        self.config = config
        id = config.id
        let safeName = config.name.replacingOccurrences(of: "[^A-Za-z0-9А-Яа-я._-]+", with: "_", options: .regularExpression)
        logs = LogBuffer(fileURL: logDirectory.appendingPathComponent("\(safeName)-\(config.id.uuidString.prefix(8)).log"))
    }

    func start() {
        guard runner == nil else { return }
        restartTask?.cancel()
        restartTask = nil
        stopRequested = false
        system("▶ Запуск: \(config.command)")
        do {
            let runner = try ProcessRunner(
                command: config.command,
                workingDirectory: config.workingDirectory,
                onLine: { [weak self] line in self?.enqueue(line) },
                onExit: { [weak self] reason in
                    Task { @MainActor in self?.handleExit(reason) }
                }
            )
            self.runner = runner
            let since = Date()
            state = .running(pid: runner.pid, since: since)
            scheduleStabilityReset(since: since)
        } catch {
            system("✖ \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    /// SIGTERM to the process group, SIGKILL after a timeout.
    func stop(completion: (() -> Void)? = nil) {
        restartTask?.cancel()
        restartTask = nil
        guard let runner else {
            if case .restarting = state { state = .stopped }
            completion?()
            return
        }
        if let completion { stopWaiters.append(completion) }
        guard !stopRequested else { return }
        stopRequested = true
        state = .stopping
        system("■ Остановка (SIGTERM)")
        runner.signal(SIGTERM)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopTimeout) { [weak self, weak runner] in
            guard let self, let runner, self.runner === runner else { return }
            self.system("■ Не завершился за \(Int(Self.stopTimeout)) с — SIGKILL")
            runner.signal(SIGKILL)
        }
    }

    func restart() {
        if runner == nil {
            start()
        } else {
            stop { [weak self] in self?.start() }
        }
    }

    func clearLogs() {
        logs.clear()
        logRevision += 1
    }

    // MARK: - Private

    private func handleExit(_ reason: ExitReason) {
        flushLines()
        runner = nil
        let waiters = stopWaiters
        stopWaiters = []

        if stopRequested {
            system("■ Остановлен (\(reason.description))")
            state = .stopped
        } else {
            system("✖ Процесс завершился: \(reason.description)")
            consecutiveCrashes += 1
            if config.autoRestart {
                let delay = min(pow(2, Double(consecutiveCrashes - 1)), Self.maxBackoff)
                state = .restarting(at: Date().addingTimeInterval(delay), after: reason)
                system("↻ Перезапуск через \(Int(delay)) с")
                restartTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.start()
                }
            } else {
                state = .crashed(reason)
            }
            onUnexpectedExit?(self, reason)
        }
        stopRequested = false
        waiters.forEach { $0() }
    }

    private func scheduleStabilityReset(since: Date) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stableRunDuration) { [weak self] in
            guard let self, case .running(_, let s) = self.state, s == since else { return }
            self.consecutiveCrashes = 0
        }
    }

    private func system(_ text: String) {
        flushLines()
        logs.append(text, kind: .system)
        logRevision += 1
    }

    /// Called from the runner's queue; lines are batched to keep the UI responsive.
    nonisolated private func enqueue(_ line: String) {
        let date = Date()
        pendingLock.lock()
        pendingLines.append((date, line))
        let needsFlush = !flushScheduled
        flushScheduled = true
        pendingLock.unlock()
        if needsFlush {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                MainActor.assumeIsolated { self?.flushLines() }
            }
        }
    }

    private func flushLines() {
        pendingLock.lock()
        let batch = pendingLines
        pendingLines = []
        flushScheduled = false
        pendingLock.unlock()
        guard !batch.isEmpty else { return }
        for (date, line) in batch {
            logs.append(line, date: date)
        }
        logRevision += 1
    }
}

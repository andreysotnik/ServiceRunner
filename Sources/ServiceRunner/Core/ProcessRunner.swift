import Darwin
import Foundation

/// How a spawned process ended.
enum ExitReason: Equatable {
    case exited(Int32)
    case signaled(Int32)

    var isSuccess: Bool { self == .exited(0) }

    var description: String {
        switch self {
        case .exited(let code): return "код \(code)"
        case .signaled(let sig): return "сигнал \(sig) (\(String(cString: strsignal(sig))))"
        }
    }
}

enum ProcessRunnerError: LocalizedError {
    case spawnFailed(Int32)
    case pipeFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .spawnFailed(let err): return "Не удалось запустить процесс: \(String(cString: strerror(err)))"
        case .pipeFailed(let err): return "Не удалось создать pipe: \(String(cString: strerror(err)))"
        }
    }
}

/// Runs a shell command in its own process group, streams combined stdout/stderr
/// line by line and reports termination. Stopping signals the whole group, so
/// grandchildren (e.g. `node` under `npm run`) are terminated too.
final class ProcessRunner {
    let pid: pid_t
    private let queue = DispatchQueue(label: "ServiceRunner.ProcessRunner")
    private let outputHandle: FileHandle
    private var exitSource: DispatchSourceProcess?
    private var pendingOutput = Data()
    private var exitReason: ExitReason?
    private var outputClosed = false
    private var onLine: ((String) -> Void)?
    private var onExit: ((ExitReason) -> Void)?

    /// Starts `command` via the user's login shell so PATH etc. match the terminal.
    /// Callbacks are invoked on a private serial queue.
    init(
        command: String,
        workingDirectory: String?,
        onLine: @escaping (String) -> Void,
        onExit: @escaping (ExitReason) -> Void
    ) throws {
        self.onLine = onLine
        self.onExit = onExit

        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { throw ProcessRunnerError.pipeFailed(errno) }
        let readFD = fds[0], writeFD = fds[1]
        _ = fcntl(readFD, F_SETFD, FD_CLOEXEC)

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&fileActions, writeFD, 1)
        posix_spawn_file_actions_adddup2(&fileActions, writeFD, 2)
        posix_spawn_file_actions_addclose(&fileActions, writeFD)
        if let dir = workingDirectory, !dir.isEmpty {
            posix_spawn_file_actions_addchdir_np(&fileActions, (dir as NSString).expandingTildeInPath)
        }

        var attrs: posix_spawnattr_t?
        posix_spawnattr_init(&attrs)
        defer { posix_spawnattr_destroy(&attrs) }
        // New process group with pgid == pid; reset signal mask/handlers inherited from the app.
        posix_spawnattr_setpgroup(&attrs, 0)
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attrs, &noSignals)
        var allSignals = sigset_t()
        sigfillset(&allSignals)
        posix_spawnattr_setsigdefault(&attrs, &allSignals)
        posix_spawnattr_setflags(&attrs, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))

        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = env["TERM"] ?? "xterm-256color"
        let args = [shell, "-l", "-c", command]
        let envStrings = env.map { "\($0.key)=\($0.value)" }

        var cArgs = args.map { strdup($0) } + [nil]
        var cEnv = envStrings.map { strdup($0) } + [nil]
        defer {
            cArgs.forEach { free($0) }
            cEnv.forEach { free($0) }
        }

        var childPID: pid_t = 0
        let rc = posix_spawn(&childPID, shell, &fileActions, &attrs, &cArgs, &cEnv)
        close(writeFD)
        guard rc == 0 else {
            close(readFD)
            throw ProcessRunnerError.spawnFailed(rc)
        }
        pid = childPID
        outputHandle = FileHandle(fileDescriptor: readFD, closeOnDealloc: true)

        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            self?.queue.async { self?.consume(data) }
        }

        let source = DispatchSource.makeProcessSource(identifier: childPID, eventMask: .exit, queue: queue)
        // Strong capture keeps the runner alive until the process is reaped.
        source.setEventHandler { self.reap() }
        exitSource = source
        source.resume()
        // The child may have exited before the source was armed.
        queue.async { self.reap() }
    }

    /// Sends `signal` to the whole process group.
    func signal(_ sig: Int32) {
        kill(-pid, sig)
    }

    private func reap() {
        guard exitReason == nil else { return }
        var status: Int32 = 0
        let r = waitpid(pid, &status, WNOHANG)
        guard r == pid else { return }
        exitSource?.cancel()
        exitSource = nil
        let low = status & 0x7f
        exitReason = low == 0 ? .exited((status >> 8) & 0xff) : .signaled(low)
        // Background children may keep the pipe open; give the output a moment, then finish.
        queue.asyncAfter(deadline: .now() + 0.3) { self.finish() }
    }

    private func consume(_ data: Data) {
        if data.isEmpty {
            outputClosed = true
            outputHandle.readabilityHandler = nil
            finish()
            return
        }
        pendingOutput.append(data)
        while let nl = pendingOutput.firstIndex(of: 0x0A) {
            let lineData = pendingOutput[pendingOutput.startIndex..<nl]
            pendingOutput.removeSubrange(pendingOutput.startIndex...nl)
            emit(lineData)
        }
    }

    private func emit(_ data: Data) {
        var line = String(decoding: data, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        onLine?(line)
    }

    private func finish() {
        guard let reason = exitReason, let onExit else { return }
        if !pendingOutput.isEmpty {
            emit(pendingOutput)
            pendingOutput.removeAll()
        }
        if !outputClosed {
            outputHandle.readabilityHandler = nil
        }
        self.onExit = nil
        self.onLine = nil
        onExit(reason)
    }
}

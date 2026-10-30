import Darwin
import XCTest
@testable import ServiceRunner

final class ProcessRunnerTests: XCTestCase {
    private final class Collector {
        let lock = NSLock()
        var lines: [String] = []
        var reason: ExitReason?
    }

    private func run(_ command: String, cwd: String? = nil) throws -> (ProcessRunner, Collector, XCTestExpectation) {
        let collector = Collector()
        let exited = expectation(description: "exit")
        let runner = try ProcessRunner(
            command: command,
            workingDirectory: cwd,
            onLine: { line in collector.lock.withLock { collector.lines.append(line) } },
            onExit: { reason in
                collector.lock.withLock { collector.reason = reason }
                exited.fulfill()
            }
        )
        return (runner, collector, exited)
    }

    func testCapturesStdoutAndStderrAndExitCode() throws {
        let (_, collector, exited) = try run("echo out; echo err >&2; printf 'tail'; exit 3")
        wait(for: [exited], timeout: 10)
        XCTAssertEqual(collector.lines, ["out", "err", "tail"])
        XCTAssertEqual(collector.reason, .exited(3))
    }

    func testWorkingDirectory() throws {
        let (_, collector, exited) = try run("pwd -P", cwd: "/tmp")
        wait(for: [exited], timeout: 10)
        XCTAssertEqual(collector.lines.last, "/private/tmp")
    }

    func testStopKillsWholeProcessGroup() throws {
        let marker = "sr-test-\(UUID().uuidString.prefix(8))"
        // Background child that would survive if only the shell were killed.
        let (runner, collector, exited) = try run("sh -c 'exec -a \(marker) sleep 1000' & echo started; wait")
        let deadline = Date().addingTimeInterval(10)
        while collector.lock.withLock({ collector.lines.isEmpty }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertTrue(pgrep(marker), "child should be running")

        runner.signal(SIGTERM)
        wait(for: [exited], timeout: 10)
        XCTAssertEqual(collector.reason, .signaled(SIGTERM))
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(pgrep(marker), "child should be terminated with the group")
    }

    private func pgrep(_ pattern: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        p.standardOutput = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    func testStripANSI() {
        XCTAssertEqual(LogBuffer.stripANSI("\u{1B}[32mok\u{1B}[0m done"), "ok done")
    }
}

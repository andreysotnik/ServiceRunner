import AppKit
import SwiftUI

extension Notification.Name {
    static let openMainWindow = Notification.Name("ServiceRunner.openMainWindow")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ServiceStore()
    let notifier = Notifier()
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`).
        NSApp.setActivationPolicy(.regular)
        notifier.setUp()
        notifier.onOpen = { [weak self] id in
            self?.store.selection = id
            NotificationCenter.default.post(name: .openMainWindow, object: nil)
        }
        store.onUnexpectedExit = { [weak self] service, reason in
            self?.notifier.notifyCrash(
                name: service.config.name,
                id: service.id,
                reason: reason,
                restarting: service.config.autoRestart
            )
        }
        store.startAutoStartServices()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.runningCount > 0 else { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        store.stopAll {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct ServiceRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("ServiceRunner", id: "main") {
            MainWindow()
                .environmentObject(appDelegate.store)
        }
        .defaultSize(width: 1000, height: 640)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.store)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

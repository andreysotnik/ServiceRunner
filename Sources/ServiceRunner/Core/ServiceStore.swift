import Combine
import Foundation
import SwiftUI

/// The list of services, persisted as JSON in Application Support.
@MainActor
final class ServiceStore: ObservableObject {
    @Published private(set) var services: [ServiceController] = []
    /// Bumped whenever any service changes state, so aggregate views refresh.
    @Published private(set) var stateRevision = 0
    @Published var selection: UUID?

    let configURL: URL
    let logDirectory: URL
    var onUnexpectedExit: ((ServiceController, ExitReason) -> Void)?

    private var observers: [UUID: Any] = [:]

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ServiceRunner", isDirectory: true)
        try? fm.createDirectory(at: support, withIntermediateDirectories: true)
        configURL = support.appendingPathComponent("services.json")
        logDirectory = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ServiceRunner", isDirectory: true)
        load()
    }

    var hasProblems: Bool { services.contains { $0.state.isProblem } }
    var runningCount: Int { services.filter { $0.state.isActive }.count }

    func service(id: UUID?) -> ServiceController? {
        services.first { $0.id == id }
    }

    func add(_ config: ServiceConfig) {
        services.append(makeController(config))
        selection = config.id
        save()
    }

    func update(_ config: ServiceConfig) {
        guard let controller = service(id: config.id) else { return }
        controller.config = config
        save()
    }

    func remove(id: UUID) {
        guard let controller = service(id: id) else { return }
        controller.stop()
        services.removeAll { $0.id == id }
        observers[id] = nil
        if selection == id { selection = services.first?.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        services.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func startAutoStartServices() {
        services.filter { $0.config.autoStart }.forEach { $0.start() }
    }

    func stopAll(completion: @escaping () -> Void) {
        let active = services.filter { $0.state.isActive }
        guard !active.isEmpty else { return completion() }
        var remaining = active.count
        for service in active {
            service.stop {
                remaining -= 1
                if remaining == 0 { completion() }
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: configURL),
              let configs = try? JSONDecoder().decode([ServiceConfig].self, from: data)
        else { return }
        services = configs.map(makeController)
        selection = services.first?.id
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(services.map(\.config)) else { return }
        try? data.write(to: configURL, options: .atomic)
    }

    private func makeController(_ config: ServiceConfig) -> ServiceController {
        let controller = ServiceController(config: config, logDirectory: logDirectory)
        controller.onUnexpectedExit = { [weak self] service, reason in
            self?.onUnexpectedExit?(service, reason)
        }
        observers[config.id] = controller.$state.sink { [weak self] _ in
            self?.stateRevision += 1
        }
        return controller
    }
}

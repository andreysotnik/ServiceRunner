import Foundation

struct ServiceConfig: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    var workingDirectory: String = ""
    var autoStart = false
    var autoRestart = false
}

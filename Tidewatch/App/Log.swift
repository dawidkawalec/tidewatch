import os

enum Log {
    static let app = Logger(subsystem: "pl.craftweb.tidewatch", category: "app")
    static let sessions = Logger(subsystem: "pl.craftweb.tidewatch", category: "sessions")
    static let ui = Logger(subsystem: "pl.craftweb.tidewatch", category: "ui")
    static let hooks = Logger(subsystem: "pl.craftweb.tidewatch", category: "hooks")
}

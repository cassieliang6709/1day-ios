import Foundation
import os

enum Log {
    static let subsystem = "com.cassie.AISetlog"

    static let api = Logger(subsystem: subsystem, category: "api")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let app = Logger(subsystem: subsystem, category: "app")
    static let debug = Logger(subsystem: subsystem, category: "debug")
}

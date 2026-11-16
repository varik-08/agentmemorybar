import Foundation
import Darwin

struct ControlResult {
    var snapshot: [String: Any]?
    var error: String?
}

struct BarSettings: Codable {
    var startServerOnLaunch = true
    var executable = ""
    var cliPath = ""
    var dataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/agentmemory").path
}

struct BarError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum Controller {
    #if TESTING
    static let home = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    #else
    static let home = FileManager.default.homeDirectoryForCurrentUser
    #endif
    static let root = home.appendingPathComponent(".agentmemory")
    static let service = home.appendingPathComponent("Library/Application Support/AgentMemoryBar")
    static let settingsURL = service.appendingPathComponent("settings.json")
    static let logURL = service.appendingPathComponent("runtime.log")
    static let label = "local.agentmemorybar"
    static let domain = "gui/\(getuid())"
    static let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    static let searchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    static func prepare() throws {
        try FileManager.default.createDirectory(at: service, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    static func settings() throws -> BarSettings {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return BarSettings() }
        return try JSONDecoder().decode(BarSettings.self, from: Data(contentsOf: settingsURL))
    }

    static func save(_ settings: BarSettings) throws {
        try prepare()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }

    static func command(_ settings: BarSettings) throws -> [String] {
        let fm = FileManager.default
        if !settings.executable.isEmpty {
            guard fm.isExecutableFile(atPath: settings.executable) else {
                throw BarError(message: "The configured executable is missing. Open Settings to select Node.js or agentmemory.")
            }
            if !settings.cliPath.isEmpty && !fm.fileExists(atPath: settings.cliPath) {
                throw BarError(message: "The configured agentmemory CLI file is missing.")
            }
            return [settings.executable] + (settings.cliPath.isEmpty ? [] : [settings.cliPath])
        }
        let bins = ["/opt/homebrew/bin", "/usr/local/bin"]
        if let executable = bins.map({ $0 + "/agentmemory" }).first(where: { fm.isExecutableFile(atPath: $0) }) {
            return [executable]
        }
        // Recognize the pinned installation used before AgentMemoryBar; never scan npm caches.
        let pinned = root.appendingPathComponent("runtime-0.9.33/node_modules/@agentmemory/agentmemory/dist/cli.mjs")
        if fm.fileExists(atPath: pinned.path),
           let node = bins.map({ $0 + "/node" }).first(where: { fm.isExecutableFile(atPath: $0) }) {
            return [node, pinned.path]
        }
        throw BarError(message: "Install agentmemory first, then select its executable in Settings. See the README for setup.")
    }

    // Capture stdout/stderr in a file so a verbose CLI cannot deadlock a pipe.
    static func execute(_ arguments: [String], timeout: TimeInterval = 420,
                        runtimeLog: Bool = false) throws -> (Int32, String) {
        try prepare()
        let outputURL = runtimeLog ? logURL : FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tmp")
        if runtimeLog, let size = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size]) as? Int,
           size > 2 * 1024 * 1024 {
            let previous = service.appendingPathComponent("runtime.previous.log")
            try? FileManager.default.removeItem(at: previous)
            try FileManager.default.moveItem(at: outputURL, to: previous)
        }
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        defer { if !runtimeLog { try? FileManager.default.removeItem(at: outputURL) } }
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0])
        process.arguments = Array(arguments.dropFirst())
        process.currentDirectoryURL = service
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = URL(fileURLWithPath: arguments[0]).deletingLastPathComponent().path + ":" + searchPath
        environment["CI"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 3) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw BarError(message: "The command timed out. Inspect runtime.log before retrying.")
        }
        process.waitUntilExit()
        let output = runtimeLog ? "" : (try String(contentsOf: outputURL, encoding: .utf8))
        return (process.terminationStatus, output)
    }

    static func loginEnabled() -> Bool {
        guard FileManager.default.fileExists(atPath: plist.path),
              let result = try? execute(["/bin/launchctl", "print-disabled", domain], timeout: 10), result.0 == 0
        else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: label)
        return result.1.range(of: "\"" + escaped + "\"\\s*=>\\s*(true|disabled)\\b",
                              options: .regularExpression) == nil
    }

    static func setLogin(_ enabled: Bool) throws {
        let job = domain + "/" + label
        if !enabled {
            let result = try execute(["/bin/launchctl", "disable", job], timeout: 15)
            guard result.0 == 0 else { throw BarError(message: "Could not disable launch at login.") }
            // The current application keeps running. The disabled job is not run at next login.
            try? FileManager.default.removeItem(at: plist)
            return
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            throw BarError(message: "Install and launch the .app bundle before enabling launch at login.")
        }
        let definition: [String: Any] = [
            "Label": label,
            "ProgramArguments": [Bundle.main.executableURL!.path],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
            "StandardOutPath": service.appendingPathComponent("app.out.log").path,
            "StandardErrorPath": service.appendingPathComponent("app.err.log").path
        ]
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0)
            .write(to: plist, options: .atomic)
        let result = try execute(["/bin/launchctl", "enable", job], timeout: 15)
        guard result.0 == 0 else { throw BarError(message: "Could not enable launch at login.") }
        // No bootstrap here: it would create a second instance. launchd reads the plist at next login.
    }

    static func secret() -> String? {
        if let value = ProcessInfo.processInfo.environment["AGENTMEMORY_SECRET"], !value.isEmpty { return value }
        if let contents = try? String(contentsOf: root.appendingPathComponent(".env"), encoding: .utf8) {
            for raw in contents.components(separatedBy: .newlines) {
                var line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("export ") { line = String(line.dropFirst(7)) }
                let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "AGENTMEMORY_SECRET" else { continue }
                var value = parts[1].trimmingCharacters(in: .whitespaces)
                if let quote = value.first, quote == "\"" || quote == "'" {
                    value = String(value.dropFirst().prefix(while: { $0 != quote }))
                } else if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]) }
                if !value.isEmpty { return value }
            }
        }
        return (try? String(contentsOf: root.appendingPathComponent("secret"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func request(_ endpoint: String, authenticated: Bool = false) -> (Int, [String: Any]?) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:3111/agentmemory/" + endpoint)!)
        request.timeoutInterval = 4
        if authenticated {
            guard let value = secret(), !value.isEmpty else { return (401, nil) }
            request.setValue("Bearer " + value, forHTTPHeaderField: "Authorization")
        }
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Int, [String: Any]?) = (0, nil)
        let task = session.dataTask(with: request) { data, response, _ in
            result = ((response as? HTTPURLResponse)?.statusCode ?? 0,
                      data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] })
            semaphore.signal()
        }
        task.resume()
        if semaphore.wait(timeout: .now() + 6) == .timedOut { task.cancel(); return (0, nil) }
        return result
    }

    static func probe() -> String {
        let live = request("livez")
        guard live.0 != 0 else { return "unavailable" }
        guard live.0 == 200, live.1?["service"] as? String == "agentmemory" else { return "unexpected-service" }
        let health = request("health", authenticated: true)
        if health.0 == 401 || health.0 == 403 { return "auth-error" }
        return health.0 == 200 && health.1?["status"] as? String == "healthy" ? "healthy" : "unhealthy"
    }

    static func runtime(_ action: String? = nil, settings: BarSettings) throws {
        var args = try command(settings)
        if let action { args.append(action) }
        args += ["--data-dir", settings.dataDirectory, "--port", "3111"]
        let result = try execute(args, runtimeLog: true)
        guard result.0 == 0 else { throw BarError(message: "agentmemory failed. Open Logs and inspect runtime.log.") }
    }

    static func ownedRecord(_ settings: BarSettings) throws -> Bool {
        let path = root.appendingPathComponent("engine-state.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return false }
        let data = try Data(contentsOf: path)
        let state = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let expected = URL(fileURLWithPath: settings.dataDirectory).appendingPathComponent("compose/worker-compose.yaml")
        guard state?["kind"] as? String == "compose", state?["restPort"] as? Int == 3111,
              let file = state?["file"] as? String,
              URL(fileURLWithPath: file).standardizedFileURL == expected.standardizedFileURL else {
            throw BarError(message: "This runtime belongs to a different instance. No process was stopped.")
        }
        return true
    }

    static func stop(_ settings: BarSettings) throws {
        if try ownedRecord(settings) { try runtime("stop", settings: settings) }
        guard probe() == "unavailable" else {
            throw BarError(message: "A service is still responding. No unrelated process was stopped.")
        }
    }

    static func start(_ settings: BarSettings) throws {
        let health = probe()
        if health == "healthy" { return }
        guard health == "unavailable" else {
            throw BarError(message: "Server state is \(health). Inspect the existing instance before starting another.")
        }
        if try ownedRecord(settings) { try stop(settings) }
        try runtime(settings: settings)
        for _ in 0..<15 {
            if probe() == "healthy" { return }
            Thread.sleep(forTimeInterval: 2)
        }
        throw BarError(message: "agentmemory did not become healthy. Open Logs for details.")
    }

    static func snapshot(_ settings: BarSettings) -> [String: Any] {
        let login = loginEnabled()
        return ["server": probe(), "enabled": settings.startServerOnLaunch,
                "autostart_enabled": login && settings.startServerOnLaunch,
                "app_login_enabled": login, "autostart_mode": "application",
                "periodic_check_enabled": false, "viewer": "http://localhost:3113",
                "data_directory": settings.dataDirectory,
                "runtime_found": (try? command(settings)) != nil]
    }

    static func run(_ action: String) -> ControlResult {
        do {
            try prepare()
            let fd = open(service.appendingPathComponent("control.lock").path, O_CREAT | O_RDWR, 0o600)
            guard fd >= 0 else { throw BarError(message: "Cannot open the control lock.") }
            defer { flock(fd, LOCK_UN); close(fd) }
            // Shared by the app and command-line entry point. A second click never starts a second server.
            guard flock(fd, LOCK_EX) == 0 else { throw BarError(message: "Cannot lock the controller.") }
            var config = try settings()
            switch action {
            case "on", "restart":
                if action == "restart" { try stop(config) }
                try start(config)
                config.startServerOnLaunch = true
                try save(config)
            case "off":
                try stop(config)
                config.startServerOnLaunch = false
                try save(config)
            case "login":
                if config.startServerOnLaunch { try start(config) }
            case "login-on": try setLogin(true)
            case "login-off": try setLogin(false)
            case "status": break
            default: throw BarError(message: "Unknown control action.")
            }
            return ControlResult(snapshot: snapshot(config))
        } catch { return ControlResult(error: error.localizedDescription) }
    }
}

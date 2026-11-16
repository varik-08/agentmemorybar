import Foundation

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw BarError(message: message) }
    checks += 1
}

do {
    try Controller.prepare()
    var config = BarSettings()
    config.dataDirectory = Controller.home.appendingPathComponent("store with spaces").path
    try check(try Controller.settings().startServerOnLaunch, "Default should start server on app launch")
    config.startServerOnLaunch = false
    try Controller.save(config)
    try check(try !Controller.settings().startServerOnLaunch, "Stop preference must survive a relaunch")
    try check(try Controller.settings().dataDirectory == config.dataDirectory, "Data path must round-trip")
    let permissions = try FileManager.default.attributesOfItem(atPath: Controller.settingsURL.path)[.posixPermissions] as? Int
    try check(permissions == 0o600, "Private settings permissions")
    try FileManager.default.createDirectory(at: Controller.root, withIntermediateDirectories: true)
    try "fallback-secret\n".write(to: Controller.root.appendingPathComponent("secret"), atomically: true, encoding: .utf8)
    try check(Controller.secret() == "fallback-secret", "Secret discovery")
    try "export AGENTMEMORY_SECRET = 'configured-value' # comment\n".write(to: Controller.root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
    try check(Controller.secret() == "configured-value", "Explicit .env secret has precedence")
    try check(try !Controller.ownedRecord(config), "Missing ownership is not ownership")
    let record: [String: Any] = ["kind": "compose", "restPort": 3111,
                               "file": config.dataDirectory + "/compose/worker-compose.yaml"]
    let recordURL = Controller.root.appendingPathComponent("engine-state.json")
    try JSONSerialization.data(withJSONObject: record).write(to: recordURL)
    try check(try Controller.ownedRecord(config), "Matching runtime is owned")
    var mismatched = config
    mismatched.dataDirectory += "/different"
    var refused = false
    do { _ = try Controller.ownedRecord(mismatched) } catch { refused = true }
    try check(refused, "Never stop an instance with a different store")
    config.executable = "/bin/echo"
    config.cliPath = ""
    try check(try Controller.command(config) == ["/bin/echo"], "Explicit executable")
    let result = try Controller.execute(["/bin/echo", "literal path with spaces; $(no shell)"])
    try check(result.0 == 0 && result.1.trimmingCharacters(in: .newlines) == "literal path with spaces; $(no shell)", "Arguments must not be interpreted by a shell")
    let unknown = Controller.run("not-an-action")
    try check(unknown.error != nil, "Unknown actions must fail")
    print("Passed \(checks) controller checks")
} catch {
    fputs("Test failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}

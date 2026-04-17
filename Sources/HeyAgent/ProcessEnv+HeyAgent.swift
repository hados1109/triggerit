import Foundation

enum ProcessEnvHeyAgent {
    /// Prepends common Homebrew locations so `uv` / `go` resolve when the app is not started from a login shell.
    static func withHomebrewPrefixes(_ base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        let pathPrefixes = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let existing = env["PATH"] ?? ""
        env["PATH"] = pathPrefixes.joined(separator: ":") + (existing.isEmpty ? "" : ":" + existing)
        return env
    }
}

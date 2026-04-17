import Foundation

/// Resolves the HeyAgent repo root from this source file’s location (`…/Sources/HeyAgent/…`).
enum GazeBridgePaths {
    private static var agentSourcesDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    }

    /// Directory that contains `Package.swift` and the `python/` folder.
    static var packageRoot: URL {
        agentSourcesDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var pythonDirectory: URL {
        packageRoot.appendingPathComponent("python", isDirectory: true)
    }

    static var gazeBridgeScriptExists: Bool {
        FileManager.default.fileExists(
            atPath: pythonDirectory.appendingPathComponent("gaze_bridge.py").path
        )
    }

    static var slapBridgeDirectory: URL {
        packageRoot.appendingPathComponent("slap-bridge", isDirectory: true)
    }

    static var slapBridgeMainExists: Bool {
        FileManager.default.fileExists(atPath: slapBridgeDirectory.appendingPathComponent("main.go").path)
    }
}

import Foundation

/// Owns the long-running **gaze** `Process` and opens **slap-bridge** in Terminal (sudo).
@MainActor
final class BridgeSupervisor: ObservableObject {
    @Published var eyeTrackingEnabled = true
    @Published var slapEnabled = false

    @Published var gazeCameraIndex = 0
    @Published var gazeProfile = ""

    @Published var slapFastMode = true
    @Published var slapMinAmplitude = 0.20
    @Published var slapCooldownMs = 1500.0

    @Published var isGazeBridgeRunning = false
    @Published var statusMessage = ""

    private var gazeProcess: Process?

    /// Stops the managed gaze bridge process (slap runs in Terminal — close that tab yourself).
    func stopGazeBridge() {
        guard let proc = gazeProcess else {
            isGazeBridgeRunning = false
            return
        }
        gazeProcess = nil
        if proc.isRunning {
            proc.terminate()
        }
        isGazeBridgeRunning = false
        statusMessage = "Gaze bridge stopped."
    }

    /// Stops gaze (if any) then starts components according to toggles. Slap opens a new Terminal tab.
    func runBridges(udpPort: UInt16) {
        stopGazeBridge()

        var parts: [String] = []

        if eyeTrackingEnabled {
            if GazeBridgePaths.gazeBridgeScriptExists {
                startGazeProcess(udpPort: udpPort)
                parts.append("Gaze bridge started (camera \(gazeCameraIndex)).")
            } else {
                parts.append("Gaze: python/gaze_bridge.py not found next to the app package.")
            }
        }

        if slapEnabled {
            if GazeBridgePaths.slapBridgeMainExists {
                do {
                    try openSlapInTerminal(udpPort: udpPort)
                    parts.append("Slap: opened Terminal — approve sudo if asked, then leave that tab open.")
                } catch {
                    parts.append("Slap: could not open Terminal (\(error.localizedDescription)).")
                }
            } else {
                parts.append("Slap: slap-bridge/main.go not found.")
            }
        }

        if parts.isEmpty {
            statusMessage = "Nothing started — enable eye tracking and/or slap."
        } else {
            statusMessage = parts.joined(separator: " ")
        }
    }

    private func startGazeProcess(udpPort: UInt16) {
        let args = GazeBridgeCommandRunner.gazeArgs(
            profile: gazeProfile,
            camera: gazeCameraIndex,
            extra: ["--udp-port", "\(udpPort)"]
        )

        let proc = Process()
        proc.currentDirectoryURL = GazeBridgePaths.pythonDirectory
        proc.environment = ProcessEnvTriggerit.withHomebrewPrefixes()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["uv", "run", "python", "gaze_bridge.py"] + args

        proc.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardError = FileHandle(forWritingAtPath: "/dev/null")

        proc.terminationHandler = { [weak self] finished in
            guard let self else { return }
            DispatchQueue.main.async {
                if let g = self.gazeProcess, g.processIdentifier == finished.processIdentifier {
                    self.gazeProcess = nil
                    self.isGazeBridgeRunning = false
                    self.statusMessage = "Gaze bridge exited (code \(finished.terminationStatus))."
                }
            }
        }

        do {
            try proc.run()
            gazeProcess = proc
            isGazeBridgeRunning = true
        } catch {
            gazeProcess = nil
            isGazeBridgeRunning = false
            statusMessage = "Gaze bridge failed to start: \(error.localizedDescription)"
        }
    }

    private func openSlapInTerminal(udpPort: UInt16) throws {
        let dir = GazeBridgePaths.slapBridgeDirectory.path
        let qdir = shellSingleQuotedPath(dir)
        let udp = "127.0.0.1:\(udpPort)"
        let fast = slapFastMode ? "-fast=true" : "-fast=false"
        let minA = String(format: "%.3f", slapMinAmplitude)
        let cool = Int(slapCooldownMs.rounded())
        let bash = "cd \(qdir) && sudo go run . --udp=\(udp) \(fast) -min-amplitude=\(minA) -cooldown=\(cool)"

        let escaped = bash
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell

        """

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-"]
        let input = Pipe()
        proc.standardInput = input
        proc.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        proc.standardError = FileHandle(forWritingAtPath: "/dev/null")

        let data = Data(source.utf8)
        let writer = input.fileHandleForWriting
        try writer.write(contentsOf: data)
        try writer.close()

        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            throw NSError(
                domain: "Triggerit",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "osascript exited with status \(proc.terminationStatus)"]
            )
        }
    }

    private func shellSingleQuotedPath(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

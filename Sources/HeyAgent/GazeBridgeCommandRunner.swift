import Foundation

/// Runs `uv run python gaze_bridge.py …` from the repo’s `python/` directory and captures output.
@MainActor
final class GazeBridgeCommandRunner: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning = false

    func run(arguments: [String]) {
        guard !isRunning else { return }
        guard GazeBridgePaths.gazeBridgeScriptExists else {
            output = "Could not find python/gaze_bridge.py next to this app’s package root (\(GazeBridgePaths.packageRoot.path)). Open the repo from disk or run from the HeyAgent folder."
            return
        }

        isRunning = true
        output = ""

        let cwd = GazeBridgePaths.pythonDirectory
        let args = arguments

        Task.detached { [cwd, args] in
            let text = Self.runProcessInPythonDir(cwd: cwd, gazeArguments: args)
            await MainActor.run {
                self.output = text
                self.isRunning = false
            }
        }
    }

    /// Builds CLI arguments after `gaze_bridge.py` (profile empty = default `~/.heyagent/gaze_model.pkl`).
    static func gazeArgs(profile: String?, camera: Int? = nil, extra: [String]) -> [String] {
        var out: [String] = []
        let p = profile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !p.isEmpty {
            out.append(contentsOf: ["--profile", p])
        }
        if let camera {
            out.append(contentsOf: ["--camera", "\(camera)"])
        }
        out.append(contentsOf: extra)
        return out
    }

    nonisolated private static func runProcessInPythonDir(cwd: URL, gazeArguments: [String]) -> String {
        let proc = Process()
        proc.currentDirectoryURL = cwd

        proc.environment = ProcessEnvHeyAgent.withHomebrewPrefixes()

        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["uv", "run", "python", "gaze_bridge.py"] + gazeArguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return "Failed to start process: \(error.localizedDescription)\n\nTip: install uv and run `uv sync` in the python folder once from Terminal."
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let outStr = String(data: outData, encoding: .utf8) ?? ""
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        var combined = outStr
        if !errStr.isEmpty {
            if !combined.isEmpty { combined += "\n" }
            combined += errStr
        }
        if combined.isEmpty {
            combined = "(no output, exit \(proc.terminationStatus))"
        } else if proc.terminationStatus != 0 {
            combined += "\n\nExit code: \(proc.terminationStatus)"
        }
        return combined
    }
}

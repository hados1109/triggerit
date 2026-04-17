import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var hub: TriggerHub
    @EnvironmentObject private var gazeRunner: GazeBridgeCommandRunner
    @EnvironmentObject private var bridge: BridgeSupervisor

    @State private var appendCalibrationNext = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Triggerit — Phase 1")
                        .font(.title2.weight(.semibold))

                    Text(
                        "UDP listener + optional bridges: Python gaze (webcam) and slap-bridge (sudo in Terminal)."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    HStack {
                        Text("UDP port")
                        TextField("Port", value: $hub.listenPort, format: .number)
                            .frame(width: 80)
                        Button(hub.listenerRunning ? "Stop" : "Listen") {
                            if hub.listenerRunning {
                                hub.stop()
                            } else {
                                hub.start()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                    }

                    if let err = hub.lastError {
                        Text(err).foregroundStyle(.red)
                    }

                    GroupBox("Run bridges") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(
                                "Choose what to run, tune slap if needed, then Run / Rerun (stops the gaze process first, then starts again). Slap always opens Terminal for sudo."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                            Toggle("Enable eye tracking (gaze bridge)", isOn: $bridge.eyeTrackingEnabled)

                            if bridge.eyeTrackingEnabled {
                                Picker("Camera index for gaze", selection: $bridge.gazeCameraIndex) {
                                    ForEach(0 ..< 8, id: \.self) { i in
                                        Text("\(i)").tag(i)
                                    }
                                }
                                .pickerStyle(.menu)
                                Text("Use “List cameras” below if the built-in webcam is not index 0.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            Divider()

                            Toggle("Enable slap (palm-rest tap)", isOn: $bridge.slapEnabled)

                            if bridge.slapEnabled {
                                Toggle("Slap: fast preset (shorter poll / cooldown overlay)", isOn: $bridge.slapFastMode)

                                HStack {
                                    Text("Min amplitude (g)")
                                    Spacer()
                                    Text(String(format: "%.2f", bridge.slapMinAmplitude))
                                        .monospacedDigit()
                                }
                                Slider(value: $bridge.slapMinAmplitude, in: 0.05 ... 0.6, step: 0.01) {
                                    Text("Min amplitude")
                                }

                                HStack {
                                    Text("Cooldown (ms)")
                                    Spacer()
                                    Text("\(Int(bridge.slapCooldownMs.rounded()))")
                                        .monospacedDigit()
                                }
                                Slider(value: $bridge.slapCooldownMs, in: 200 ... 4_000, step: 50) {
                                    Text("Cooldown")
                                }

                                Text(
                                    "Higher amplitude → harder tap required. Longer cooldown → fewer repeated triggers."
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }

                            Divider()

                            HStack(alignment: .firstTextBaseline) {
                                Text("Gaze profile (optional)")
                                TextField("e.g. office", text: $bridge.gazeProfile)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 12) {
                                Button("Run / Rerun bridges") {
                                    bridge.runBridges(udpPort: hub.listenPort)
                                }
                                .keyboardShortcut("r", modifiers: [.command])
                                .disabled(gazeRunner.isRunning)

                                Button("Stop gaze bridge") {
                                    bridge.stopGazeBridge()
                                }
                                .disabled(!bridge.isGazeBridgeRunning)
                            }

                            if bridge.isGazeBridgeRunning {
                                Label("Gaze bridge process is running", systemImage: "eye")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }

                            if !bridge.statusMessage.isEmpty {
                                Text(bridge.statusMessage)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Calibrate gaze") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Runs the dot-grid once, then saves a model for the camera index above. Stops the gaze bridge first so the webcam is free."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                            Toggle("Append to previous samples (same profile)", isOn: $appendCalibrationNext)

                            Button("Calibrate gaze now") {
                                bridge.stopGazeBridge()
                                var extra = ["--calibrate-only"]
                                if appendCalibrationNext {
                                    extra.append("--append-calibration")
                                }
                                gazeRunner.run(
                                    arguments: GazeBridgeCommandRunner.gazeArgs(
                                        profile: bridge.gazeProfile,
                                        camera: bridge.gazeCameraIndex,
                                        extra: extra
                                    ))
                            }
                            .disabled(!bridge.eyeTrackingEnabled || gazeRunner.isRunning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Last trigger") {
                        Text(hub.feedback.lastMessage)
                            .font(.body.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Gaze (from Python)") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Packets (UDP): \(hub.packetsReceived)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Text("x̂").monospaced()
                                Text(hub.gazeSX.map { String(format: "%.3f", $0) } ?? "—")
                            }
                            HStack {
                                Text("ŷ").monospaced()
                                Text(hub.gazeSY.map { String(format: "%.3f", $0) } ?? "—")
                            }
                            HStack {
                                Text("In AOI")
                                Spacer()
                                Text(hub.gazeInZone ? "yes" : "no")
                                    .foregroundStyle(hub.gazeInZone ? .green : .secondary)
                            }
                            HStack {
                                Text("Dwell (s)")
                                Spacer()
                                Text(String(format: "%.2f", hub.gazeDwell))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Gaze tools (one-shot)") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Uses the gaze profile field above. Disabled while a one-shot command is running.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                gazeToolButton(title: "List cameras", systemImage: "camera.viewfinder") {
                                    gazeRunner.run(
                                        arguments: GazeBridgeCommandRunner.gazeArgs(
                                            profile: bridge.gazeProfile,
                                            camera: nil,
                                            extra: ["--list-cameras"]
                                        ))
                                }
                                gazeToolButton(title: "List profiles", systemImage: "list.bullet.rectangle") {
                                    gazeRunner.run(
                                        arguments: GazeBridgeCommandRunner.gazeArgs(
                                            profile: bridge.gazeProfile,
                                            camera: nil,
                                            extra: ["--list-profiles"]
                                        ))
                                }
                            }

                            Button {
                                copyStreamCommand()
                            } label: {
                                Label("Copy stream command", systemImage: "doc.on.doc")
                            }
                            .disabled(gazeRunner.isRunning || bridge.isGazeBridgeRunning)

                            if gazeRunner.isRunning {
                                ProgressView("Running command…")
                                    .scaleEffect(0.9)
                            }

                            if !gazeRunner.output.isEmpty {
                                Text("Command output")
                                    .font(.caption.weight(.semibold))
                                Text(gazeRunner.output)
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    GroupBox("Manual commands") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Gaze stream (same as HUD Run when only eye tracking is on):")
                                .font(.caption.weight(.semibold))
                            Text(streamCommandSnippet)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                            Text("Slap (Terminal + sudo; matches sliders when you use Run above):")
                                .font(.caption.weight(.semibold))
                            Text(slapCommandSnippet)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
            }

            TriggerFlashOverlay(feedback: hub.feedback)
        }
        .onAppear {
            hub.start()
        }
        .onDisappear {
            hub.stop()
            bridge.stopGazeBridge()
        }
    }

    private var streamCommandSnippet: String {
        let py = GazeBridgePaths.pythonDirectory.path
        let p = bridge.gazeProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        var tail = "gaze_bridge.py --udp-port \(hub.listenPort) --camera \(bridge.gazeCameraIndex)"
        if !p.isEmpty {
            tail += " --profile \(p)"
        }
        return "cd \"\(py)\" && uv run python \(tail)"
    }

    private var slapCommandSnippet: String {
        let dir = GazeBridgePaths.slapBridgeDirectory.path
        let fast = bridge.slapFastMode ? "-fast=true" : "-fast=false"
        let minA = String(format: "%.3f", bridge.slapMinAmplitude)
        let cool = Int(bridge.slapCooldownMs.rounded())
        return "cd \"\(dir)\" && sudo go run . --udp=127.0.0.1:\(hub.listenPort) \(fast) -min-amplitude=\(minA) -cooldown=\(cool)"
    }

    private func copyStreamCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(streamCommandSnippet, forType: .string)
    }

    @ViewBuilder
    private func gazeToolButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(gazeRunner.isRunning || bridge.isGazeBridgeRunning)
    }
}

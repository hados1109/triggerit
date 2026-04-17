import Darwin
import Foundation
import SwiftUI

/// Receives UDP datagrams from `gaze_bridge.py` and `slap-bridge` on `listenPort`.
/// Uses POSIX `recvfrom` for reliable UDP delivery on macOS.
final class TriggerHub: ObservableObject {
    let feedback = TriggerFeedback()

    @Published var listenPort: UInt16 = 19_722
    @Published var listenerRunning = false
    @Published var lastError: String?

    @Published var gazeSX: Double?
    @Published var gazeSY: Double?
    @Published var gazeInZone = false
    @Published var gazeDwell: Double = 0
    @Published var packetsReceived: UInt64 = 0

    private var worker: Thread?
    private var shouldStop = false
    private var listenFD: Int32 = -1
    private let fdLock = NSLock()

    /// Throttle high-rate gaze packets so the main queue can run timers / flash dismiss reliably.
    private var lastGazeUIApply: TimeInterval = 0
    private let gazeUIMinInterval: TimeInterval = 1.0 / 30.0

    func start() {
        stop()
        lastError = nil
        shouldStop = false

        let port = Int(listenPort)
        let thr = Thread { [weak self] in
            self?.udpLoop(port: port)
        }
        thr.name = "Triggerit.UDP"
        worker = thr
        thr.start()

        DispatchQueue.main.async { [weak self] in
            self?.listenerRunning = true
        }
    }

    func stop() {
        shouldStop = true
        fdLock.lock()
        let fd = listenFD
        fdLock.unlock()
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
        }
        worker = nil
        DispatchQueue.main.async { [weak self] in
            self?.listenerRunning = false
        }
    }

    private func udpLoop(port: Int) {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = "socket() failed"
                self?.listenerRunning = false
            }
            return
        }

        fdLock.lock()
        listenFD = fd
        fdLock.unlock()

        defer {
            fdLock.lock()
            if listenFD == fd {
                listenFD = -1
            }
            fdLock.unlock()
            close(fd)
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: in_port_t(port).bigEndian,
            sin_addr: in_addr(s_addr: inet_addr("0.0.0.0")),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let bindOK = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
        if !bindOK {
            DispatchQueue.main.async { [weak self] in
                self?.lastError = "bind() failed — port in use?"
                self?.listenerRunning = false
            }
            return
        }

        var buf = [UInt8](repeating: 0, count: 8192)
        while !shouldStop {
            var peer = sockaddr_in()
            var peerLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &peer) { peerPtr in
                peerPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(fd, &buf, buf.count, 0, sa, &peerLen)
                }
            }
            if n < 0 {
                if shouldStop { break }
                usleep(2000)
                continue
            }
            if n == 0 { continue }
            let data = Data(buf[..<n])
            handleDatagram(data)
        }

        DispatchQueue.main.async { [weak self] in
            self?.listenerRunning = false
        }
    }

    private func handleDatagram(_ data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = obj["t"] as? String
        else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.packetsReceived += 1
            switch t {
            case "gaze":
                let now = ProcessInfo.processInfo.systemUptime
                if now - self.lastGazeUIApply < self.gazeUIMinInterval {
                    return
                }
                self.lastGazeUIApply = now
                if let sx = obj["sx"] as? Double { self.gazeSX = sx < 0 ? nil : sx }
                if let sy = obj["sy"] as? Double { self.gazeSY = sy < 0 ? nil : sy }
                if let z = obj["z"] as? Int { self.gazeInZone = z != 0 }
                if let d = obj["d"] as? Double { self.gazeDwell = d }
            case "gaze_trig":
                self.feedback.fire(source: "Gaze (camera AOI)", tint: .cyan)
            case "slap":
                self.feedback.fire(source: "Slap (accelerometer)", tint: .orange)
            default:
                break
            }
        }
    }
}

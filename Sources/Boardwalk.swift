// Boardwalk: a small macOS app for controlling a Bluetooth walking treadmill.
// Copyright (c) 2026 Palmetto Interactive LLC. MIT License.
//
// Talks to any treadmill that speaks the Bluetooth Fitness Machine Service (FTMS).
// See docs/PROTOCOL.md for the commands and the firmware quirks behind the code below.
//
// Firmware behaviour, measured on a YIJIAN ZBJ_38A_BT ("ESLinker-xxxxxx"):
//  - Start = Request Control (0x00) then Start (0x07). Belt always starts at 0.5 mph.
//  - Set Target Speed (0x02 + uint16 LE, 0.01 km/h) is silently dropped during the
//    ~2 s pre-workout countdown (Training Status 0x0E). It works once status is 0x0D.
//  - Stop = 0x08 0x01.
//  - The control point never sends indications, so success is read from Treadmill Data.
//  - Internally it runs in 0.1 mph steps with 1 mph = 1.6 km/h: it floors any km/h target
//    to a multiple of 0.16 and reports speed that way (0.8–6.4 km/h = 0.5–4.0 mph).
//
// URL scheme: boardwalk://on, off, faster, slower, speed?mph=2.5

import AppKit
import CoreBluetooth
import SwiftUI

let FTMS = CBUUID(string: "1826")
let TREADMILL_DATA = CBUUID(string: "2ACD")
let TRAINING_STATUS = CBUUID(string: "2AD3")
let SPEED_RANGE = CBUUID(string: "2AD4")
let CONTROL_POINT = CBUUID(string: "2AD9")

let KMH_PER_MPH = 1.6   // the firmware's conversion, not the true 1.609
let STEP_MPH = 0.2
let START_MPH = 1.4   // On ramps here unless a speed was set while stopped

func log(_ msg: String) {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Boardwalk.log")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

final class Treadmill: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var status = "Starting Bluetooth…"
    @Published var connected = false
    @Published var speedKmh = 0.0
    @Published var targetMph: Double? = nil   // what we last asked for, or will apply once ready
    @Published var minKmh = 0.8
    @Published var maxKmh = 6.4
    @Published var speedEntry = ""       // the "Set speed" text field

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var controlPoint: CBCharacteristic?
    private var ready = false            // belt is past the pre-workout countdown
    private var startedAt: Date?
    private var userDisconnected = false  // Disconnect pressed: stop auto-reconnecting

    var running: Bool { speedKmh > 0 }
    var speedMph: Double { speedKmh / KMH_PER_MPH }
    var minMph: Double { minKmh / KMH_PER_MPH }
    var maxMph: Double { maxKmh / KMH_PER_MPH }

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
        // Fallback in case Training Status notifications stop arriving.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, !self.ready, self.running, let t = self.startedAt,
                  Date().timeIntervalSince(t) > 3.5 else { return }
            self.becameReady()
        }
    }

    // MARK: commands

    func on() {
        guard connected else { return }
        write([0x00])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.write([0x07]) }
        ready = false
        startedAt = Date()
        if targetMph == nil { targetMph = START_MPH }   // applied once the countdown ends
        log("on")
    }

    func off() {
        guard connected else { return }
        write([0x08, 0x01])
        targetMph = nil
        log("off")
    }

    func faster() { step(+STEP_MPH) }
    func slower() { step(-STEP_MPH) }

    private func step(_ delta: Double) {
        guard running || startedAt != nil else { return }
        setSpeed(mph: (targetMph ?? speedMph) + delta)
    }

    /// Sets the target. Applied now if the belt is ready, otherwise queued until it is.
    func setSpeed(mph: Double) {
        let clamped = min(max(mph, minMph), maxMph)
        targetMph = (clamped * 10).rounded() / 10
        log("target \(targetMph!) mph")
        if ready && running { sendTarget() }
    }

    private func sendTarget() {
        guard let mph = targetMph else { return }
        let tenths = UInt16((mph * 10).rounded())   // treadmill steps are 0.1 mph = 0.16 km/h
        let v = min(max(tenths * 16, UInt16(minKmh * 100)), UInt16(maxKmh * 100))
        write([0x02, UInt8(v & 0xff), UInt8(v >> 8)])
    }

    private func becameReady() {
        ready = true
        startedAt = nil
        log("ready")
        sendTarget()
    }

    func connect() {
        userDisconnected = false
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        if central.state == .poweredOn { scan() }
        log("connect pressed")
    }

    func disconnect() {
        userDisconnected = true
        central.stopScan()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        connected = false
        controlPoint = nil
        speedKmh = 0
        status = "Disconnected"
        log("disconnect pressed")
    }

    private func write(_ bytes: [UInt8]) {
        guard let p = peripheral, let cp = controlPoint else { return }
        p.writeValue(Data(bytes), for: cp, type: .withResponse)
    }

    // MARK: Bluetooth

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: scan()
        case .unauthorized: status = "Bluetooth permission denied (System Settings › Privacy › Bluetooth)"
        case .poweredOff: status = "Bluetooth is off"
        default: status = "Bluetooth unavailable"
        }
    }

    private func scan() {
        status = "Looking for treadmill…"
        central.scanForPeripherals(withServices: [FTMS])
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        c.stopScan()
        guard !userDisconnected else { return }
        peripheral = p
        p.delegate = self
        status = "Connecting to \(p.name ?? "treadmill")…"
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log("connected \(p.name ?? "?")")
        p.discoverServices([FTMS])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("connect failed: \(error?.localizedDescription ?? "?")")
        if !userDisconnected { scan() }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("disconnected")
        connected = false
        controlPoint = nil
        speedKmh = 0
        if userDisconnected { status = "Disconnected"; return }
        status = "Reconnecting…"
        c.connect(p)   // pending connect; completes whenever the treadmill is back
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == FTMS }) else { return }
        p.discoverCharacteristics([TREADMILL_DATA, TRAINING_STATUS, SPEED_RANGE, CONTROL_POINT], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            switch ch.uuid {
            case CONTROL_POINT: controlPoint = ch; p.setNotifyValue(true, for: ch)
            case TREADMILL_DATA, TRAINING_STATUS: p.setNotifyValue(true, for: ch)
            case SPEED_RANGE: p.readValue(for: ch)
            default: break
            }
        }
        connected = controlPoint != nil
        status = connected ? "Connected" : "Treadmill has no control point"
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let d = ch.value, !d.isEmpty else { return }
        let b = [UInt8](d)
        switch ch.uuid {
        case TREADMILL_DATA where b.count >= 4 && b[0] & 0x01 == 0:
            let kmh = Double(UInt16(b[2]) | UInt16(b[3]) << 8) / 100
            if kmh != speedKmh { log(String(format: "belt %.2f km/h", kmh)) }
            if kmh == 0 && speedKmh > 0 { ready = false; startedAt = nil; targetMph = nil }
            speedKmh = kmh
        case TRAINING_STATUS where b.count >= 2:
            if b[1] == 0x0D && !ready { becameReady() }   // 0x0D = manual mode, belt accepts speed
        case SPEED_RANGE where b.count >= 4:
            minKmh = Double(UInt16(b[0]) | UInt16(b[1]) << 8) / 100
            maxKmh = Double(UInt16(b[2]) | UInt16(b[3]) << 8) / 100
        default: break
        }
    }
}

// MARK: UI

struct ControlView: View {
    @ObservedObject var t: Treadmill

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text(String(format: "%.1f", t.speedMph))
                    .font(.system(size: 44, weight: .semibold, design: .rounded)).monospacedDigit()
                Text(String(format: "mph  ·  %.1f km/h", t.speedKmh)).foregroundStyle(.secondary)
                if let target = t.targetMph, abs(target - t.speedMph) > 0.05 {
                    Text(String(format: "going to %.1f mph", target)).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button { t.on() } label: { Label("On", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .tint(.green)
                Button { t.off() } label: { Label("Off", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                    .tint(.red)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!t.connected)

            HStack(spacing: 10) {
                Button { t.slower() } label: { Image(systemName: "minus").frame(maxWidth: .infinity) }
                Button { t.faster() } label: { Image(systemName: "plus").frame(maxWidth: .infinity) }
            }
            .controlSize(.large)
            .disabled(!t.connected || !t.running)

            HStack {
                TextField("mph", text: $t.speedEntry).frame(width: 70).onSubmit(apply)
                Button("Set speed", action: apply)
                Spacer()
            }
            .disabled(!t.connected)

            Divider()
            HStack {
                Circle().fill(t.connected ? .green : .orange).frame(width: 8, height: 8)
                Text(t.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button(t.connected ? "Disconnect" : "Connect") {
                    t.connected ? t.disconnect() : t.connect()
                }
                .font(.caption)
                .disabled(t.running)   // don't drop control of a moving belt
            }
            Text(String(format: "Starts at %.1f mph · ± %.1f per press · max %.1f", START_MPH, STEP_MPH, t.maxMph))
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(width: 260)
    }

    private func apply() {
        if let v = Double(t.speedEntry) { t.setSpeed(mph: v) }
        t.speedEntry = ""
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let treadmill = Treadmill()

    /// One-time safety notice. Bump the key's version if the text changes materially.
    func applicationDidFinishLaunching(_ note: Notification) {
        let key = "acceptedSafetyNotice.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Before you use Boardwalk"
        alert.informativeText = """
            Boardwalk starts and changes the speed of a motorized belt, \
            including from shortcuts and automations.

            • Make sure nobody, including kids and pets, is on or near the treadmill when you press On.
            • Keep your treadmill's own stop button, safety key and power switch working, and know how to stop it without this app.
            • If Bluetooth drops, the belt may keep running.

            Boardwalk is unofficial, free software provided "as is" with no warranty. \
            You use it at your own risk. Palmetto Interactive LLC and its contributors \
            aren't liable for any injury, damage or loss. See the MIT License for full terms.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "I Understand")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            UserDefaults.standard.set(true, forKey: key)
        } else {
            NSApp.terminate(nil)
        }
    }

    func application(_ app: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "boardwalk" {
            log("url \(url.absoluteString)")
            switch url.host {
            case "on": treadmill.on()
            case "off": treadmill.off()
            case "faster": treadmill.faster()
            case "slower": treadmill.slower()
            case "speed":
                let mph = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "mph" })?.value.flatMap(Double.init)
                if let mph { treadmill.setSpeed(mph: mph) }
            default: break
            }
        }
    }
}

@main
struct BoardwalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("Boardwalk", id: "main") {
            ControlView(t: delegate.treadmill)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            ControlView(t: delegate.treadmill)
        } label: {
            MenuLabel(t: delegate.treadmill)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    @ObservedObject var t: Treadmill
    var body: some View {
        if t.running {
            Text(String(format: "🚶 %.1f", t.speedMph))
        } else {
            Image(systemName: t.connected ? "figure.walk" : "figure.walk.motion.trianglebadge.exclamationmark")
        }
    }
}

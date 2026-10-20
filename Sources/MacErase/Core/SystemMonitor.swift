import AppKit
import Foundation
import IOKit.ps
import Observation

struct BatteryInfo: Equatable {
    var percent: Int
    var isCharging: Bool
    var onAC: Bool
    var minutesRemaining: Int?
}

/// Lightweight sampler. It runs only while the window is visible (or the menu bar item is on, at a slower rate).
@MainActor @Observable
final class SystemMonitor {
    static let shared = SystemMonitor()

    private(set) var cpu: Double = 0
    /// False until the first real sample, so the UI shows a placeholder instead of a misleading zero.
    private(set) var hasSample = false
    private(set) var memoryUsed: Int64 = 0
    private(set) var memoryTotal: Int64 = Int64(ProcessInfo.processInfo.physicalMemory)
    private(set) var diskFree: Int64 = 0
    private(set) var diskTotal: Int64 = 0
    private(set) var battery: BatteryInfo?
    private(set) var netDown: Double = 0
    private(set) var netUp: Double = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var currentInterval: TimeInterval = 0
    @ObservationIgnored private var lastTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    @ObservationIgnored private var lastNet: (down: UInt64, up: UInt64, at: Date)?
    @ObservationIgnored private var lastDiskCheck = Date.distantPast
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var settingsSink: NSObjectProtocol?

    var memoryFraction: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) : 0 }
    var diskUsedFraction: Double { diskTotal > 0 ? 1 - Double(diskFree) / Double(diskTotal) : 0 }

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeOcclusionStateNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigure() }
        })
        settingsSink = center.addObserver(forName: .settingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigure() }
        }
        reconfigure()
    }

    func reconfigure() {
        let settings = AppSettings.shared
        let visible = NSApp.occlusionState.contains(.visible)
        let interval: TimeInterval? = visible ? settings.sampleInterval : (settings.showMenuBar ? 5 : nil)
        guard let interval else {
            timer?.invalidate(); timer = nil; currentInterval = 0
            return
        }
        guard interval != currentInterval || timer == nil else { return }
        timer?.invalidate()
        currentInterval = interval
        sample()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        t.tolerance = interval * 0.25
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleNetwork()
        // Assign only on change: every write to an observed property re-renders the widgets that read it.
        let newBattery = Self.readBattery()
        if newBattery != battery { battery = newBattery }
        if Date().timeIntervalSince(lastDiskCheck) > 30 { sampleDisk() }
        if lastTicks != nil, diskTotal > 0, !hasSample { hasSample = true }
    }

    private func sampleCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let now = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3)
        defer { lastTicks = now }
        guard let prev = lastTicks else { return }
        let user = Double(now.user &- prev.user), sys = Double(now.system &- prev.system)
        let idle = Double(now.idle &- prev.idle), nice = Double(now.nice &- prev.nice)
        let total = user + sys + idle + nice
        guard total > 0 else { return }
        let value = ((user + sys + nice) / total * 100).rounded()
        if value != cpu {
            cpu = value
        }
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = Int64(sysconf(_SC_PAGESIZE))
        let appPages = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
        let used = (max(appPages, 0) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        // Ignore sub-50 MB wobble so SwiftUI does not re-render for noise.
        if abs(used - memoryUsed) > 50_000_000 { memoryUsed = used }
    }

    private func sampleDisk() {
        lastDiskCheck = Date()
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        let free = v.volumeAvailableCapacityForImportantUsage ?? 0, total = Int64(v.volumeTotalCapacity ?? 0)
        if free != diskFree { diskFree = free }
        if total != diskTotal { diskTotal = total }
    }

    private func sampleNetwork() {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(ifap) }
        var down: UInt64 = 0, up: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let ifa = current.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data,
               String(cString: ifa.ifa_name).hasPrefix("en") {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(d.ifi_ibytes); up += UInt64(d.ifi_obytes)
            }
            cursor = ifa.ifa_next
        }
        let now = Date()
        defer { lastNet = (down, up, now) }
        guard let prev = lastNet else { return }
        let dt = now.timeIntervalSince(prev.at)
        guard dt > 0 else { return }
        let newDown = down >= prev.down ? Double(down - prev.down) / dt : 0
        let newUp = up >= prev.up ? Double(up - prev.up) / dt : 0
        if newDown != netDown { netDown = newDown }
        if newUp != netUp { netUp = newUp }
    }

    private static func readBattery() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType,
                  let current = desc[kIOPSCurrentCapacityKey] as? Int else { continue }
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let minutes = desc[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int
            return BatteryInfo(percent: max > 0 ? current * 100 / max : current, isCharging: charging, onAC: onAC,
                               minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil)
        }
        return nil
    }
}

// Bir sürecin boşta CPU ve uyanma sayısını dışarıdan ölçer (Activity Monitor'ün "Idle Wake Ups"
// sütununun kaynağı olan proc_pid_rusage ile). Ölçülen süreçte zamanlayıcı çalıştırmaz.
// Kullanım: swift Scripts/idle-probe.swift --name NotchPrototype --seconds 60
//           swift Scripts/idle-probe.swift --pid 1234 --seconds 60
import Darwin
import Foundation

struct Sample {
    let wall: UInt64
    let cpuNanoseconds: Double
    let idleWakeups: UInt64
    let interruptWakeups: UInt64
    let energyNanojoules: UInt64
}

func value(after flag: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: flag),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

func pid(named name: String) -> pid_t? {
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-x", name]
    process.standardOutput = pipe
    try? process.run()
    process.waitUntilExit()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return output.split(separator: "\n").first.flatMap { pid_t($0) }
}

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
let ticksToNanoseconds = Double(timebase.numer) / Double(timebase.denom)

func sample(_ pid: pid_t) -> Sample? {
    var info = rusage_info_v6()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V6, $0)
        }
    }
    guard result == 0 else { return nil }
    return Sample(wall: mach_absolute_time(),
                  cpuNanoseconds: Double(info.ri_user_time + info.ri_system_time) * ticksToNanoseconds,
                  idleWakeups: info.ri_pkg_idle_wkups,
                  interruptWakeups: info.ri_interrupt_wkups,
                  energyNanojoules: info.ri_energy_nj)
}

let seconds = Double(value(after: "--seconds") ?? "60") ?? 60
guard let target = value(after: "--pid").flatMap({ pid_t($0) })
        ?? pid(named: value(after: "--name") ?? "NotchPrototype") else {
    print("süreç bulunamadı")
    exit(1)
}
guard let first = sample(target) else {
    print("proc_pid_rusage başarısız (pid \(target))")
    exit(1)
}
Thread.sleep(forTimeInterval: seconds)
guard let last = sample(target) else {
    print("süreç ölçüm sırasında kapandı")
    exit(1)
}

let elapsed = Double(last.wall - first.wall) * ticksToNanoseconds / 1e9
let cpuPercent = (last.cpuNanoseconds - first.cpuNanoseconds) / (elapsed * 1e9) * 100
let idle = Double(last.idleWakeups - first.idleWakeups)
let interrupts = Double(last.interruptWakeups - first.interruptWakeups)
let energy = Double(last.energyNanojoules - first.energyNanojoules) / 1e9
print(String(format: "pid %d · %.1f sn · CPU %%%.3f · idle wakeups %.0f (%.2f/sn) · interrupt wakeups %.0f (%.2f/sn) · enerji %.4f J (%.2f mW)",
             target, elapsed, cpuPercent, idle, idle / elapsed, interrupts, interrupts / elapsed,
             energy, energy / elapsed * 1000))

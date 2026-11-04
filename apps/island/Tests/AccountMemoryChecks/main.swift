import Darwin
import Foundation

func footprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS, "Cannot read the test process memory footprint")
    return info.phys_footprint
}

let cli = URL(fileURLWithPath: CommandLine.arguments[1])
let target = min(1000, max(100, Int(ProcessInfo.processInfo.environment["ISLAND_MEMORY_CHECKPOINTS"] ?? "") ?? 100))
let reader = AccountReader(cli: cli, profile: "synthetic-island", pollDelay: 2, pageDelay: 0, clock: ServerClock())
var checkpoints = 0
var samples: [Int: UInt64] = [:]
reader.onCheckpoint = { _, _ in
    checkpoints += 1
    if [10, 40, 100, 200, 300, 500, 1000].contains(checkpoints) || checkpoints == target {
        samples[checkpoints] = footprint()
        print("checkpoint=\(checkpoints) footprint_mib=\(Double(samples[checkpoints]!) / 1048576)")
        fflush(stdout)
    }
}
reader.start()
let deadline = Date().addingTimeInterval(Double(target))
while checkpoints < target && Date() < deadline {
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
reader.stop()
guard checkpoints == target, let early = samples[40], let late = samples[100] else {
    fatalError("Synthetic backfill did not complete \(target) checkpoints (got \(checkpoints))")
}
let growth = late > early ? late - early : 0
print("growth_mib=\(Double(growth) / 1048576)")
var laterGrowth: UInt64?
if let final = samples[target], target > 100 {
    let value = final > late ? final - late : 0
    laterGrowth = value
    print("growth_after_100_mib=\(Double(value) / 1048576)")
}
if ProcessInfo.processInfo.environment["ISLAND_MEMORY_ENFORCE"] == "1" {
    precondition(growth < 8 * 1024 * 1024, "Backfill retained too much memory between checkpoints 40 and 100")
    if target >= 300, let laterGrowth {
        let limit = 8 * 1024 * 1024 * UInt64(target - 100) / 200
        precondition(laterGrowth < limit, "Backfill retained too much memory during the extended run")
    }
}

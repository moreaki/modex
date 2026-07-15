import Darwin
import Foundation

struct ProcessResourceSample: Sendable {
    let isAvailable: Bool
    let userTimeNanoseconds: UInt64
    let systemTimeNanoseconds: UInt64
    let currentMemoryBytes: UInt64
    let peakMemoryBytes: UInt64
    let physicalBytesRead: UInt64
    let physicalBytesWritten: UInt64
    let idleWakeups: UInt64
    let interruptWakeups: UInt64
    let voluntaryContextSwitches: Int64
    let involuntaryContextSwitches: Int64

    static let unavailable = ProcessResourceSample(
        isAvailable: false,
        userTimeNanoseconds: 0,
        systemTimeNanoseconds: 0,
        currentMemoryBytes: 0,
        peakMemoryBytes: 0,
        physicalBytesRead: 0,
        physicalBytesWritten: 0,
        idleWakeups: 0,
        interruptWakeups: 0,
        voluntaryContextSwitches: 0,
        involuntaryContextSwitches: 0
    )
}

struct ProcessResourceDelta: Sendable {
    let currentMemoryBytes: UInt64
    let peakMemoryBytes: UInt64
    let cpuTimeSeconds: Double
    let physicalBytesRead: UInt64
    let physicalBytesWritten: UInt64
    let idleWakeups: UInt64
    let interruptWakeups: UInt64
    let voluntaryContextSwitches: Int64
    let involuntaryContextSwitches: Int64

    static let unavailable = ProcessResourceDelta(
        currentMemoryBytes: 0,
        peakMemoryBytes: 0,
        cpuTimeSeconds: 0,
        physicalBytesRead: 0,
        physicalBytesWritten: 0,
        idleWakeups: 0,
        interruptWakeups: 0,
        voluntaryContextSwitches: 0,
        involuntaryContextSwitches: 0
    )
}

enum ProcessResourceSampler {
    static func sample() -> ProcessResourceSample {
        var processInfo = rusage_info_v4()
        let processResult = withUnsafeMutablePointer(to: &processInfo) { pointer in
            proc_pid_rusage(
                getpid(),
                RUSAGE_INFO_V4,
                UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self)
            )
        }

        var usage = rusage()
        let usageResult = getrusage(RUSAGE_SELF, &usage)
        guard processResult == 0, usageResult == 0 else {
            return .unavailable
        }

        return ProcessResourceSample(
            isAvailable: true,
            userTimeNanoseconds: nanoseconds(usage.ru_utime),
            systemTimeNanoseconds: nanoseconds(usage.ru_stime),
            currentMemoryBytes: processInfo.ri_phys_footprint,
            peakMemoryBytes: processInfo.ri_lifetime_max_phys_footprint,
            physicalBytesRead: processInfo.ri_diskio_bytesread,
            physicalBytesWritten: processInfo.ri_diskio_byteswritten,
            idleWakeups: processInfo.ri_pkg_idle_wkups,
            interruptWakeups: processInfo.ri_interrupt_wkups,
            voluntaryContextSwitches: Int64(usage.ru_nvcsw),
            involuntaryContextSwitches: Int64(usage.ru_nivcsw)
        )
    }

    static func delta(from start: ProcessResourceSample) -> ProcessResourceDelta {
        let end = sample()
        guard start.isAvailable, end.isAvailable else {
            return .unavailable
        }

        let cpuNanoseconds = difference(end.userTimeNanoseconds, start.userTimeNanoseconds)
            + difference(end.systemTimeNanoseconds, start.systemTimeNanoseconds)
        return ProcessResourceDelta(
            currentMemoryBytes: end.currentMemoryBytes,
            peakMemoryBytes: end.peakMemoryBytes,
            cpuTimeSeconds: Double(cpuNanoseconds) / 1_000_000_000,
            physicalBytesRead: difference(end.physicalBytesRead, start.physicalBytesRead),
            physicalBytesWritten: difference(end.physicalBytesWritten, start.physicalBytesWritten),
            idleWakeups: difference(end.idleWakeups, start.idleWakeups),
            interruptWakeups: difference(end.interruptWakeups, start.interruptWakeups),
            voluntaryContextSwitches: difference(
                end.voluntaryContextSwitches,
                start.voluntaryContextSwitches
            ),
            involuntaryContextSwitches: difference(
                end.involuntaryContextSwitches,
                start.involuntaryContextSwitches
            )
        )
    }

    private static func difference(_ end: UInt64, _ start: UInt64) -> UInt64 {
        end >= start ? end - start : 0
    }

    private static func difference(_ end: Int64, _ start: Int64) -> Int64 {
        end >= start ? end - start : 0
    }

    private static func nanoseconds(_ value: timeval) -> UInt64 {
        let seconds = max(0, value.tv_sec)
        let microseconds = max(0, value.tv_usec)
        return UInt64(seconds) * 1_000_000_000 + UInt64(microseconds) * 1_000
    }
}

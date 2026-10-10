import Darwin

enum ProcessLiveness {
    /// True when a process with this pid exists (EPERM: it exists but belongs to someone else).
    @Sendable
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}

import Foundation

/// Internal shared helper: runs a process, optionally feeding stdin, draining
/// stdout/stderr concurrently, and applying an optional watchdog. Shared by
/// `PortRunner` (reads) and `PrivilegeExecutor` (writes).
enum ProcessSpawner {
    struct Output: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    @discardableResult
    static func run(executable: String,
                   arguments: [String],
                   stdin: String? = nil,
                   workDir: URL = URL(fileURLWithPath: "/"),
                   timeout: TimeInterval? = nil,
                   extraEnvironment: [String: String]? = nil) throws -> Output {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.currentDirectoryURL = workDir
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        if let extraEnvironment {
            for (k, v) in extraEnvironment { env[k] = v }
        }
        p.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        if let stdin {
            let inPipe = Pipe()
            p.standardInput = inPipe
            let handle = inPipe.fileHandleForWriting
            handle.write(Data(stdin.utf8))
            try? handle.close()
        } else {
            p.standardInput = FileHandle.nullDevice
        }

        try p.run()

        var outData = Data()
        var errData = Data()
        let outSema = DispatchSemaphore(value: 0)
        let errSema = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            outSema.signal()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            errSema.signal()
        }

        if let timeout, timeout > 0 {
            let proc = p
            Thread.detachNewThread {
                Thread.sleep(forTimeInterval: timeout)
                if proc.isRunning { proc.terminate() }
            }
        }

        p.waitUntilExit()
        outSema.wait()
        errSema.wait()

        return Output(exitCode: p.terminationStatus,
                      stdout: String(data: outData, encoding: .utf8) ?? "",
                      stderr: String(data: errData, encoding: .utf8) ?? "")
    }
}

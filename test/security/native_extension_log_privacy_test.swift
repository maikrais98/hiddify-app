import Foundation

@main
struct NativeExtensionLogPrivacyTest {
    static func main() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("native-extension-log-privacy-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("network_extension_error.log")
        let log = NativeDiagnosticLog(fileURL: logURL)
        let canary = "PRIVATE_CANARY_7d91"
        let hostileMessage = "config={\"password\":\"\(canary)\"} url=https://user:\(canary)@vpn.example/path"
        let code = log.write(message: hostileMessage, severity: .error)
        precondition(code == .authenticationFailure)

        var contents = try String(contentsOf: logURL, encoding: .utf8)
        precondition(contents.contains("code=authentication_failure"))
        precondition(!contents.contains(canary))
        precondition(!contents.contains("https://"))
        precondition(!contents.contains("password"))

        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            _ = log.write(message: "timeout \(index) https://vpn.example/?token=\(canary)", severity: .error)
        }
        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        let size = attributes[.size] as? Int ?? Int.max
        precondition(size <= NativeDiagnosticLog.maxFileBytes)

        contents = try String(contentsOf: logURL, encoding: .utf8)
        precondition(!contents.contains(canary))
        precondition(contents.contains("code=log_rollover"))
        let allowedCodes = Set(NativeDiagnosticLog.Code.allCases.map(\.rawValue))
        for line in contents.split(separator: "\n") {
            precondition(line.utf8.count <= NativeDiagnosticLog.maxEntryBytes)
            guard let codeField = line.split(separator: " ").first(where: { $0.hasPrefix("code=") }) else {
                preconditionFailure("diagnostic entry has no code")
            }
            precondition(allowedCodes.contains(String(codeField.dropFirst("code=".count))))
        }

        log.reset()
        precondition(!fileManager.fileExists(atPath: logURL.path))
        print("native extension log privacy checks passed")
    }
}

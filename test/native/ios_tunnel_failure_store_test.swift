import Foundation

@main
struct NativeTunnelFailureStoreTest {
    static func main() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("native-tunnel-failure-store-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("failure.json")
        let store = NativeTunnelFailureStore(fileURL: fileURL)

        store.write(operationID: "550e8400-e29b-11d4-a716-446655440000", code: .unknownSafe)
        precondition(!fileManager.fileExists(atPath: fileURL.path))

        let operationID = "550e8400-e29b-41d4-a716-446655440000"
        store.write(operationID: operationID, code: .invalidConfiguration)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        let keys = object.map { Set($0.keys) } ?? Set<String>()
        precondition(keys == ["schema", "operation_id", "error_code"])
        precondition(object?["schema"] as? Int == 1)
        precondition(object?["operation_id"] as? String == operationID)
        precondition(object?["error_code"] as? String == "invalid_configuration")

        let failure = store.consume(expectedOperationID: operationID)
        precondition(failure?.operationID == operationID)
        precondition(failure?.code == .invalidConfiguration)
        precondition(!fileManager.fileExists(atPath: fileURL.path))

        store.write(
            operationID: "550e8400-e29b-41d4-a716-446655440001",
            code: .networkUnavailable
        )
        precondition(store.consume(expectedOperationID: operationID) == nil)
        precondition(!fileManager.fileExists(atPath: fileURL.path))

        let options = NativeTunnelStartOptions.make(
            config: "/shared/config.json",
            grpcServiceModePort: 17079,
            disableMemoryLimit: false,
            operationID: "550e8400-e29b-41d4-a716-446655440002"
        )
        precondition((options["OperationId"] as? NSString) == "550e8400-e29b-41d4-a716-446655440002")

        let diagnosticLog = NativeDiagnosticLog(
            fileURL: directory.appendingPathComponent("diagnostics.log")
        )
        precondition(
            diagnosticLog.write(message: "xPaddingBytes cannot be disabled", severity: .fault)
                == .configurationFailure
        )

        print("native tunnel failure store checks passed")
    }
}

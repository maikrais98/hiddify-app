import Foundation

private final class ToggleDiagnosticFileManager: FileManager, @unchecked Sendable {
    var failWrites = false
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        if failWrites { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError) }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

@main
struct NativeDiagnosticsPrivacyTest {
    static func main() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("native-diagnostics-privacy-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        try assertFailedRecordCannotCrossEnableBoundary(directory: directory)
        try assertFailureMarkerSurvivesUntilJournalCommit(directory: directory)

        let logURL = directory.appendingPathComponent("network_extension_error.log")
        let sidecarURL = directory.appendingPathComponent("extension-safe-diagnostics.json")
        let log = NativeDiagnosticLog(
            fileURL: logURL,
            source: .extension,
            structuredFileURL: sidecarURL
        )
        let canaries = [
            "PRIVATE_CREDENTIAL_CANARY_7d91",
            "11111111-2222-3333-4444-555555555555",
            "/private/var/mobile/Containers/Shared/AppGroup/PRIVATE_PATH",
            "PRIVATE_MULTILINE_CANARY",
        ]
        let hostileMessages = [
            "config={\"password\":\"\(canaries[0])\"} url=https://user:\(canaries[0])@vpn.example/path",
            "connection failed for uuid=\(canaries[1])",
            "cannot read file \(canaries[2])",
            "timeout\nseverity=fault code=forged \(canaries[3])",
            String(repeating: "native failure ", count: 2_000) + canaries[0],
        ]

        for message in hostileMessages {
            _ = log.write(message: message, severity: .error)
        }

        let boundedInput = String(repeating: "x", count: 4_096) + "password failed"
        precondition(log.write(message: boundedInput, severity: .info) == .nativeEvent,
                     "native classifier must inspect only a bounded input prefix")

        var contents = try String(contentsOf: logURL, encoding: .utf8)
        assertClosed(contents, canaries: canaries)

        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            _ = log.write(
                message: "timeout \(index) https://vpn.example/?token=\(canaries[0])",
                severity: .error
            )
        }

        let attributes = try fileManager.attributesOfItem(atPath: logURL.path)
        let size = attributes[.size] as? Int ?? Int.max
        precondition(size <= NativeDiagnosticLog.maxFileBytes, "native diagnostic file exceeded its cap")

        contents = try String(contentsOf: logURL, encoding: .utf8)
        assertClosed(contents, canaries: canaries)
        precondition(contents.contains("code=log_rollover"), "bounded log did not record rollover")

        log.record(
            stage: .state,
            code: .noError,
            nativeStatus: .connected
        )
        log.record(stage: .requested, code: .unknown, phase: .wake)
        log.record(stage: .accepted, code: .noError, phase: .wake)
        log.record(
            stage: .failed,
            code: .unexpected,
            phase: .lastDisconnectError,
            error: NSError(
                domain: "PRIVATE_DOMAIN_\(canaries[0])",
                code: 44,
                userInfo: [NSLocalizedDescriptionKey: canaries[3]]
            )
        )

        let firstSnapshot = log.snapshot()
        assertStructuredSnapshot(firstSnapshot, source: "extension")
        let structuredBytes = try Data(contentsOf: sidecarURL)
        let structuredText = String(decoding: structuredBytes, as: UTF8.self)
        assertNoCanaries(structuredText, canaries: canaries)
        precondition(!structuredText.contains("PRIVATE_DOMAIN"), "arbitrary NSError domain reached sidecar")
        precondition(!structuredText.contains("userInfo"), "NSError userInfo reached sidecar")
        precondition(!structuredText.contains("description"), "NSError description reached sidecar")

        let reopened = NativeDiagnosticLog(
            fileURL: logURL,
            source: .extension,
            structuredFileURL: sidecarURL
        )
        let reopenedSnapshot = reopened.snapshot()
        precondition(
            reopenedSnapshot["generation"] as? String == firstSnapshot["generation"] as? String,
            "journal generation must survive restart"
        )
        reopened.record(stage: .accepted, code: .noError, phase: .sleep)
        let nextSnapshot = reopened.snapshot()
        precondition(
            (nextSnapshot["last_sequence"] as? Int ?? 0) > (firstSnapshot["last_sequence"] as? Int ?? 0),
            "source sequence must increase across restart"
        )

        for _ in 0..<200 {
            reopened.record(stage: .state, code: .noError, nativeStatus: .reasserting)
        }
        let boundedSnapshot = reopened.snapshot()
        let boundedRecords = boundedSnapshot["records"] as? [[String: Any]] ?? []
        precondition(boundedRecords.count <= 128, "structured journal exceeded record cap")
        let boundedSidecarData = try Data(contentsOf: sidecarURL)
        precondition(
            boundedSidecarData.count <= NativeDiagnosticLog.maxStructuredFileBytes,
            "structured journal exceeded byte cap"
        )
        precondition((boundedSnapshot["dropped_count"] as? Int ?? 0) > 0, "structured overflow was not reported")

        let normalURL = directory.appendingPathComponent("normal-capacity.json")
        let normal = NativeDiagnosticLog(
            fileURL: directory.appendingPathComponent("normal.log"),
            source: .runner,
            structuredFileURL: normalURL
        )
        for status in [
            NativeDiagnosticStatus.invalid, .disconnected, .connecting,
            .connected, .reasserting, .disconnecting,
        ] {
            normal.record(stage: .state, code: .noError, nativeStatus: status)
        }
        for phase in [
            NativeDiagnosticPhase.preferencesLoad, .preferencesSave, .preferencesReload,
        ] {
            normal.record(stage: .requested, code: .none, phase: phase)
            normal.record(stage: .accepted, code: .noError, phase: phase)
        }
        let normalRecords = (normal.snapshot()["records"] as? [[String: Any]])?.count ?? 0
        let normalBytes = try Data(contentsOf: normalURL).count
        precondition(normalRecords == 12, "normal capacity episode lost records")
        precondition(normalBytes <= NativeDiagnosticLog.maxStructuredFileBytes, "normal capacity episode exceeded byte cap")

        let failureURL = directory.appendingPathComponent("failure-capacity.json")
        let failure = NativeDiagnosticLog(
            fileURL: directory.appendingPathComponent("failure.log"),
            source: .runner,
            structuredFileURL: failureURL
        )
        failure.record(stage: .state, code: .noError, nativeStatus: .disconnected)
        failure.record(stage: .requested, code: .none, phase: .preferencesLoad)
        failure.record(
            stage: .failed,
            code: .unexpected,
            phase: .preferencesLoad,
            error: NSError(domain: NSPOSIXErrorDomain, code: 5)
        )
        failure.record(stage: .requested, code: .none, phase: .lastDisconnectError)
        failure.record(
            stage: .failed,
            code: .unexpected,
            phase: .lastDisconnectError,
            error: NSError(domain: NSPOSIXErrorDomain, code: 54)
        )
        let failureRecords = (failure.snapshot()["records"] as? [[String: Any]])?.count ?? 0
        let failureBytes = try Data(contentsOf: failureURL).count
        precondition(failureRecords == 5, "failure capacity episode lost records")
        precondition(failureBytes <= NativeDiagnosticLog.maxStructuredFileBytes, "failure capacity episode exceeded byte cap")
        print(
            "capacity normal_records=\(normalRecords)/128 normal_bytes=\(normalBytes)/65536 " +
            "failure_records=\(failureRecords)/128 failure_bytes=\(failureBytes)/65536 " +
            "overflow_dropped=\(boundedSnapshot["dropped_count"] as? Int ?? 0)"
        )

        let runnerURL = directory.appendingPathComponent("runner-safe-diagnostics.json")
        let runner = NativeDiagnosticLog(fileURL: directory.appendingPathComponent("runner.log"), source: .runner, structuredFileURL: runnerURL)
        runner.record(stage: .state, code: .noError, nativeStatus: .connecting)
        let bridgeBefore = NativeDiagnosticLog.bridgeSnapshot(runnerURL: runnerURL, extensionURL: sidecarURL)
        let bridgeAfter = NativeDiagnosticLog.bridgeSnapshot(runnerURL: runnerURL, extensionURL: sidecarURL)
        precondition(bridgeBefore["version"] as? Int == 1, "bridge version is not closed")
        precondition((bridgeBefore["sources"] as? [[String: Any]])?.count == 2, "bridge must return exactly two sources")
        let beforeData = try JSONSerialization.data(withJSONObject: bridgeBefore, options: [.sortedKeys])
        let afterData = try JSONSerialization.data(withJSONObject: bridgeAfter, options: [.sortedKeys])
        precondition(beforeData == afterData, "bridge read must be non-destructive")

        log.reset()
        precondition(!fileManager.fileExists(atPath: logURL.path), "reset must remove the prior lifecycle log")
        precondition(fileManager.fileExists(atPath: sidecarURL.path), "legacy reset must preserve structured history")

        let invalidParent = directory.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: invalidParent)
        let unwritableLog = NativeDiagnosticLog(fileURL: invalidParent.appendingPathComponent("diagnostic.log"))
        let returnedCode = unwritableLog.write(message: hostileMessages[0], severity: .fault)
        precondition(returnedCode == .authenticationFailure, "logging failure changed diagnostic classification")

        print("native diagnostics privacy checks passed")
    }

    private static func assertFailedRecordCannotCrossEnableBoundary(directory: URL) throws {
        let manager = ToggleDiagnosticFileManager()
        let sidecar = directory.appendingPathComponent("failed-write-consent.json")
        let log = NativeDiagnosticLog(fileURL: directory.appendingPathComponent("failed-write.log"),
                                      source: .extension, structuredFileURL: sidecar, fileManager: manager)
        log.record(stage: .state, code: .noError, nativeStatus: .connected)
        manager.failWrites = true
        log.record(stage: .requested, code: .unknown, phase: .sleep)
        let oldDisk = NativeDiagnosticLog.snapshot(at: sidecar, source: .extension)
        precondition(oldDisk["last_sequence"] as? Int == 1, "failed write changed committed baseline")
        manager.failWrites = false
        log.record(stage: .accepted, code: .noError, phase: .wake)
        let recovered = NativeDiagnosticLog.snapshot(at: sidecar, source: .extension)
        let records = recovered["records"] as? [[String: Any]] ?? []
        let events = records.compactMap { $0["event"] as? [String: Any] }
        precondition(!events.contains { $0["phase"] as? String == "sleep" },
                     "failed OFF event must never flush across a later consent baseline")
        precondition(events.contains { $0["phase"] as? String == "wake" }, "fresh recovered event missing")
        precondition(recovered["last_sequence"] as? Int == 2, "never-committed sequence must be reused")
        precondition(recovered["dropped_count"] as? Int == 1, "failed record loss must be counted")
        precondition(recovered["storage_failed"] as? Bool == true, "failure must remain explicit")
        precondition(records.compactMap { $0["source_sequence"] as? Int } == [1, 2], "retained records must stay contiguous")
    }

    private static func assertFailureMarkerSurvivesUntilJournalCommit(directory: URL) throws {
        let suite = "native-diagnostic-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let marker = "blizzard.native-diagnostic.storage-failed.v1.extension"
        let manager = ToggleDiagnosticFileManager()
        let sidecar = directory.appendingPathComponent("failure-marker.json")
        let logURL = directory.appendingPathComponent("failure-marker.log")
        let log = NativeDiagnosticLog(fileURL: logURL, source: .extension, structuredFileURL: sidecar,
                                      fileManager: manager, failureDefaults: defaults)
        log.record(stage: .state, code: .noError, nativeStatus: .connected)
        manager.failWrites = true
        log.record(stage: .requested, code: .unknown, phase: .sleep)
        precondition(defaults.bool(forKey: marker), "last-write failure marker missing")
        precondition(NativeDiagnosticLog.snapshot(at: sidecar, source: .extension)["storage_failed"] as? Bool == false,
                     "failure injection must leave the prior valid file untouched")
        let runnerURL = directory.appendingPathComponent("marker-runner.json")
        let bridge = NativeDiagnosticLog.bridgeSnapshot(runnerURL: runnerURL, extensionURL: sidecar,
                                                        failureDefaults: defaults)
        let extensionState = (bridge["sources"] as? [[String: Any]])?.first { $0["source"] as? String == "extension" }
        precondition(extensionState?["storage_failed"] as? Bool == true, "bridge missed last-write failure")
        let reopened = NativeDiagnosticLog(fileURL: logURL, source: .extension, structuredFileURL: sidecar,
                                           fileManager: manager, failureDefaults: defaults)
        precondition(reopened.snapshot()["storage_failed"] as? Bool == true, "restart lost pending failure")
        reopened.record(stage: .requested, code: .unknown, phase: .sleep)
        precondition(defaults.bool(forKey: marker), "failed retry cleared marker before journal commit")
        manager.failWrites = false
        log.record(stage: .accepted, code: .noError, phase: .wake)
        precondition(defaults.object(forKey: marker) == nil, "committed failure marker was not cleared")
        let persisted = NativeDiagnosticLog.snapshot(at: sidecar, source: .extension)
        precondition(persisted["storage_failed"] as? Bool == true, "marker cleared without committed failure flag")
        let events = (persisted["records"] as? [[String: Any]] ?? []).compactMap { $0["event"] as? [String: Any] }
        precondition(!events.contains { $0["phase"] as? String == "sleep" }, "failed OFF payload survived marker recovery")
    }

    private static func assertStructuredSnapshot(_ snapshot: [String: Any], source: String) {
        let expectedKeys: Set<String> = ["source", "generation", "first_sequence", "last_sequence", "dropped_count", "storage_failed", "records"]
        precondition(Set(snapshot.keys) == expectedKeys, "snapshot contains fields outside the closed bridge contract")
        precondition(snapshot["source"] as? String == source, "snapshot source is not closed")
        let generation = snapshot["generation"] as? String ?? ""
        precondition(generation.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil,
                     "snapshot generation is not 16 lowercase hex")
        let records = snapshot["records"] as? [[String: Any]] ?? []
        precondition(!records.isEmpty, "structured journal did not retain records")
        for record in records {
            let sourceSequence = record["source_sequence"] as? Int ?? 0
            let event = record["event"] as? [String: Any] ?? [:]
            precondition(sourceSequence > 0, "source sequence must be positive")
            precondition(event["sequence"] as? Int == sourceSequence, "wire sequence must equal source sequence")
            precondition(event["operation_id"] as? Int == 0, "native operation id must be zero")
            precondition(event["operation"] as? String == "native", "native operation must be closed")
            precondition(event["reachability"] as? String == "not_checked", "native reachability must be closed")
        }

        assertCorruptedDocumentRejected(snapshot, source: source, message: "corrupt event vocabulary was not rejected") {
            $0["operation"] = "PRIVATE_UNTRUSTED_OPERATION"
        }
        assertCorruptedDocumentRejected(snapshot, source: source, message: "out-of-range stop reason was not rejected") {
            $0["stop_reason"] = 256
        }
        assertCorruptedDocumentRejected(snapshot, source: source, message: "unpaired error code was not rejected") {
            $0["error_code"] = 7
            $0.removeValue(forKey: "error_domain")
        }
    }

    private static func assertCorruptedDocumentRejected(
        _ snapshot: [String: Any],
        source: String,
        message: String,
        mutate: (inout [String: Any]) -> Void
    ) {
        guard var corrupted = (snapshot["records"] as? [[String: Any]])?.first,
              var event = corrupted["event"] as? [String: Any] else {
            preconditionFailure("structured snapshot has no record to corrupt")
        }
        mutate(&event)
        corrupted["event"] = event
        var document = snapshot
        document.removeValue(forKey: "first_sequence")
        document["version"] = 1
        document["records"] = [corrupted]
        let data = try! JSONSerialization.data(withJSONObject: document)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-native-sidecar-\(UUID().uuidString).json")
        try! data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let rejected = NativeDiagnosticLog.snapshot(at: url, source: source == "extension" ? .extension : .runner)
        precondition(rejected["storage_failed"] as? Bool == true, message)
        precondition((rejected["records"] as? [[String: Any]])?.isEmpty == true, "corrupt record crossed the bridge")
    }

    private static func assertNoCanaries(_ contents: String, canaries: [String]) {
        for canary in canaries {
            precondition(!contents.contains(canary), "private canary reached structured diagnostic output")
        }
    }

    private static func assertClosed(_ contents: String, canaries: [String]) {
        for canary in canaries {
            precondition(!contents.contains(canary), "private canary reached native diagnostic output")
        }
        precondition(!contents.contains("https://"), "URL reached native diagnostic output")
        precondition(!contents.contains("password"), "credential key reached native diagnostic output")
        precondition(!contents.contains("config="), "configuration reached native diagnostic output")

        let allowedCodes = Set(NativeDiagnosticLog.Code.allCases.map(\.rawValue))
        let allowedSeverities = Set(NativeDiagnosticSeverity.allCases.map(\.rawValue))
        for line in contents.split(separator: "\n") {
            precondition(line.utf8.count <= NativeDiagnosticLog.maxEntryBytes, "diagnostic entry exceeded its cap")
            let fields = line.split(separator: " ")
            precondition(fields.count == 3, "diagnostic entry is not closed structured data")
            precondition(fields[0].hasPrefix("timestamp="), "diagnostic entry has no timestamp")
            guard let severityField = fields.first(where: { $0.hasPrefix("severity=") }) else {
                preconditionFailure("diagnostic entry has no severity")
            }
            guard let codeField = fields.first(where: { $0.hasPrefix("code=") }) else {
                preconditionFailure("diagnostic entry has no code")
            }
            let severity = String(severityField.dropFirst("severity=".count))
            let code = String(codeField.dropFirst("code=".count))
            precondition(allowedSeverities.contains(severity), "diagnostic severity is not allowlisted")
            precondition(allowedCodes.contains(code), "diagnostic code is not allowlisted")
        }
    }
}

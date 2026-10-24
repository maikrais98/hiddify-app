import Darwin
import Foundation
import NetworkExtension

@main
struct VPNManagerManualPolicyTests {
    private static var failureCount = 0

    static func main() async {
        await existingProfileIsMadeManualBeforeExplicitStart()
        await newlyCreatedProfileIsMadeManualBeforeExplicitStart()
        await disconnectKeepsManualPolicyAndStopsTunnel()
        await setupFailurePreventsStart(operation: "load-all")
        await setupFailurePreventsStart(operation: "save")
        await setupFailurePreventsStart(operation: "load")
        await policyFailurePreventsStart(operation: "save")
        await policyFailurePreventsStart(operation: "load")
        await startFailureIsReported()
        await retryAfterPolicySaveFailureCanStart()
        await setupRecoversSystemStatus()
        await statusRefreshDoesNotCreateAProfile()
        await statusRefreshReportsLoadFailure()
        await statusNotificationsIgnoreForeignConnectionsAndKeepAllNativeStates()
        await preferencesEmitRequestedAndCompletedStages()
        await disconnectErrorNilAndStaleCallbacksAreClosed()

        if failureCount == 0 {
            print("PASS: VPNManager manual system control behavior")
            exit(EXIT_SUCCESS)
        }
        print("FAIL: \(failureCount) assertion(s)")
        exit(EXIT_FAILURE)
    }

    private static func existingProfileIsMadeManualBeforeExplicitStart() async {
        let persisted = seededOnDemandManager()
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])

        do {
            let subject = VPNManager()
            try await subject.setup()
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)

            expectManualPolicyWasSavedBeforeStart("existing profile")
            expect(FakeNetworkExtensionState.startCount == 1, "existing profile: explicit manual start still occurs")
            expect(
                FakeNetworkExtensionState.lastStartOptions?["Config"] as? String == "/safe/config.json",
                "existing profile: explicit start keeps the selected config"
            )
        } catch {
            fail("existing profile: unexpected error \(error)")
        }
    }

    private static func newlyCreatedProfileIsMadeManualBeforeExplicitStart() async {
        FakeNetworkExtensionState.reset()

        do {
            let subject = VPNManager()
            try await subject.setup()
            try await subject.connect(with: "/safe/new-config.json", grpcServiceModePort: 17079)

            expectManualPolicyWasSavedBeforeStart("new profile")
            expect(FakeNetworkExtensionState.startCount == 1, "new profile: explicit manual start still occurs")
        } catch {
            fail("new profile: unexpected error \(error)")
        }
    }

    private static func disconnectKeepsManualPolicyAndStopsTunnel() async {
        let persisted = seededOnDemandManager()
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])

        do {
            let subject = VPNManager()
            try await subject.setup()
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
            subject.disconnect()

            expect(FakeNetworkExtensionState.stopCount == 1, "disconnect: tunnel is explicitly stopped")
            expect(persisted.isOnDemandEnabled == false, "disconnect: On Demand remains disabled")
            expect((persisted.onDemandRules ?? []).isEmpty, "disconnect: On Demand rules remain empty")
        } catch {
            fail("disconnect: unexpected error \(error)")
        }
    }

    private static func seededOnDemandManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        manager.isEnabled = true
        manager.isOnDemandEnabled = true
        manager.onDemandRules = [NEOnDemandRuleConnect()]
        return manager
    }

    private static func setupRecoversSystemStatus() async {
        for status: NEVPNStatus in [.disconnected, .connecting, .connected, .reasserting, .disconnecting] {
            let persisted = seededOnDemandManager()
            persisted.connection.status = status
            FakeNetworkExtensionState.reset(loadedManagers: [persisted])
            let subject = VPNManager()
            do {
                try await subject.setup()
                expect(subject.state == status, "setup: existing system status is recovered")
                persisted.connection.status = .disconnected
                try await subject.setup()
                expect(subject.state == .disconnected, "resume: external system stop replaces old status")
                expect(FakeNetworkExtensionState.startCount == 0, "status: reading status never starts tunnel")
                expect(FakeNetworkExtensionState.saveSnapshots.isEmpty, "status: existing profile is not rewritten")
            } catch {
                fail("status: unexpected setup failure")
            }
        }
    }

    private static func statusRefreshDoesNotCreateAProfile() async {
        let persisted = seededOnDemandManager()
        persisted.connection.status = .connected
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        let subject = VPNManager()
        do {
            let connected = try await subject.refreshStatus()
            expect(connected == .connected, "refresh: connected system tunnel is recovered")
            FakeNetworkExtensionState.loadedManagers = []
            let missing = try await subject.refreshStatus()
            expect(missing == .invalid, "refresh: deleted system profile clears stale status")
            expect(FakeNetworkExtensionState.saveSnapshots.isEmpty, "refresh: no profile is created or rewritten")
            expect(FakeNetworkExtensionState.startCount == 0, "refresh: tunnel is never started")
        } catch {
            fail("refresh: unexpected failure")
        }
    }

    private static func statusRefreshReportsLoadFailure() async {
        let persisted = seededOnDemandManager()
        persisted.connection.status = .connected
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        let subject = VPNManager()
        do {
            _ = try await subject.refreshStatus()
            let failure = NSError(domain: "test.vpn.status", code: 5)
            FakeNetworkExtensionState.loadAllError = failure
            do {
                _ = try await subject.refreshStatus()
                fail("refresh: load failure must reach caller")
            } catch {
                expect((error as NSError) === failure, "refresh: original failure reaches caller")
                expect(subject.state == .connected, "refresh: load failure does not invent disconnected state")
            }
        } catch {
            fail("refresh: unexpected initial failure")
        }
    }

    private static func statusNotificationsIgnoreForeignConnectionsAndKeepAllNativeStates() async {
        resetNativeDiagnostics()
        let persisted = seededOnDemandManager()
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        let subject = VPNManager()
        do {
            try await subject.setup()
            let foreign = NETunnelProviderSession()
            foreign.status = .connected
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: foreign)
            expect(subject.state != .connected, "status notification: foreign connection is ignored")

            let statuses: [NEVPNStatus] = [.invalid, .disconnected, .connecting, .connected, .reasserting, .disconnecting]
            for status in statuses {
                persisted.connection.status = status
                NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: persisted.connection)
                expect(subject.state == status, "status notification: current connection preserves \(status)")
            }
            let names = nativeEvents().compactMap { $0["native_status"] as? String }
            expect(names.suffix(6).elementsEqual(["invalid", "disconnected", "connecting", "connected", "reasserting", "disconnecting"]),
                   "status notification: all six native statuses remain distinct")
            let liveRecords = subject.safeDiagnosticSnapshot()["records"] as? [[String: Any]] ?? []
            expect(!liveRecords.isEmpty, "status notification: live runner snapshot exposes in-memory writer state")
        } catch {
            fail("status notification: unexpected error \(error)")
        }
    }

    private static func preferencesEmitRequestedAndCompletedStages() async {
        resetNativeDiagnostics()
        FakeNetworkExtensionState.reset(loadedManagers: [seededOnDemandManager()])
        let subject = VPNManager()
        do {
            try await subject.setup()
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
            let stages = nativeEvents().compactMap { event -> String? in
                guard let phase = event["phase"] as? String, phase.hasPrefix("preferences") else { return nil }
                return "\(phase):\(event["stage"] as? String ?? "")"
            }
            expect(stages.contains("preferencesLoad:requested"), "preferences: load requested is observed")
            expect(stages.contains("preferencesLoad:accepted"), "preferences: load completion is observed")
            expect(stages.contains("preferencesSave:requested"), "preferences: save requested is observed")
            expect(stages.contains("preferencesSave:accepted"), "preferences: save completion is observed")
            expect(stages.contains("preferencesReload:requested"), "preferences: reload requested is observed")
            expect(stages.contains("preferencesReload:accepted"), "preferences: reload completion is observed")
        } catch {
            fail("preferences: unexpected error \(error)")
        }
    }

    private static func disconnectErrorNilAndStaleCallbacksAreClosed() async {
        resetNativeDiagnostics()
        let persisted = seededOnDemandManager()
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        let subject = VPNManager()
        do {
            try await subject.setup()
            persisted.connection.status = .connected
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: persisted.connection)
            persisted.connection.status = .disconnected
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: persisted.connection)
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: persisted.connection)
            expect(FakeNetworkExtensionState.pendingDisconnectErrorCallbacks.count == 1,
                   "disconnect error: only a transition to disconnected fetches")
            guard !FakeNetworkExtensionState.pendingDisconnectErrorCallbacks.isEmpty else { return }
            FakeNetworkExtensionState.pendingDisconnectErrorCallbacks.removeFirst()(nil)

            persisted.connection.status = .connected
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: persisted.connection)
            persisted.connection.status = .disconnected
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: persisted.connection)
            guard !FakeNetworkExtensionState.pendingDisconnectErrorCallbacks.isEmpty else {
                fail("disconnect error: second disconnect did not fetch")
                return
            }
            let stale = FakeNetworkExtensionState.pendingDisconnectErrorCallbacks.removeFirst()
            persisted.connection.status = .connecting
            NotificationCenter.default.post(name: .NEVPNStatusDidChange, object: persisted.connection)
            stale(NSError(domain: NEVPNConnectionErrorDomain, code: 7, userInfo: [NSLocalizedDescriptionKey: "PRIVATE_STALE_CANARY"]))

            let events = nativeEvents().filter { $0["phase"] as? String == "lastDisconnectError" }
            expect(events.contains { $0["code"] as? String == "noError" }, "disconnect error: nil is recorded without fabrication")
            expect(events.contains { $0["code"] as? String == "stale" }, "disconnect error: stale callback is rejected explicitly")
            let encoded = String(data: try JSONSerialization.data(withJSONObject: events), encoding: .utf8) ?? ""
            expect(!encoded.contains("PRIVATE_STALE_CANARY"), "disconnect error: private description is never serialized")
            expect(!events.contains { $0["error_code"] != nil }, "disconnect error: stale NSError fields are omitted")
        } catch {
            fail("disconnect error: unexpected error \(error)")
        }
    }

    private static func resetNativeDiagnostics() {
        try? FileManager.default.removeItem(at: FilePath.workingDirectory)
        try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
    }

    private static func nativeEvents() -> [[String: Any]] {
        let snapshot = NativeDiagnosticLog.snapshot(
            at: FilePath.workingDirectory.appendingPathComponent("runner-safe-diagnostics.json"),
            source: .runner
        )
        let records = snapshot["records"] as? [[String: Any]] ?? []
        return records.compactMap { $0["event"] as? [String: Any] }
    }

    private static func setupFailurePreventsStart(operation: String) async {
        resetNativeDiagnostics()
        FakeNetworkExtensionState.reset()
        let error = NSError(domain: "test.vpn.preferences", code: 1)
        switch operation {
        case "load-all": FakeNetworkExtensionState.loadAllError = error
        case "save": FakeNetworkExtensionState.saveError = error
        default: FakeNetworkExtensionState.loadError = error
        }
        let subject = VPNManager()
        var reportedError: NSError?
        do {
            try await subject.setup()
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
        } catch {
            reportedError = error as NSError
        }
        expect(reportedError === error, "setup \(operation): original failure reaches caller")
        expect(FakeNetworkExtensionState.startCount == 0, "setup \(operation): tunnel is not started")
        let expectedPhase = operation == "load-all" ? "preferencesLoad" : operation == "save" ? "preferencesSave" : "preferencesReload"
        expect(nativeEvents().contains { $0["stage"] as? String == "failed" && $0["phase"] as? String == expectedPhase },
               "setup \(operation): exact failed preference stage is observed")
    }

    private static func policyFailurePreventsStart(operation: String) async {
        resetNativeDiagnostics()
        FakeNetworkExtensionState.reset(loadedManagers: [seededOnDemandManager()])
        let subject = VPNManager()
        do {
            try await subject.setup()
        } catch {
            fail("policy \(operation): unexpected setup failure")
            return
        }
        let error = NSError(domain: "test.vpn.preferences", code: 2)
        if operation == "save" {
            FakeNetworkExtensionState.saveError = error
        } else {
            FakeNetworkExtensionState.loadError = error
        }
        var reportedError: NSError?
        do {
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
        } catch {
            reportedError = error as NSError
        }
        expect(reportedError === error, "policy \(operation): original failure reaches caller")
        expect(FakeNetworkExtensionState.startCount == 0, "policy \(operation): tunnel is not started")
        let expectedPhase = operation == "save" ? "preferencesSave" : "preferencesReload"
        expect(nativeEvents().contains { $0["stage"] as? String == "failed" && $0["phase"] as? String == expectedPhase },
               "policy \(operation): exact failed preference stage is observed")
    }

    private static func startFailureIsReported() async {
        FakeNetworkExtensionState.reset(loadedManagers: [seededOnDemandManager()])
        let subject = VPNManager()
        let failure = NSError(domain: "test.vpn.start", code: 3)
        do {
            try await subject.setup()
            FakeNetworkExtensionState.startError = failure
            do {
                try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
                fail("start: rejected command must not return success")
            } catch {
                expect((error as NSError) === failure, "start: original failure reaches caller")
            }
            expect(FakeNetworkExtensionState.startCount == 1, "start: only one start is attempted")
        } catch {
            fail("start: unexpected setup failure")
        }
    }

    private static func retryAfterPolicySaveFailureCanStart() async {
        FakeNetworkExtensionState.reset(loadedManagers: [seededOnDemandManager()])
        let subject = VPNManager()
        do {
            try await subject.setup()
            FakeNetworkExtensionState.saveError = NSError(domain: "test.vpn.preferences", code: 4)
            do {
                try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
                fail("retry: failed first attempt must report failure")
            } catch {}
            FakeNetworkExtensionState.saveError = nil
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
            expect(FakeNetworkExtensionState.startCount == 1, "retry: only successful attempt starts tunnel")
            expectManualPolicyWasSavedBeforeStart("retry")
        } catch {
            fail("retry: unexpected error")
        }
    }

    private static func expectManualPolicyWasSavedBeforeStart(_ context: String) {
        guard let startIndex = FakeNetworkExtensionState.events.firstIndex(of: "start") else {
            fail("\(context): missing explicit start")
            return
        }
        guard let saveIndex = FakeNetworkExtensionState.events[..<startIndex].lastIndex(of: "save") else {
            fail("\(context): policy was not saved before start")
            return
        }

        let snapshotIndex = FakeNetworkExtensionState.events[..<saveIndex].filter { $0 == "save" }.count
        guard FakeNetworkExtensionState.saveSnapshots.indices.contains(snapshotIndex) else {
            fail("\(context): missing saved policy snapshot")
            return
        }
        let snapshot = FakeNetworkExtensionState.saveSnapshots[snapshotIndex]
        expect(snapshot.isEnabled, "\(context): VPN manager remains enabled")
        expect(snapshot.isOnDemandEnabled == false, "\(context): saved policy disables On Demand")
        expect(snapshot.onDemandRuleCount == 0, "\(context): saved policy clears On Demand rules")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func fail(_ message: String) {
        failureCount += 1
        print("ASSERTION FAILED: \(message)")
    }
}

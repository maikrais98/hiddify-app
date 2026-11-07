import Darwin
import Foundation
import NetworkExtension

@main
struct VPNManagerManualPolicyTests {
    private static var failureCount = 0

    static func main() async {
        // Defaults belong to this throwaway test process, never to the installed app.
        UserDefaults.standard.removeObject(forKey: "VPN.AlwaysOn")
        expect(!VPNConfig.shared.alwaysOn, "configuration: official always-on default is false")
        await staleSaveReloadsAndReappliesPolicy()
        await overlappingRefreshWaitsForSave()
        await foreignProviderIsUntouched()
        await disconnectSaveIsSerialized()
        await successfulResetRemovesOnlyOwnProvider()
        await resetPolicySaveFailureDoesNotStopOrDelete()
        await existingProfileIsMadeManualBeforeExplicitStart()
        await newlyCreatedProfileIsMadeManualBeforeExplicitStart()
        await disconnectKeepsManualPolicyAndStopsTunnel()
        for operation in ["load-all", "save", "load"] { await setupFailurePreventsStart(operation: operation) }
        for operation in ["save", "load"] { await policyFailurePreventsStart(operation: operation) }
        await startFailureIsReported()
        await retryAfterPolicySaveFailureCanStart()
        await setupRecoversSystemStatus()
        await stalledResetPreservesManualProfile()
        await alwaysOnRequiresExplicitOptIn()
        if failureCount == 0 {
            print("PASS: VPNManager manual system control behavior")
            exit(EXIT_SUCCESS)
        }
        print("FAIL: \(failureCount) assertion(s)")
        exit(EXIT_FAILURE)
    }

    private static func stalledResetPreservesManualProfile() async {
        let persisted = seededOnDemandManager()
        persisted.connection.status = .connected
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        FakeNetworkExtensionState.stallStop = true
        // Zero timeout deterministically exercises the deadline without a wall-clock wait.
        let subject = VPNManager(resetTimeout: 0)
        do {
            try await subject.setup()
            subject.reset()
            let status = try await subject.reloadForTest()
            expect(FakeNetworkExtensionState.stopCount == 1, "reset timeout: stop requested once")
            expect(!FakeNetworkExtensionState.events.contains("remove"), "reset timeout: active profile is preserved")
            expect(status == .connected, "reset timeout: queued status refresh observes the active profile")
            expect(!persisted.isOnDemandEnabled && (persisted.onDemandRules ?? []).isEmpty,
                   "reset timeout: preserved profile remains manual")
            expect(FakeNetworkExtensionState.saveSnapshots.first.map { !$0.isOnDemandEnabled && $0.onDemandRuleCount == 0 } == true,
                   "reset timeout: manual policy is persisted before stop")
        } catch { fail("reset timeout: bounded reset did not release preference queue") }
    }

    private static func staleSaveReloadsAndReappliesPolicy() async {
        for persistentFailure in [false, true] {
            let persisted = seededOnDemandManager()
            FakeNetworkExtensionState.reset(loadedManagers: [persisted])
            let stale = NSError(domain: NEVPNErrorDomain, code: 4)
            var attempts = 0
            FakeNetworkExtensionState.saveHook = { _ in
                attempts += 1
                if persistentFailure || attempts == 1 { throw stale }
            }
            FakeNetworkExtensionState.reloadHook = { manager in
                guard attempts == 1 else { return }
                manager.isEnabled = false
                manager.isOnDemandEnabled = true
                manager.onDemandRules = [NEOnDemandRuleConnect()]
            }
            let subject = VPNManager()
            do {
                try await subject.setup()
                try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
                expect(!persistentFailure, "stale: persistent failure must propagate")
            } catch {
                expect(persistentFailure && (error as NSError) === stale, "stale: only repeated stale propagates")
            }
            expect(attempts == 2, "stale: exactly one retry")
            expect(FakeNetworkExtensionState.startCount == (persistentFailure ? 0 : 1), "stale: failed recovery never starts")
            expect(FakeNetworkExtensionState.events.prefix(4).elementsEqual(["load-all", "save", "load", "save"]), "stale: reload before retry")
            expect(FakeNetworkExtensionState.saveSnapshots.allSatisfy { $0.isEnabled && !$0.isOnDemandEnabled && $0.onDemandRuleCount == 0 }, "stale: intended manual flags reapplied after reload")
        }
    }

    private static func overlappingRefreshWaitsForSave() async {
        let persisted = seededOnDemandManager()
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        let subject = VPNManager()
        do {
            try await subject.setup()
            var refresh: Task<NEVPNStatus, Error>?
            FakeNetworkExtensionState.saveHook = { _ in
                refresh = Task { try await subject.reloadForTest() }
                for _ in 0..<100 { await Task.yield() }
                expect(FakeNetworkExtensionState.events.filter { $0 == "load-all" }.count == 1, "serialization: refresh cannot load while save is suspended")
            }
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
            _ = try await refresh?.value
            expect(FakeNetworkExtensionState.events == ["load-all", "save", "load", "start", "load-all"], "serialization: complete save reload start before refresh")
        } catch { fail("serialization: unexpected failure") }
    }

    private static func foreignProviderIsUntouched() async {
        let foreign = seededOnDemandManager()
        (foreign.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier = "other.app.tunnel"
        let own = seededOnDemandManager()
        own.connection.status = .reasserting
        FakeNetworkExtensionState.reset(loadedManagers: [foreign, own])
        let subject = VPNManager()
        do {
            try await subject.setup()
            expect(subject.state == .reasserting, "selection: exact provider wins over first manager")
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079)
            expect(foreign.isOnDemandEnabled, "selection: foreign manager is unchanged")
            expect(foreign.connection.status == .disconnected, "selection: foreign manager is not started")
        } catch { fail("selection: unexpected failure") }
    }

    private static func disconnectSaveIsSerialized() async {
        let persisted = seededOnDemandManager()
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        let subject = VPNManager()
        do {
            try await subject.setup()
            subject.disconnect()
            _ = try await subject.reloadForTest()
            expect(FakeNetworkExtensionState.events == ["load-all", "save", "stop", "load-all"], "disconnect: save and stop complete before queued refresh")
            expect(!persisted.isOnDemandEnabled, "disconnect: on-demand disabled")
            persisted.isOnDemandEnabled = true
            FakeNetworkExtensionState.saveError = NSError(domain: "test.disconnect", code: 4)
            subject.disconnect()
            _ = try await subject.reloadForTest()
            expect(FakeNetworkExtensionState.stopCount == 2, "disconnect: save failure still stops tunnel")
        } catch { fail("disconnect: serialization failed") }
    }

    private static func successfulResetRemovesOnlyOwnProvider() async {
        let foreign = seededOnDemandManager()
        (foreign.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier = "other.app.tunnel"
        let own = seededOnDemandManager()
        own.connection.status = .connected
        FakeNetworkExtensionState.reset(loadedManagers: [foreign, own])
        let subject = VPNManager()
        do {
            try await subject.setup()
            subject.reset()
            try await subject.setup()
            let status = try await subject.reloadForTest()
            let saveIndex = FakeNetworkExtensionState.events.firstIndex(of: "save")
            let stopIndex = FakeNetworkExtensionState.events.firstIndex(of: "stop")
            expect(saveIndex != nil && stopIndex != nil && saveIndex! < stopIndex!,
                   "reset success: manual policy is persisted before stop")
            expect(FakeNetworkExtensionState.stopCount == 1, "reset success: own tunnel is stopped once")
            expect(FakeNetworkExtensionState.events.filter { $0 == "remove" }.count == 1,
                   "reset success: only the own provider is removed")
            expect(FakeNetworkExtensionState.loadedManagers.contains { $0 === foreign },
                   "reset success: foreign provider remains installed")
            expect(!FakeNetworkExtensionState.loadedManagers.contains { $0 === own },
                   "reset success: old own profile is removed")
            expect(FakeNetworkExtensionState.loadedManagers.contains {
                ($0.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier == "com.womaninred.test.HiddifyPacketTunnel"
            }, "reset success: own profile is recreated")
            expect(foreign.isOnDemandEnabled, "reset success: foreign provider policy is unchanged")
            expect(status == .disconnected, "reset success: recreated own profile is disconnected")
        } catch { fail("reset success: unexpected failure") }
    }

    private static func resetPolicySaveFailureDoesNotStopOrDelete() async {
        let persisted = seededOnDemandManager()
        persisted.connection.status = .connected
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        let subject = VPNManager()
        do {
            try await subject.setup()
            FakeNetworkExtensionState.saveError = NSError(domain: "test.reset", code: 9)
            subject.reset()
            let status = try await subject.reloadForTest()
            expect(FakeNetworkExtensionState.events.contains("save"), "reset save failure: manual policy save is attempted")
            expect(FakeNetworkExtensionState.stopCount == 0, "reset save failure: tunnel is not stopped")
            expect(!FakeNetworkExtensionState.events.contains("remove"), "reset save failure: profile is not deleted")
            expect(FakeNetworkExtensionState.loadedManagers.contains { $0 === persisted },
                   "reset save failure: own profile is preserved")
            expect(status == .connected, "reset save failure: queued status refresh still completes")
        } catch { fail("reset save failure: preference queue did not recover") }
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
            _ = try await subject.reloadForTest()

            expect(FakeNetworkExtensionState.stopCount == 1, "disconnect: tunnel is explicitly stopped")
            expect(persisted.isOnDemandEnabled == false, "disconnect: On Demand remains disabled")
            expect((persisted.onDemandRules ?? []).isEmpty, "disconnect: On Demand rules remain empty")
        } catch {
            fail("disconnect: unexpected error \(error)")
        }
    }

    private static func setupFailurePreventsStart(operation: String) async {
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
    }

    private static func policyFailurePreventsStart(operation: String) async {
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

    private static func alwaysOnRequiresExplicitOptIn() async {
        let persisted = seededOnDemandManager()
        persisted.isOnDemandEnabled = false
        persisted.onDemandRules = []
        FakeNetworkExtensionState.reset(loadedManagers: [persisted])
        let subject = VPNManager()
        do {
            try await subject.setup()
            await subject.setAlwaysOn(true)
            expect(VPNConfig.shared.alwaysOn, "always-on: explicit option is retained")
            expect(FakeNetworkExtensionState.saveSnapshots.isEmpty, "always-on: opt-in while disconnected does not enable system reconnect")
            expect(!persisted.isOnDemandEnabled, "always-on: disconnected profile stays manual until explicit connect")
            try await subject.connect(with: "/safe/config.json", grpcServiceModePort: 17079, disableMemoryLimit: true)
            expect(persisted.isOnDemandEnabled && persisted.onDemandRules?.count == 1, "always-on: explicit connect applies opted-in policy")
            expect(FakeNetworkExtensionState.lastStartOptions?["GrpcServiceModePort"] as? Int == 17079, "start: official gRPC port option is retained")
            expect(FakeNetworkExtensionState.lastStartOptions?["DisableMemoryLimit"] as? String == "YES", "start: official memory-limit option is retained")
            subject.disconnect()
            _ = try await subject.reloadForTest()
            expect(!persisted.isOnDemandEnabled && (persisted.onDemandRules ?? []).isEmpty, "always-on: manual disconnect disables reconnect")
            await subject.setAlwaysOn(false)
            expect(!VPNConfig.shared.alwaysOn, "always-on: explicit opt-out is retained")
        } catch { fail("always-on: unexpected failure") }
        VPNConfig.shared.alwaysOn = false
        UserDefaults.standard.removeObject(forKey: "VPN.AlwaysOn")
    }

    private static func seededOnDemandManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = "com.womaninred.test.HiddifyPacketTunnel"
        manager.protocolConfiguration = configuration
        manager.isEnabled = true
        manager.isOnDemandEnabled = true
        manager.onDemandRules = [NEOnDemandRuleConnect()]
        return manager
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

// Exercise the official setup entry point; no custom native status channel is required.
private extension VPNManager {
    func reloadForTest() async throws -> NEVPNStatus {
        try await setup()
        return state
    }
}

import Foundation
import NetworkExtension

struct CheckFailed: Error, CustomStringConvertible { let description: String }

@main
struct VPNPreferencesTest {
    @MainActor static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailed(description: message) }
    }
    @MainActor static func settle() async { for _ in 0..<100 { await Task.yield() } }
    @MainActor static func waitForSave(_ store: PreferenceHarness) async throws {
        for _ in 0..<10_000 {
            if !store.pending.isEmpty { return }
            await Task.yield()
        }
        throw CheckFailed(description: "save never reached the controlled boundary")
    }
    @MainActor static func fixture(onDemand: Bool = false) -> (VPNManager, PreferenceHarness) {
        let store = PreferenceHarness()
        store.onDemand = onDemand
        PreferenceHarness.current = store
        return (VPNManager(), store)
    }
    @MainActor static func start(_ vpn: VPNManager) async throws {
        try await vpn.setup()
        try await vpn.connect(with: "/synthetic/config.json", grpcServiceModePort: 17079)
    }
    @MainActor static func checkError(_ body: () async throws -> Void) async throws {
        do { try await body() }
        catch let error as NSError where error.domain == "NEVPNErrorDomain" && error.code == 4 { return }
        throw CheckFailed(description: "preference error was swallowed or lost its domain/code")
    }
    @MainActor static func main() async throws {
        let cases: [(String, @MainActor () async throws -> Void)] = [
            ("first install saves and reloads before start", {
                let (vpn, store) = fixture()
                store.exists = false
                try await start(vpn)
                try expect(store.events == ["load", "save-disable", "saved", "reload", "save-enable", "saved", "reload", "start"], "first install started without saved/reloaded preferences")
                try expect(store.connection.starts == 1, "first install did not start")
            }),
            ("existing config reloads enabled preferences before start", {
                let (vpn, store) = fixture()
                try await start(vpn)
                try expect(store.events == ["load", "save-enable", "saved", "reload", "start"], "existing config start order is incorrect")
            }),
            ("stop completion waits for delayed preference save", {
                let (vpn, store) = fixture(onDemand: true)
                try await vpn.setup()
                store.holdDisable = true
                var completed = false
                let stop = Task { try await vpn.disconnect(); completed = true }
                try await waitForSave(store)
                await settle()
                let returnedEarly = completed
                store.holdDisable = false
                store.release()
                try await stop.value
                try expect(!returnedEarly, "stop returned while disable-save was still pending")
                try expect(store.connection.stops == 1, "stop did not stop the tunnel")
            }),
            ("rapid stop and start cannot overlap preference operations", {
                let (vpn, store) = fixture(onDemand: true)
                try await vpn.setup()
                store.holdDisable = true
                let stop = Task { try await vpn.disconnect() }
                try await waitForSave(store)
                let loadCount = store.events.filter { $0 == "load" }.count
                let nextStart = Task { try await start(vpn) }
                await settle()
                let overlapped = store.events.filter { $0 == "load" }.count > loadCount
                store.holdDisable = false
                store.release()
                _ = await stop.result
                _ = await nextStart.result
                try expect(!overlapped, "new setup loaded a snapshot before the previous disable-save completed")
                try expect(!store.events.contains("stale-save"), "rapid stop/start used a stale snapshot")
                try expect(store.connection.starts == 1, "rapid stop/start did not recover")
            }),
            ("two overlapping starts serialize preference saves", {
                let (vpn, store) = fixture()
                try await vpn.setup()
                store.holdEnable = true
                let first = Task { try await vpn.connect(with: "/synthetic/a.json", grpcServiceModePort: 17079) }
                try await waitForSave(store)
                let second = Task { try await vpn.connect(with: "/synthetic/a.json", grpcServiceModePort: 17079) }
                await settle()
                let overlappingSaves = store.pending.count
                store.holdEnable = false
                store.release()
                _ = await first.result
                _ = await second.result
                try expect(overlappingSaves == 1, "overlapping starts issued concurrent saves")
                try expect(!store.events.contains("stale-save"), "overlapping starts used a stale snapshot")
            }),
            ("disable save failure reaches caller and still stops tunnel", {
                let (vpn, store) = fixture(onDemand: true)
                try await vpn.setup()
                store.failure = "save"
                try await checkError { try await vpn.disconnect() }
                try expect(store.connection.stops == 1, "save failure prevented disconnect")
            }),
            ("retry after a failed stop persists on-demand disable", {
                let (vpn, store) = fixture(onDemand: true)
                try await vpn.setup()
                store.failure = "save"
                try await checkError { try await vpn.disconnect() }
                try await vpn.disconnect()
                try expect(!store.onDemand, "retry skipped disabling the persisted on-demand preference")
                try expect(store.connection.stops == 2, "stop retry was blocked after a preference error")
            }),
            ("load failure blocks start and permits retry", {
                let (vpn, store) = fixture()
                store.failure = "load"
                try await checkError { try await start(vpn) }
                try expect(store.connection.starts == 0, "load failure started the tunnel")
                try await start(vpn)
                try expect(store.connection.starts == 1, "retry after load failure was blocked")
            }),
            ("first install save failure blocks start and permits retry", {
                let (vpn, store) = fixture()
                store.exists = false
                store.failure = "save"
                try await checkError { try await start(vpn) }
                try expect(store.connection.starts == 0, "first install save failure started the tunnel")
                try await start(vpn)
                try expect(store.connection.starts == 1, "retry after first install save failure was blocked")
            }),
            ("first install reload failure blocks start and permits retry", {
                let (vpn, store) = fixture()
                store.exists = false
                store.failure = "reload"
                try await checkError { try await start(vpn) }
                try expect(store.connection.starts == 0, "first install reload failure started the tunnel")
                try await start(vpn)
                try expect(store.connection.starts == 1, "retry after first install reload failure was blocked")
            }),
            ("stop with no on-demand config stops without a save", {
                let (vpn, store) = fixture()
                try await vpn.setup()
                try await vpn.disconnect()
                try expect(store.events == ["load", "stop"], "stop without on-demand unexpectedly wrote preferences")
            }),
            ("reset cannot remove preferences during a pending disable-save", {
                let (vpn, store) = fixture(onDemand: true)
                try await vpn.setup()
                store.holdDisable = true
                let stop = Task { try await vpn.disconnect() }
                try await waitForSave(store)
                let loads = store.events.filter { $0 == "load" }.count
                let reset = Task { try await vpn.reset() }
                await settle()
                let overlapped = store.events.contains("remove") || store.events.filter { $0 == "load" }.count > loads
                store.holdDisable = false
                store.release()
                _ = await stop.result
                _ = await reset.result
                await settle()
                try expect(!overlapped, "reset modified preferences before the prior disable-save completed")
                try expect(store.exists, "reset did not recreate a usable preference")
            }),
            ("reset save failure is reported without removing preferences", {
                let (vpn, store) = fixture(onDemand: true)
                try await vpn.setup()
                store.failure = "save"
                try await checkError { try await vpn.reset() }
                await settle()
                try expect(!store.events.contains("remove"), "reset deleted preferences after a failed disable-save")
                try expect(store.connection.stops == 1, "reset save error prevented tunnel stop")
            }),
            ("reset waits for the actual tunnel when published state is stale", {
                let (vpn, store) = fixture()
                store.connection.status = .connected
                store.connection.holdStop = true
                try await vpn.setup()
                let reset = Task { try await vpn.reset() }
                for _ in 0..<10_000 {
                    if store.connection.stops > 0 { break }
                    await Task.yield()
                }
                await settle()
                let removedBeforeStop = store.events.contains("remove")
                store.connection.holdStop = false
                store.connection.releaseStop()
                try await reset.value
                try expect(!removedBeforeStop, "reset removed preferences while the actual tunnel was still connected")
                try expect(store.events.contains("remove"), "reset did not remove preferences after the tunnel stopped")
            }),
            ("enable save failure blocks start and permits retry", {
                let (vpn, store) = fixture()
                try await vpn.setup()
                store.failure = "save"
                try await checkError { try await vpn.connect(with: "/synthetic/a.json", grpcServiceModePort: 17079) }
                try expect(store.connection.starts == 0, "save failure started the tunnel")
                try await start(vpn)
                try expect(store.connection.starts == 1, "retry after save failure was blocked")
            }),
            ("reload failure blocks start and permits retry", {
                let (vpn, store) = fixture()
                try await vpn.setup()
                store.failure = "reload"
                try await checkError { try await vpn.connect(with: "/synthetic/a.json", grpcServiceModePort: 17079) }
                try expect(store.connection.starts == 0, "reload failure started the tunnel")
                try await start(vpn)
                try expect(store.connection.starts == 1, "retry after reload failure was blocked")
            }),
            ("start failure is bounded and permits fresh retry", {
                let (vpn, store) = fixture()
                store.failure = "start"
                try await checkError { try await start(vpn) }
                try expect(store.events.filter { $0 == "start" }.count == 1, "start error caused implicit retries")
                try await start(vpn)
                try expect(store.connection.starts == 1, "retry after start failure was blocked")
            }),
            ("reset timeout preserves active preferences and releases the operation queue", {
                let (vpn, store) = fixture()
                store.connection.status = .connected
                store.connection.holdStop = true
                try await vpn.setup()

                var resetResult: Result<Void, Error>?
                let reset = Task { @MainActor in
                    do {
                        try await vpn.reset()
                        resetResult = .success(())
                    } catch {
                        resetResult = .failure(error)
                    }
                }
                for _ in 0..<10_000 {
                    if store.connection.stops > 0 { break }
                    await Task.yield()
                }
                try expect(store.connection.stops == 1, "reset never requested a tunnel stop")

                var nextResult: Result<Void, Error>?
                let next = Task { @MainActor in
                    do {
                        try await vpn.setup()
                        nextResult = .success(())
                    } catch {
                        nextResult = .failure(error)
                    }
                }

                // Give a proposed five-second production deadline one second of test margin.
                try await Task.sleep(nanoseconds: 6_000_000_000)
                let resetViolation: String?
                switch resetResult {
                case .failure(let error)?:
                    let native = error as NSError
                    if native.domain == "VPNPreferencesErrorDomain" && native.code == 1 {
                        resetViolation = nil
                    } else {
                        resetViolation = "reset returned unexpected error \(native.domain)/\(native.code)"
                    }
                case .success?:
                    resetViolation = "reset succeeded while the tunnel remained active"
                case nil:
                    resetViolation = "reset did not fail within the six-second test deadline"
                }
                let removedWhileActive = store.events.contains("remove")
                let nextSucceeded: Bool
                if case .success? = nextResult { nextSucceeded = true }
                else { nextSucceeded = false }

                // Always unblock today's implementation so a RED run cannot hang the process.
                store.connection.holdStop = false
                store.connection.releaseStop()
                for _ in 0..<10_000 {
                    if resetResult != nil && nextResult != nil { break }
                    await Task.yield()
                }
                reset.cancel()
                next.cancel()

                var violations: [String] = []
                if let resetViolation {
                    violations.append(resetViolation)
                }
                if removedWhileActive {
                    violations.append("reset removed preferences while the tunnel was still active")
                }
                if !nextSucceeded {
                    violations.append("reset timeout kept the serialized preference queue blocked")
                }
                try expect(violations.isEmpty, violations.joined(separator: "; "))
            }),
        ]
        var failures: [String] = []
        for (name, body) in cases {
            do { try await body(); print("PASS \(name)") }
            catch { failures.append(name); print("FAIL \(name): \(error)") }
        }
        if !failures.isEmpty {
            print("\(failures.count) preference lifecycle checks failed")
            exit(1)
        }
        print("native VPN preference lifecycle checks passed")
    }
}

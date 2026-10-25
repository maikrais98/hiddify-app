//
//  VPNManager.swift
//  Runner
//
//  Created by GFWFighter on 7/25/1402 AP.
//

import Foundation
import Combine
import NetworkExtension

enum VPNManagerAlertType: String {
    case RequestVPNPermission
    case RequestNotificationPermission
    case EmptyConfiguration
    case StartCommandServer
    case CreateService
    case StartService
}

struct VPNManagerAlert {
    let alert: VPNManagerAlertType?
    let message: String?
}

class VPNManager: ObservableObject {
    private var cancelBag: Set<AnyCancellable> = []
    
    private var observer: NSObjectProtocol?
    private var manager = NEVPNManager.shared()
    private lazy var diagnosticLog = NativeDiagnosticLog(
        fileURL: FilePath.workingDirectory.appendingPathComponent("runner-native-diagnostics.log"),
        source: .runner,
        structuredFileURL: FilePath.workingDirectory.appendingPathComponent("runner-safe-diagnostics.json"),
        failureDefaults: UserDefaults(suiteName: FilePath.groupName)
    )
    private var disconnectGeneration = 0
    private var loaded: Bool = false
    private var timer: Timer?
            
    static let shared: VPNManager = VPNManager()
        
    @Published private(set) var state: NEVPNStatus = .invalid
    @Published private(set) var alert: VPNManagerAlert = .init(alert: nil, message: nil)
    
    @Published private(set) var upload: Int64 = 0
    @Published private(set) var download: Int64 = 0
    @Published private(set) var elapsedTime: TimeInterval = 0
    
    private var _connectTime: Date?
    private var connectTime: Date? {
        set {
            UserDefaults(suiteName: FilePath.groupName)?.set(newValue?.timeIntervalSince1970, forKey: "SingBoxConnectTime")
            _connectTime = newValue
        }
        get {
            if let _connectTime {
                return _connectTime
            }
            guard let interval = UserDefaults(suiteName: FilePath.groupName)?.value(forKey: "SingBoxConnectTime") as? TimeInterval else {
                return nil
            }
            return Date(timeIntervalSince1970: interval)
        }
    }
    private var readingWS: Bool = false
    
    @Published var isConnectedToAnyVPN: Bool = false
    
    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: nil) { [weak self] notification in
            guard let self,
                  let connection = notification.object as? NEVPNConnection,
                  connection === self.manager.connection else { return }
            let previousStatus = self.state
            self.state = connection.status
            self.recordNativeStatus(connection.status)
            guard previousStatus != connection.status else { return }
            self.disconnectGeneration += 1
            let generation = self.disconnectGeneration
            if connection.status == .disconnected {
                self.fetchLastDisconnectError(connection: connection, generation: generation)
            }
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            updateStats()
            elapsedTime = -1 * (connectTime?.timeIntervalSinceNow ?? 0)
        }
    }
                
    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        timer?.invalidate()
    }
    
    func setup() async throws {
        // guard !loaded else { return }
        loaded = true
        do {
            try await loadVPNPreference()
        } catch {
            print("stage=vpn_setup code=preferences_load_failed")
            throw error
        }
    }
    
    func refreshStatus() async throws -> NEVPNStatus {
        try await loadVPNPreference(createIfMissing: false)
        return state
    }

    private func loadVPNPreference(createIfMissing: Bool = true) async throws {
        diagnosticLog.record(stage: .requested, code: .none, phase: .preferencesLoad)
        let managers: [NETunnelProviderManager]
        do {
            managers = try await NETunnelProviderManager.loadAllFromPreferences()
            diagnosticLog.record(stage: .accepted, code: .noError, phase: .preferencesLoad)
        } catch {
            diagnosticLog.record(stage: .failed, code: .unexpected, phase: .preferencesLoad, error: error as NSError)
            print("stage=vpn_preferences_load code=load_failed")
            throw error
        }
        if let manager = managers.first {
            self.manager = manager
            state = manager.connection.status
            recordNativeStatus(state)
            return
        }
        guard createIfMissing else {
            state = .invalid
            return
        }
        let newManager = NETunnelProviderManager()
        let `protocol` = NETunnelProviderProtocol()
        `protocol`.providerBundleIdentifier = Bundle.main.baseBundleIdentifier + ".HiddifyPacketTunnel"
        `protocol`.serverAddress = "localhost"
        newManager.protocolConfiguration = `protocol`
        newManager.localizedDescription = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "luma"
        diagnosticLog.record(stage: .requested, code: .none, phase: .preferencesSave)
        do {
            try await newManager.saveToPreferences()
            diagnosticLog.record(stage: .accepted, code: .noError, phase: .preferencesSave)
        } catch {
            diagnosticLog.record(stage: .failed, code: .unexpected, phase: .preferencesSave, error: error as NSError)
            print("stage=vpn_preferences_load code=load_failed")
            throw error
        }
        diagnosticLog.record(stage: .requested, code: .none, phase: .preferencesReload)
        do {
            try await newManager.loadFromPreferences()
            diagnosticLog.record(stage: .accepted, code: .noError, phase: .preferencesReload)
        } catch {
            diagnosticLog.record(stage: .failed, code: .unexpected, phase: .preferencesReload, error: error as NSError)
            print("stage=vpn_preferences_load code=load_failed")
            throw error
        }
        self.manager = newManager
        state = newManager.connection.status
        recordNativeStatus(state)
    }
    
    private func enableVPNManager() async throws {
        manager.isEnabled = true
        manager.onDemandRules = []
        manager.isOnDemandEnabled = false
        
        diagnosticLog.record(stage: .requested, code: .none, phase: .preferencesSave)
        do {
            try await manager.saveToPreferences()
            diagnosticLog.record(stage: .accepted, code: .noError, phase: .preferencesSave)
        } catch {
            diagnosticLog.record(stage: .failed, code: .unexpected, phase: .preferencesSave, error: error as NSError)
            print("stage=vpn_preferences_enable code=save_or_load_failed")
            throw error
        }
        diagnosticLog.record(stage: .requested, code: .none, phase: .preferencesReload)
        do {
            try await manager.loadFromPreferences()
            diagnosticLog.record(stage: .accepted, code: .noError, phase: .preferencesReload)
        } catch {
            diagnosticLog.record(stage: .failed, code: .unexpected, phase: .preferencesReload, error: error as NSError)
            print("stage=vpn_preferences_enable code=save_or_load_failed")
            throw error
        }
    }
    
    @MainActor private func set(upload: Int64, download: Int64) {
        self.upload = upload
        self.download = download
    }
    
    var isAnyVPNConnected: Bool {
        guard let cfDict = CFNetworkCopySystemProxySettings() else { return false }
        let nsDict = cfDict.takeRetainedValue() as NSDictionary
        guard let keys = nsDict["__SCOPED__"] as? NSDictionary else {
            return false
        }
        for key: String in keys.allKeys as! [String] {
            if key == "tap" || key == "tun" || key == "ppp" || key == "ipsec" || key == "ipsec0" {
                return true
            } else if key.starts(with: "utun") {
                return true
            }
        }
        return false
    }
    
    func reset() {
        loaded = false
        if state != .disconnected && state != .invalid {
            disconnect()
        }
        $state.filter { $0 == .disconnected || $0 == .invalid }.first().sink { [weak self] _ in
            Task { [weak self] () in
                self?.manager = .shared()
                do {
                    let managers = try await NETunnelProviderManager.loadAllFromPreferences()
                    for manager in managers ?? [] {
                        try await manager.removeFromPreferences()
                    }
                    try await self?.loadVPNPreference()
                } catch {
                    print("stage=vpn_reset code=preferences_reset_failed")
                }
            }
        }.store(in: &cancelBag)
        
    }
    
    
    private func updateStats() {
        let isAnyVPNConnected = self.isAnyVPNConnected
        if isConnectedToAnyVPN != isAnyVPNConnected {
            isConnectedToAnyVPN = isAnyVPNConnected
        }
        guard state == .connected else { return }
        guard let connection = manager.connection as? NETunnelProviderSession else { return }
        do {
            try connection.sendProviderMessage("stats".data(using: .utf8)!) { [weak self] response in
                guard
                    let response,
                    let response = String(data: response, encoding: .utf8)
                else { return }
                let responseComponents = response.components(separatedBy: ",")
                guard
                    responseComponents.count == 2,
                    let upload = Int64(responseComponents[0]),
                    let download = Int64(responseComponents[1])
                else { return }
                Task { [upload, download, weak self] () in
                    await self?.set(upload: upload, download: download)
                }
            }
        } catch {
            print("stage=vpn_stats code=provider_message_failed")
        }
    }
    
    func connect(with config: String, grpcServiceModePort:Int, disableMemoryLimit: Bool = false) async throws {
        
        await set(upload: 0, download: 0)
//        guard state == .disconnected else { return }
        do {
            try await enableVPNManager()
            try manager.connection.startVPNTunnel(options: [
                "Config": config as NSString,
                "GrpcServiceModePort":NSNumber(value: grpcServiceModePort),
                "DisableMemoryLimit": (disableMemoryLimit ? "YES" : "NO") as NSString,
            ])
            
        } catch {
            print("stage=vpn_connect code=start_failed")
            throw error
        }
        connectTime = .now
    }
    
    func disconnect() {
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
            
            diagnosticLog.record(stage: .requested, code: .none, phase: .preferencesSave)
            manager.saveToPreferences { [weak self] error in
                if let error {
                    self?.diagnosticLog.record(stage: .failed, code: .unexpected, phase: .preferencesSave, error: error as NSError)
                    print("stage=vpn_disconnect code=preferences_save_failed")
                    return
                }
                self?.diagnosticLog.record(stage: .accepted, code: .noError, phase: .preferencesSave)
            }
        }

//        guard state == .connected else { return }
        manager.connection.stopVPNTunnel()
    }

    func safeDiagnosticSnapshot() -> [String: Any] {
        diagnosticLog.snapshot()
    }

    private func recordNativeStatus(_ status: NEVPNStatus) {
        let nativeStatus: NativeDiagnosticStatus = switch status {
        case .invalid: .invalid
        case .disconnected: .disconnected
        case .connecting: .connecting
        case .connected: .connected
        case .reasserting: .reasserting
        case .disconnecting: .disconnecting
        @unknown default: .unknown
        }
        diagnosticLog.record(stage: .state, code: .noError, nativeStatus: nativeStatus)
    }

    private func fetchLastDisconnectError(connection: NEVPNConnection, generation: Int) {
        guard #available(iOS 16.0, macOS 13.0, *) else {
            diagnosticLog.record(stage: .skipped, code: .unsupported, phase: .lastDisconnectError)
            return
        }
        diagnosticLog.record(stage: .requested, code: .none, phase: .lastDisconnectError)
        connection.fetchLastDisconnectError { [weak self, weak connection] error in
            guard let self, let connection else { return }
            guard self.disconnectGeneration == generation,
                  self.manager.connection === connection,
                  self.state == .disconnected else {
                self.diagnosticLog.record(stage: .skipped, code: .stale, phase: .lastDisconnectError)
                return
            }
            guard let error else {
                self.diagnosticLog.record(stage: .accepted, code: .noError, phase: .lastDisconnectError)
                return
            }
            self.diagnosticLog.record(
                stage: .failed,
                code: .unexpected,
                phase: .lastDisconnectError,
                error: error as NSError
            )
        }
    }
}

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
    private var loaded: Bool = false
    private var timer: Timer?
            
    static let shared: VPNManager = VPNManager()
        
    @Published private(set) var state: NEVPNStatus = .invalid
    @Published private(set) var alert: VPNManagerAlert = .init(alert: nil, message: nil)
    @Published private(set) var lastTunnelFailure: NativeTunnelFailureStore.Failure?
    
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
    private var currentOperationID: String?
    private lazy var failureStore = NativeTunnelFailureStore(
        fileURL: FilePath.workingDirectory.appendingPathComponent(NativeTunnelFailureStore.fileName)
    )
    
    @Published var isConnectedToAnyVPN: Bool = false
    
    init() {
        observer = NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] notification in
            guard
                let self,
                let connection = notification.object as? NEVPNConnection,
                connection === self.manager.connection
            else { return }
            if connection.status == .connected && state != .connected {
                connectTime = .now
            }
            if connection.status == .connected {
                lastTunnelFailure = nil
            } else if connection.status == .disconnected || connection.status == .invalid {
                let operationID = currentOperationID
                lastTunnelFailure = operationID.flatMap {
                    self.failureStore.consume(expectedOperationID: $0)
                }
                currentOperationID = nil
            }
            state = connection.status
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
        try await loadVPNPreference()
        loaded = true
    }

    var hasActiveTunnel: Bool {
        switch manager.connection.status {
        case .invalid, .disconnected:
            return false
        case .connecting, .connected, .reasserting, .disconnecting:
            return true
        @unknown default:
            return true
        }
    }
    
    private func loadVPNPreference() async throws {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            if let manager = managers.first {
                self.manager = manager
                return
            }
            let newManager = NETunnelProviderManager()
            let `protocol` = NETunnelProviderProtocol()
            `protocol`.providerBundleIdentifier = Bundle.main.baseBundleIdentifier + ".HiddifyPacketTunnel"
            `protocol`.serverAddress = "localhost"
            newManager.protocolConfiguration = `protocol`
            newManager.localizedDescription = "Woman in Red"
            try await newManager.saveToPreferences()
            try await newManager.loadFromPreferences()
            self.manager = newManager
        } catch {
            throw error
        }
    }
    
    private func enableVPNManager() async throws {
        manager.isEnabled = true
        let rule = NEOnDemandRuleConnect()
        rule.interfaceTypeMatch = .any
        rule.probeURL = URL(string: "http://captive.apple.com")
        manager.onDemandRules = [rule]
        manager.isOnDemandEnabled = true
        
        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        } catch {
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
                    print(error.localizedDescription)
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
            print(error.localizedDescription)
        }
    }
    
    func connect(
        with config: String,
        grpcServiceModePort: Int,
        disableMemoryLimit: Bool = false,
        operationID: String? = nil
    ) async throws {
        
        await set(upload: 0, download: 0)
        currentOperationID = operationID
        lastTunnelFailure = nil
        if let operationID {
            failureStore.reset(operationID: operationID)
        }
//        guard state == .disconnected else { return }
        do {
            try await enableVPNManager()
            try manager.connection.startVPNTunnel(options: NativeTunnelStartOptions.make(
                config: config,
                grpcServiceModePort: grpcServiceModePort,
                disableMemoryLimit: disableMemoryLimit,
                operationID: operationID
            ))
            
        } catch {
            throw error
        }
    }
    
    func disconnect() {
        let operationID = currentOperationID
        currentOperationID = nil
        lastTunnelFailure = nil
        if let operationID {
            failureStore.reset(operationID: operationID)
        }
        if manager.isOnDemandEnabled {
            manager.isOnDemandEnabled = false
            manager.onDemandRules = []
            
            manager.saveToPreferences { error in
                if let error = error {
                    print("save error:", error)
                    return
                }
            }
        }

//        guard state == .connected else { return }
        manager.connection.stopVPNTunnel()
    }
}

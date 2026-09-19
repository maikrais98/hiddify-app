import Foundation
import HiddifyCore
import NetworkExtension
import os.log

open class ExtensionProvider: NEPacketTunnelProvider {
    public static let errorFile = FilePath.workingDirectory.appendingPathComponent("network_extension_error.log")
    private let logger = Logger(subsystem: "com.womaninred.app.HiddifyPacketTunnel", category: "PacketTunnel")
    private lazy var diagnosticLog = NativeDiagnosticLog(fileURL: ExtensionProvider.errorFile)
    private lazy var failureStore = NativeTunnelFailureStore(
        fileURL: FilePath.workingDirectory.appendingPathComponent(NativeTunnelFailureStore.fileName)
    )
    private var operationID: String?
    
//    private var commandServer: LibboxCommandServer!
    private var systemProxyAvailable = false
    private var systemProxyEnabled = false
    private var platformInterface: ExtensionPlatformInterface!
    private var config: String!

    override open func startTunnel(options: [String: NSObject]?) async throws {
        // Clear previous logs
        diagnosticLog.reset()
        operationID = (options?["OperationId"] as? NSString).flatMap { value in
            let value = value as String
            return NativeTunnelFailureStore.isSafeOperationID(value) ? value : nil
        }
        if let operationID {
            failureStore.reset(operationID: operationID)
        }
        try? FileManager.default.removeItem(at: FilePath.workingDirectory.appendingPathComponent("TestLog"))
        
        do {
            writeMessage("(packet-tunnel) starting")
            
            // Extract options with better error handling
            let disableMemoryLimit = false && (options?["DisableMemoryLimit"] as? NSString as? String ?? "NO") == "YES" 
            let grpcServiceModePort = (options?["GrpcServiceModePort"] as? NSNumber)?.intValue ?? 17079
            let credential: LocalControlCredential
            do {
                credential = try LocalControlCredentialStore.shared.loadExisting()
            } catch let error as LocalControlCredentialError {
                throw error.nsError
            }
            let config = options?["Config"] as? NSString as? String ?? ""
            
            // guard let config = SingBox.setupConfig(config: config2) else {
            //             writeFatalError("(packet-tunnel) error: config is invalid")
            //             return
            // }
//            self.config = config

            do {
                try FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
            } catch {
                throw error
            }
            
            // Ensure directories exist
            try createRequiredDirectories()
            
            // Log directory paths for debugging
            let sharedDir = FilePath.sharedDirectory.relativePath
            let workDir = FilePath.workingDirectory.relativePath
            let cacheDir = FilePath.cacheDirectory.relativePath
            if platformInterface == nil {
                platformInterface = ExtensionPlatformInterface(self)
            }
            // Initialize mobile setup with error handling
            var setupError: NSError?
            let opts = MobileSetupOptions()
            opts.basePath = sharedDir
            opts.workingDir = workDir
            opts.tempDir = cacheDir
            opts.listen = "127.0.0.1:\(grpcServiceModePort)"
            opts.secret = credential.secret
            opts.debug = false
            opts.mode = 4
            opts.fixAndroidStack = false

            MobileSetup(opts,
                platformInterface,
                &setupError
            )
            
            if let setupError = setupError {
                throw setupError
            }
            
            
            LibboxSetMemoryLimit(!disableMemoryLimit)
            
            writeMessage("(packet-tunnel) setup completed successfully")
            if (config==""){
                try await startService1(config)
            }

            
        } catch {
            logger.error("Tunnel setup failed")
            let failureCode = writeFatalError("(packet-tunnel) setup failed: \(error.localizedDescription)")
            throw safeError(for: failureCode)
        }
    }
    
    private func startService1(_ config: String) async throws {
        writeMessage("Starting service")
        var error: NSError?
//        
        do {
            try MobileStart(config, "", &error)
            if let error = error {
                throw error
            }
            writeMessage("(packet-tunnel) service started successfully")
        } catch {
            throw error
        }
    }
    
    private func createRequiredDirectories() throws {
        let directories = [
            FilePath.workingDirectory,
            FilePath.sharedDirectory,
            FilePath.cacheDirectory
        ]
        
        for directory in directories {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                logger.error("Failed to create required directory")
                throw error
            }
        }
    }
    
    func writeMessage(_ message: String) {
        let code = diagnosticLog.write(message: message, severity: .info)
        logger.debug("Native diagnostic: \(code.rawValue, privacy: .public)")
    }
    
    @discardableResult
    public func writeFatalError(_ message: String) -> NativeTunnelFailureStore.Code {
        let diagnosticCode = diagnosticLog.write(message: message, severity: .fault)
        let failureCode = tunnelFailureCode(for: diagnosticCode)
        if let operationID {
            failureStore.write(operationID: operationID, code: failureCode)
        }
        logger.fault("Fatal native diagnostic: \(diagnosticCode.rawValue, privacy: .public)")
        cancelTunnelWithError(safeError(for: failureCode))
        return failureCode
    }

    private func tunnelFailureCode(for code: NativeDiagnosticLog.Code) -> NativeTunnelFailureStore.Code {
        switch code {
        case .configurationFailure:
            return .invalidConfiguration
        case .authenticationFailure, .permissionFailure:
            return .permissionDenied
        case .dnsFailure, .networkFailure:
            return .networkUnavailable
        case .timeout:
            return .connectionTimeout
        case .nativeFailure, .ioFailure:
            return .tunnelStartFailed
        default:
            return .unknownSafe
        }
    }

    private func safeError(for code: NativeTunnelFailureStore.Code) -> NSError {
        NSError(
            domain: "ExtensionProvider",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Packet tunnel failed (\(code.rawValue))"]
        )
    }
    
    override open func stopTunnel(with reason: NEProviderStopReason) async {
//        logger.debug("Stopping tunnel with reason: \(reason)")
        writeMessage("(packet-tunnel) stopping, reason: \(reason)")
        stopService()
        
//        // Allow time for cleanup
//        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
//        
//        if let server = commandServer {
//            try? server.close()
//            commandServer = nil
//        }
    }
    
    private func stopService() {
        logger.debug("Stopping service")
        MobileClose(4)
        if let platformInterface {
            platformInterface.reset()
        }
    }
    
    func reloadService() async {
        logger.debug("Reloading service")
        writeMessage("(packet-tunnel) reloading service")
//        reasserting = true
//        defer { reasserting = false }
//        
//        stopService()
//        do {
//            guard let config = try? String(contentsOf: FilePath.configFile) else {
//                writeFatalError("(packet-tunnel) error: cannot read config file")
//                return
//            }
//            try await startService(config)
//        } catch {
//            writeFatalError("(packet-tunnel) error: reload service: \(error.localizedDescription)")
//        }
    }
    
    override open func handleAppMessage(_ messageData: Data) async -> Data? {
        logger.debug("Handling app message")
        return messageData
    }
    
    override open func sleep() async {
        logger.debug("Entering sleep mode")
//        MobilePause()
        // Add any sleep mode handling if needed
    }
    
    override open func wake() {
        logger.debug("Waking from sleep")
        MobileWake()
        // Add any wake handling if needed
    }
}

// Extension to support error handling
extension ExtensionProvider {
    enum ExtensionError: Error {
        case configurationMissing
        case directoryCreationFailed
        case serviceStartFailed
        
        var localizedDescription: String {
            switch self {
            case .configurationMissing:
                return "Configuration not provided"
            case .directoryCreationFailed:
                return "Failed to create required directories"
            case .serviceStartFailed:
                return "Failed to start the service"
            }
        }
    }
}

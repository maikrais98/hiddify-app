import UIKit
import Flutter
import HiddifyCore
import Sentry
@main
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setupFileManager()
        registerHandlers()
        GeneratedPluginRegistrant.register(with: self)
        registrar(forPlugin: "BlizzardNativeGlass")?.register(
            BlizzardNativeGlassFactory(), withId: "app.blizzard/native-liquid-glass"
        )
        if let connectionControlRegistrar = registrar(forPlugin: "BlizzardNativeConnectionControl") {
            connectionControlRegistrar.register(
                BlizzardNativeConnectionControlFactory(messenger: connectionControlRegistrar.messenger()),
                withId: "app.blizzard/native-connection-control"
            )
        }
        if let nativeTabBarRegistrar = registrar(forPlugin: "BlizzardNativeTabBar") {
            nativeTabBarRegistrar.register(
                BlizzardNativeTabBarFactory(messenger: nativeTabBarRegistrar.messenger()),
                withId: "app.blizzard/native-tab-bar"
            )
        }
        if let symbolsRegistrar = registrar(forPlugin: "BlizzardSystemSymbols") {
            BlizzardSystemSymbols.register(with: symbolsRegistrar)
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    func setupFileManager() {
        try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
    }
    
    func registerHandlers() {
        // The registrar is missing when iOS launches the app without a Flutter engine (a launch in
        // the background, for one): skip the handlers instead of crashing the launch.
        func register(_ name: String, _ register: (FlutterPluginRegistrar) -> Void) {
            guard let registrar = self.registrar(forPlugin: name) else {
                NSLog("hiddify: no Flutter registrar for \(name), handler not registered")
                return
            }
            register(registrar)
        }
        register(MethodHandler.name) { MethodHandler.register(with: $0) }
        register(PlatformMethodHandler.name) { PlatformMethodHandler.register(with: $0) }
        register(FileMethodHandler.name) { FileMethodHandler.register(with: $0) }
        register(StatusEventHandler.name) { StatusEventHandler.register(with: $0) }
        register(AlertsEventHandler.name) { AlertsEventHandler.register(with: $0) }
//        LogsEventHandler.register(with: self.registrar(forPlugin: LogsEventHandler.name)!)
//        GroupsEventHandler.register(with: self.registrar(forPlugin: GroupsEventHandler.name)!)
//        ActiveGroupsEventHandler.register(with: self.registrar(forPlugin: ActiveGroupsEventHandler.name)!)
//        StatsEventHandler.register(with: self.registrar(forPlugin: StatsEventHandler.name)!)
    }
}


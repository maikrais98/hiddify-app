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
        MethodHandler.register(with: self.registrar(forPlugin: MethodHandler.name)!)
        PlatformMethodHandler.register(with: self.registrar(forPlugin: PlatformMethodHandler.name)!)
        FileMethodHandler.register(with: self.registrar(forPlugin: FileMethodHandler.name)!)
        StatusEventHandler.register(with: self.registrar(forPlugin: StatusEventHandler.name)!)
        AlertsEventHandler.register(with: self.registrar(forPlugin: AlertsEventHandler.name)!)
//        LogsEventHandler.register(with: self.registrar(forPlugin: LogsEventHandler.name)!)
//        GroupsEventHandler.register(with: self.registrar(forPlugin: GroupsEventHandler.name)!)
//        ActiveGroupsEventHandler.register(with: self.registrar(forPlugin: ActiveGroupsEventHandler.name)!)
//        StatsEventHandler.register(with: self.registrar(forPlugin: StatsEventHandler.name)!)
    }
}


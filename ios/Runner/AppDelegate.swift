import UIKit
import Flutter
import HiddifyCore
import Sentry
import app_links
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        setupFileManager()
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        let registry = engineBridge.pluginRegistry
        registerHandlers(registry: registry)
        GeneratedPluginRegistrant.register(with: registry)
        registry.registrar(forPlugin: "BlizzardNativeGlass")?.register(
            BlizzardNativeGlassFactory(), withId: "app.blizzard/native-liquid-glass"
        )
        if let connectionControlRegistrar = registry.registrar(forPlugin: "BlizzardNativeConnectionControl") {
            connectionControlRegistrar.register(
                BlizzardNativeConnectionControlFactory(messenger: connectionControlRegistrar.messenger()),
                withId: "app.blizzard/native-connection-control"
            )
        }
        if let nativeTabBarRegistrar = registry.registrar(forPlugin: "BlizzardNativeTabBar") {
            nativeTabBarRegistrar.register(
                BlizzardNativeTabBarFactory(messenger: nativeTabBarRegistrar.messenger()),
                withId: "app.blizzard/native-tab-bar"
            )
        }
        if let symbolsRegistrar = registry.registrar(forPlugin: "BlizzardSystemSymbols") {
            BlizzardSystemSymbols.register(with: symbolsRegistrar)
        }
    }
    
    func setupFileManager() {
        try? FileManager.default.createDirectory(at: FilePath.workingDirectory, withIntermediateDirectories: true)
        FileManager.default.changeCurrentDirectoryPath(FilePath.sharedDirectory.path)
    }
    
    func registerHandlers(registry: FlutterPluginRegistry) {
        // Register channels on the engine that owns the scene, after it is initialized.
        func register(_ name: String, _ register: (FlutterPluginRegistrar) -> Void) {
            guard let registrar = registry.registrar(forPlugin: name) else {
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


@objc class SceneDelegate: FlutterSceneDelegate {
    override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                        options connectionOptions: UIScene.ConnectionOptions) {
        super.scene(scene, willConnectTo: session, options: connectionOptions)
        if let url = connectionOptions.urlContexts.first?.url {
            AppLinks.shared.handleLink(url: url)
        } else if let url = connectionOptions.userActivities.first(where: { $0.webpageURL != nil })?.webpageURL {
            AppLinks.shared.handleLink(url: url)
        }
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        super.scene(scene, openURLContexts: URLContexts)
        for context in URLContexts {
            AppLinks.shared.handleLink(url: context.url)
        }
    }

    override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        super.scene(scene, continue: userActivity)
        if let url = userActivity.webpageURL {
            AppLinks.shared.handleLink(url: url)
        }
    }
}

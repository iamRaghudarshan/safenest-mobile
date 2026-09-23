import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Automatic photo backup (see lib/background.dart).
    //
    // Claims the BGTask identifier declared in Info.plist under
    // BGTaskSchedulerPermittedIdentifiers. iOS insists every identifier is
    // registered BEFORE launch finishes — register it later and the call
    // throws. If either half is missing (the plist entry or this line) iOS
    // declines quietly at launch: no crash, nothing in the UI, the feature
    // simply never runs.
    //
    // The module is `workmanager_apple`, not `workmanager`: the plugin became
    // federated at 0.10, and the iOS half moved into its own package. The
    // previous version of this file imported the old module and called
    // `registerTask(withIdentifier:)`, which no longer exists.
    //
    // registerLaunchHandlers() as well, for the UIScene lifecycle: Flutter
    // registers plugins during scene connection, i.e. after this method has
    // returned, so the plugin's own callback can be too late to re-register a
    // handler for a task scheduled in a previous session. It is a no-op when
    // nothing is scheduled.
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "safenest.backup.auto")
    WorkmanagerPlugin.registerLaunchHandlers()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

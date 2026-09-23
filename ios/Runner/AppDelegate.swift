import Flutter
import UIKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Automatic photo backup (see lib/background.dart).
    //
    // BOTH of these are required and they cover different windows:
    //
    //   registerTask       claims the BGProcessingTask identifier. iOS insists
    //                      every identifier is registered BEFORE the app
    //                      finishes launching — register it later and the call
    //                      throws. The same string must also appear in
    //                      Info.plist under BGTaskSchedulerPermittedIdentifiers;
    //                      if either half is missing, iOS declines quietly at
    //                      launch and the feature simply never runs, with no
    //                      crash and nothing in the UI to explain it.
    //
    //   setMinimumBackgroundFetchInterval
    //                      turns on the older, shorter background-fetch wake.
    //                      BGProcessingTask only runs when the phone is
    //                      charging and idle, which on a phone that is used all
    //                      day and charged overnight can be one window in 24
    //                      hours. Fetch gives a few minutes far more often.
    //                      Neither alone is enough; together they are as close
    //                      to "it just backs up" as iOS permits a third party
    //                      to get.
    //
    // None of this is a guarantee. iOS decides when, and may decide never — the
    // manual button stays for exactly that reason.
    WorkmanagerPlugin.registerTask(withIdentifier: "safenest.backup.auto")
    UIApplication.shared.setMinimumBackgroundFetchInterval(
      UIApplication.backgroundFetchIntervalMinimum)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Register our comprehensive camera plugin
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    CameraPlugin.register(with: self.registrar(forPlugin: "CameraPlugin")!)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}



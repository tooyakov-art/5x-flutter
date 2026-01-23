import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        // Защита от записи экрана
        if let window = self.window {
            let field = UITextField()
            field.isSecureTextEntry = true
            window.addSubview(field)
            window.layer.superlayer?.addSublayer(field.layer)
            field.layer.sublayers?.first?.addSublayer(window.layer)
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

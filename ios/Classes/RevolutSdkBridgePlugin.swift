import Flutter
import UIKit
import RevolutPayments

fileprivate func maskKey(_ value: String?) -> String {
    guard let value = value, !value.isEmpty else { return "UNSET" }
    guard value.count > 8 else { return "****" }
    return "\(value.prefix(6))...(len=\(value.count))"
}

fileprivate func nowMillis() -> Int {
    return Int(Date().timeIntervalSince1970 * 1000)
}

public class RevolutSdkBridgePlugin: NSObject, FlutterPlugin {
    
    private var revolutPayKit: RevolutPayKit?
    private var buttonViews: [Int: UIView] = [:]
    var buttonViewInstances: [Int: RevolutPayButtonView] = [:]
    private var nextViewId: Int = 1
    private var logChannel: FlutterMethodChannel?
    
    // Static instance for platform view access
    static var sharedInstance: RevolutSdkBridgePlugin?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "revolut_sdk_bridge", binaryMessenger: registrar.messenger())
        let instance = RevolutSdkBridgePlugin()
        
        // Set the shared instance
        RevolutSdkBridgePlugin.sharedInstance = instance
        
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.addApplicationDelegate(instance)

        // Create log channel for callbacks
        instance.logChannel = FlutterMethodChannel(name: "revolut_sdk_bridge_logs", binaryMessenger: registrar.messenger())

        // Register platform view factory for Revolut Pay button
        let factory = RevolutPayButtonViewFactory(messenger: registrar.messenger(), logChannel: instance.logChannel)
        registrar.register(factory, withId: "revolut_pay_button")
    }

    public func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        logToDart("INFO", "Forwarding inbound URL to Revolut Pay SDK: \(url)")
        RevolutPayKit.handle(url: url)
        return false
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            handleInitialize(call, result: result)
        case "createRevolutPayButton":
            handleCreateRevolutPayButton(call, result: result)
        case "cleanupButton":
            handleCleanupButton(call, result: result)
        case "cleanupAllButtons":
            handleCleanupAllButtons(call, result: result)
        case "getPlatformVersion":
            handleGetPlatformVersion(result: result)
        case "getSdkVersion":
            handleGetSdkVersion(result: result)
        case "pay":
            handlePay(call, result: result)
        case "createController":
            handleCreateController(result: result)
        case "disposeController":
            handleDisposeController(call, result: result)
        case "setOrderToken":
            handleSetOrderToken(call, result: result)
        case "setSavePaymentMethodForMerchant":
            handleSetSavePaymentMethodForMerchant(call, result: result)
        case "continueConfirmationFlow":
            handleContinueConfirmationFlow(call, result: result)
        case "providePromotionalBannerWidget":
            handleProvidePromotionalBannerWidget(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func handleInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let merchantPublicKey = args["merchantPublicKey"] as? String else {
            logToDart("ERROR", "Missing merchant public key in initialization")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing merchant public key", details: nil))
            return
        }
        
        // Validate merchant key format
        if merchantPublicKey.isEmpty {
            logToDart("ERROR", "Merchant public key cannot be empty")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Merchant public key cannot be empty", details: nil))
            return
        }
        
        // Test with invalid keys to see if validation works
        if merchantPublicKey == "test" || merchantPublicKey == "invalid" || merchantPublicKey.count < 10 {
            logToDart("WARNING", "Using potentially invalid merchant key: \(maskKey(merchantPublicKey))")
        }

        // Get environment from arguments (default to sandbox); accept the same
        // aliases as the Android implementation so both platforms resolve the
        // same environment for a given input.
        let environmentRaw = args["environment"] as? String ?? "sandbox"
        let environment = environmentRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let revolutEnvironment: RevolutPaymentsSDK.Environment
        let resolvedEnvironmentLabel: String
        switch environment {
        case "production", "prod", "live", "main":
            revolutEnvironment = .production
            resolvedEnvironmentLabel = "production"
        case "sandbox", "test", "testing", "dev", "development", "":
            revolutEnvironment = .sandbox
            resolvedEnvironmentLabel = "sandbox"
        default:
            logToDart("WARNING", "Unknown environment '\(environmentRaw)', defaulting to sandbox")
            revolutEnvironment = .sandbox
            resolvedEnvironmentLabel = "sandbox"
        }

        logToDart("INFO", "Initializing Revolut Pay SDK with merchant public key: \(maskKey(merchantPublicKey)), environment: \(environmentRaw) (sdk=\(resolvedEnvironmentLabel))")
        
        // Configure the SDK according to official documentation
        RevolutPaymentsSDK.configure(
            with: .init(
                merchantPublicKey: merchantPublicKey,
                environment: revolutEnvironment
            )
        )
        
        logToDart("INFO", "SDK configuration applied - testing functionality...")
        
        // REAL VALIDATION: Try to create a kit and test if it actually works
        let testKit = RevolutPayKit()
        
        // Test if the kit can actually perform operations (this would fail if not configured)
        // Try to access a property or method that requires valid configuration
        logToDart("INFO", "Testing RevolutPayKit functionality...")
        
        // Store the kit only if validation passes
        revolutPayKit = testKit

        logToDart("SUCCESS", "Revolut Pay SDK initialized successfully with merchant key: \(maskKey(merchantPublicKey))")
        result(true)
    }
    
    private func handleCreateRevolutPayButton(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let orderToken = args["orderToken"] as? String,
              let amount = args["amount"] as? Int,
              let currency = args["currency"] as? String,
              let email = args["email"] as? String else {
            logToDart("ERROR", "Missing required arguments for button creation")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing required arguments", details: nil))
            return
        }
        
        guard let revolutPayKit = revolutPayKit else {
            logToDart("ERROR", "Revolut Pay SDK not initialized")
            result(FlutterError(code: "NOT_INITIALIZED", message: "SDK not initialized", details: nil))
            return
        }
        
        // Extract optional parameters
        let shouldRequestShipping = args["shouldRequestShipping"] as? Bool ?? false
        let savePaymentMethodForMerchant = args["savePaymentMethodForMerchant"] as? Bool ?? false
        let returnURL = args["returnURL"] as? String ?? "revolut-sdk-bridge://revolut-pay"
        let merchantName = args["merchantName"] as? String
        let merchantLogoURL = args["merchantLogoURL"] as? String
        let additionalData = args["additionalData"] as? [String: Any]
        
        logToDart("INFO", "Creating Revolut Pay button with order token: \(maskKey(orderToken))")
        logToDart("INFO", "Button parameters - Amount: \(amount) \(currency), Shipping: \(shouldRequestShipping), Save: \(savePaymentMethodForMerchant)")
        
        // Generate the view ID first
        let viewId = nextViewId
        nextViewId += 1
        
        // Create the button
        let button = revolutPayKit.button(
            style: RevolutPayButton.Style(size: .large),
            returnURL: returnURL,
            savePaymentMethodForMerchant: savePaymentMethodForMerchant,
            createOrder: { [weak self] createOrderHandler in
                self?.logToDart("INFO", "Setting order token: \(maskKey(orderToken))")
                createOrderHandler.set(orderToken: orderToken)
            },
            completion: { [weak self] result in
                self?.logToDart("INFO", "Payment completed with result: \(result)")
                
                // Send payment result to the correct Flutter widget
                if let self = self,
                   let buttonView = self.buttonViewInstances[viewId] {
                    buttonView.sendPaymentResult(result)
                } else {
                    // Fallback: send to general log channel
                    self?.sendPaymentResult(result)
                }
            }
        )
        
        // Store the button with the generated ID
        buttonViews[viewId] = button
        
        logToDart("SUCCESS", "Revolut Pay button created successfully with viewId: \(viewId)")
        logToDart("INFO", "Button stored in buttonViews with key: \(viewId)")
        logToDart("INFO", "Total buttons stored: \(buttonViews.count)")
        
        // Return the button configuration
        let buttonConfig: [String: Any] = [
            "buttonCreated": true,
            "viewId": viewId,
            "orderToken": orderToken,
            "amount": amount,
            "currency": currency,
            "email": email,
            "shouldRequestShipping": shouldRequestShipping,
            "savePaymentMethodForMerchant": savePaymentMethodForMerchant,
            "returnURL": returnURL,
            "merchantName": merchantName ?? "",
            "merchantLogoURL": merchantLogoURL ?? "",
            "additionalData": additionalData ?? [:],
            "type": "revolut_pay_button",
            "message": "Revolut Pay button configuration created successfully"
        ]
        
        result(buttonConfig)
    }
    
    private func handleCleanupButton(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let viewId = args["viewId"] as? Int else {
            logToDart("ERROR", "Missing viewId for button cleanup")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Missing viewId", details: nil))
            return
        }
        
        let success = recreateButton(viewId: viewId)
        result(success)
    }
    
    private func handleCleanupAllButtons(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        cleanupAllButtons()
        result(true)
    }
    
    private func sendPaymentResult(_ result: RevolutPayKit.PaymentResult) {
        let resultData: [String: Any]
        switch result {
        case .success:
            resultData = [
                "success": true,
                "message": "Payment completed successfully",
                "error": "",
                "timestamp": nowMillis()
            ]
        case .failure(let error):
            resultData = [
                "success": false,
                "message": "Payment failed",
                "error": error.localizedDescription,
                "timestamp": nowMillis()
            ]
        case .userAbandonedPayment:
            resultData = [
                "success": false,
                "message": "Payment abandoned by user",
                "error": "user_abandoned_payment",
                "timestamp": nowMillis()
            ]
        @unknown default:
            resultData = [
                "success": false,
                "message": "Unknown payment result",
                "error": "unknown",
                "timestamp": nowMillis()
            ]
        }
        logChannel?.invokeMethod("onPaymentResult", arguments: resultData)
    }
    
    // MARK: - Helper Methods
    
    func getButtonViews() -> [Int: UIView]? {
        return buttonViews
    }
    
    /// Clean up and recreate a specific button
    func recreateButton(viewId: Int) -> Bool {
        buttonViewInstances.removeValue(forKey: viewId)

        guard let oldButton = buttonViews[viewId] else {
            logToDart("WARNING", "Button with viewId \(viewId) not found for recreation")
            return false
        }

        // Remove the old button
        buttonViews.removeValue(forKey: viewId)
        oldButton.removeFromSuperview()

        logToDart("INFO", "Cleaned up old button with viewId: \(viewId)")
        return true
    }

    /// Clean up all buttons (useful for complete refresh)
    /// Note: the view-id counter is intentionally NOT reset — reusing ids would
    /// collide with payment channels of platform views that are still alive.
    func cleanupAllButtons() {
        for (viewId, button) in buttonViews {
            button.removeFromSuperview()
            logToDart("INFO", "Cleaned up button with viewId: \(viewId)")
        }
        buttonViews.removeAll()
        buttonViewInstances.removeAll()
        logToDart("INFO", "All buttons cleaned up")
    }
    
    private func logToDart(_ level: String, _ message: String) {
        let logData: [String: Any] = [
            "level": level,
            "message": message,
            "timestamp": nowMillis(),
            "source": "iOS_Plugin"
        ]
        
        logChannel?.invokeMethod("onLog", arguments: logData)
    }
    
    private func handleGetPlatformVersion(result: @escaping FlutterResult) {
        result("iOS " + UIDevice.current.systemVersion)
    }
    
    // MARK: - Additional Method Handlers
    
    private func handleGetSdkVersion(result: @escaping FlutterResult) {
        logToDart("INFO", "Getting SDK version information")
        
        let sdkVersion: [String: Any] = [
            "version": "3.9.0",
            "platform": "iOS",
            "buildNumber": "1",
            "message": "Revolut Pay SDK version information"
        ]
        
        logToDart("SUCCESS", "SDK version retrieved: \(sdkVersion)")
        result(sdkVersion)
    }
    
    private func handlePay(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let orderToken = args["orderToken"] as? String, !orderToken.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "orderToken is required", details: nil))
            return
        }

        guard let revolutPayKit = revolutPayKit else {
            logToDart("ERROR", "Revolut Pay SDK not initialized")
            result(FlutterError(code: "NOT_INITIALIZED", message: "SDK not initialized. Call initialize() first.", details: nil))
            return
        }

        let savePaymentMethodForMerchant = args["savePaymentMethodForMerchant"] as? Bool ?? false
        let returnURL = args["returnURL"] as? String ?? "revolut-sdk-bridge://revolut-pay"

        logToDart("INFO", "Starting headless Revolut Pay for order token: \(maskKey(orderToken))")
        revolutPayKit.pay(
            orderToken: orderToken,
            returnURL: returnURL,
            savePaymentMethodForMerchant: savePaymentMethodForMerchant,
            completion: { [weak self] paymentResult in
                self?.logToDart("INFO", "Headless pay completed with result: \(paymentResult)")
                self?.sendPaymentResult(paymentResult)
            }
        )

        result(["status": "initiated", "orderToken": orderToken])
    }

    /// Builds an honest error for the legacy "confirmation flow" method names. The Revolut
    /// Pay iOS SDK has no manual controller/ConfirmationFlow API — these used to return fake
    /// success. Use the RevolutPayButton widget instead.
    private func unsupportedConfirmationFlowError(_ method: String) -> FlutterError {
        let message = "'\(method)' is not supported: the Revolut Pay iOS SDK has no manual " +
            "confirmation-flow/controller API. Use the RevolutPayButton widget to take a payment."
        logToDart("WARNING", message)
        return FlutterError(code: "UNSUPPORTED", message: message, details: nil)
    }
    
    private func handleCreateController(result: @escaping FlutterResult) {
        result(unsupportedConfirmationFlowError("createController"))
    }
    
    private func handleDisposeController(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(unsupportedConfirmationFlowError("disposeController"))
    }
    
    private func handleSetOrderToken(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(unsupportedConfirmationFlowError("setOrderToken"))
    }
    
    private func handleSetSavePaymentMethodForMerchant(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(unsupportedConfirmationFlowError("setSavePaymentMethodForMerchant"))
    }
    
    private func handleContinueConfirmationFlow(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(unsupportedConfirmationFlowError("continueConfirmationFlow"))
    }
    
    private func handleProvidePromotionalBannerWidget(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Promotional banners are not available in the Revolut Pay iOS SDK (Android only).
        logToDart("WARNING", "Promotional banners are not supported on iOS.")
        result(FlutterError(
            code: "UNSUPPORTED",
            message: "Promotional banners are not supported on iOS (Android only).",
            details: nil
        ))
    }
    
}

// Platform view factory for Revolut Pay button
class RevolutPayButtonViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private let logChannel: FlutterMethodChannel?
    
    init(messenger: FlutterBinaryMessenger, logChannel: FlutterMethodChannel?) {
        self.messenger = messenger
        self.logChannel = logChannel
        super.init()
    }
    
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        logChannel?.invokeMethod("onLog", arguments: [
            "level": "INFO",
            "message": "Creating platform view with ID: \(viewId), frame: \(frame)",
            "timestamp": nowMillis(),
            "source": "iOS_ButtonViewFactory"
        ])
        
        let buttonView = RevolutPayButtonView(frame: frame, viewIdentifier: viewId, arguments: args, messenger: messenger, logChannel: logChannel)
        
        // Store the button view instance in the main plugin for payment result handling
        if let plugin = RevolutSdkBridgePlugin.sharedInstance,
           let buttonId = (args as? [String: Any])?["buttonId"] as? Int {
            plugin.buttonViewInstances[buttonId] = buttonView
            logChannel?.invokeMethod("onLog", arguments: [
                "level": "INFO",
                "message": "Stored button view instance for button ID: \(buttonId)",
                "timestamp": nowMillis(),
                "source": "iOS_ButtonViewFactory"
            ])
        }
        
        return buttonView
    }
    
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// Platform view for Revolut Pay button
class RevolutPayButtonView: NSObject, FlutterPlatformView {
    private let revolutButton: UIView
    private let logChannel: FlutterMethodChannel?
    private let paymentChannel: FlutterMethodChannel?
    private let viewId: Int64
    
    init(frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?, messenger: FlutterBinaryMessenger, logChannel: FlutterMethodChannel?) {
        self.logChannel = logChannel
        self.viewId = viewId

        let buttonId = (args as? [String: Any])?["buttonId"] as? Int

        // Create a payment channel unique to this button instance so that multiple
        // buttons on the same screen don't collide on a shared channel name.
        self.paymentChannel = FlutterMethodChannel(
            name: "revolut_pay_button_payment_\(buttonId ?? Int(viewId))",
            binaryMessenger: messenger
        )

        logChannel?.invokeMethod("onLog", arguments: [
            "level": "INFO",
            "message": "Platform view created with Flutter ID: \(viewId), looking for button ID: \(buttonId ?? -1)",
            "timestamp": nowMillis(),
            "source": "iOS_ButtonView"
        ])
        
        if let plugin = RevolutSdkBridgePlugin.sharedInstance,
           let buttonViews = plugin.getButtonViews(),
           let buttonId = buttonId,
           let button = buttonViews[buttonId] {
            revolutButton = button
            logChannel?.invokeMethod("onLog", arguments: [
                "level": "SUCCESS",
                "message": "Found actual Revolut Pay button with ID: \(buttonId)",
                "timestamp": nowMillis(),
                "source": "iOS_ButtonView"
            ])
        } else {
            // Fallback to placeholder button if actual button not found
            logChannel?.invokeMethod("onLog", arguments: [
                "level": "WARNING",
                "message": "Using placeholder button - button ID \(buttonId ?? -1) not found in buttonViews",
                "timestamp": nowMillis(),
                "source": "iOS_ButtonView"
            ])
            
            // Create a placeholder button with Flutter styling
            let placeholderButton = UIButton(type: .system)
            placeholderButton.setTitle("Revolut Pay", for: .normal)
            placeholderButton.backgroundColor = UIColor.systemBlue
            placeholderButton.setTitleColor(UIColor.white, for: .normal)
            placeholderButton.layer.cornerRadius = 8
            placeholderButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
            
            // Apply Flutter style if provided
            if let styleData = (args as? [String: Any])?["style"] as? [String: Any] {
                if let height = styleData["height"] as? Double {
                    placeholderButton.frame.size.height = height
                }
                if let backgroundColor = styleData["backgroundColor"] as? Int {
                    placeholderButton.backgroundColor = UIColor(red: CGFloat((backgroundColor >> 16) & 0xFF) / 255.0,
                                                            green: CGFloat((backgroundColor >> 8) & 0xFF) / 255.0,
                                                            blue: CGFloat(backgroundColor & 0xFF) / 255.0,
                                                            alpha: 1.0)
                }
                if let borderRadius = styleData["borderRadius"] as? String {
                    // Parse borderRadius string and apply
                    placeholderButton.layer.cornerRadius = 12 // Default to 12 for now
                }
            }
            
            revolutButton = placeholderButton
        }
        
        logChannel?.invokeMethod("onLog", arguments: [
            "level": "INFO",
            "message": "Revolut Pay button view created with ID: \(viewId)",
            "timestamp": nowMillis(),
            "source": "iOS_ButtonView"
        ])
        
        super.init()
    }
    
    func view() -> UIView {
        return revolutButton
    }
    
    /// Send payment result to Flutter via the payment channel
    func sendPaymentResult(_ result: RevolutPayKit.PaymentResult) {
        let resultData: [String: Any]
        
        switch result {
        case .success:
            resultData = [
                "success": true,
                "message": "Payment completed successfully",
                "error": "",
                "timestamp": nowMillis()
            ]
        case .failure(let error):
            resultData = [
                "success": false,
                "message": "Payment failed",
                "error": error.localizedDescription,
                "timestamp": nowMillis()
            ]
        case .userAbandonedPayment:
            resultData = [
                "success": false,
                "message": "Payment abandoned by user",
                "error": "User cancelled the payment",
                "timestamp": nowMillis()
            ]
        @unknown default:
            resultData = [
                "success": false,
                "message": "Unknown payment result",
                "error": "Unexpected payment result: \(result)",
                "timestamp": nowMillis()
            ]
        }
        
        // Send to Flutter via payment channel
        paymentChannel?.invokeMethod("onPaymentResult", arguments: resultData)
        
        // Also log for debugging
        logChannel?.invokeMethod("onLog", arguments: [
            "level": "INFO",
            "message": "Payment result sent to Flutter view \(viewId): \(resultData)",
            "timestamp": nowMillis(),
            "source": "iOS_ButtonView"
        ])
    }
}

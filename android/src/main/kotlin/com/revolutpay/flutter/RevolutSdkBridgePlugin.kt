package com.revolutpay.flutter

import android.app.Activity
import android.content.Context
import android.net.Uri
import android.view.View
import androidx.activity.ComponentActivity
import androidx.annotation.NonNull
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import com.revolut.payments.RevolutPaymentsSDK
import com.revolut.revolutpay.api.PaymentResult
import com.revolut.revolutpay.api.PaymentState
import com.revolut.revolutpay.api.RevolutPaymentController
import com.revolut.revolutpay.api.button.BoxText
import com.revolut.revolutpay.api.button.BoxTextCurrency
import com.revolut.revolutpay.api.button.ButtonParams
import com.revolut.revolutpay.api.button.Radius
import com.revolut.revolutpay.api.button.Size
import com.revolut.revolutpay.api.button.Variant
import com.revolut.revolutpay.api.button.VariantModes
import com.revolut.revolutpay.api.order.OrderParams
import com.revolut.revolutpay.api.order.PreferredMode
import com.revolut.revolutpay.api.order.Customer
import com.revolut.revolutpay.api.revolutPay
import com.revolut.revolutpay.api.bindPaymentState
import com.revolut.revolutpay.api.CountryCode
import com.revolut.revolutpay.api.promobanner.PromoBannerParams
import com.revolut.payments.RevolutCurrency
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

import android.content.Intent
import io.flutter.plugin.common.PluginRegistry.NewIntentListener

class RevolutSdkBridgePlugin: FlutterPlugin, MethodCallHandler, ActivityAware, NewIntentListener {
    companion object {
        // Static instance for platform view access
        var sharedInstance: RevolutSdkBridgePlugin? = null
        private const val CHANNEL_NAME = "revolut_sdk_bridge"
        private const val EVENT_CHANNEL_NAME = "revolut_sdk_bridge_events"
        private const val LOG_CHANNEL_NAME = "revolut_sdk_bridge_logs"
        private const val VIEW_TYPE_BUTTON = "revolut_pay_button"
        private const val VIEW_TYPE_PROMO_BANNER = "revolut_pay_promo_banner"
        private const val TAG = "RevolutSdkBridgePlugin"
    }

    private lateinit var channel : MethodChannel
    private lateinit var eventChannel : EventChannel
    private lateinit var logChannel: MethodChannel
    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private var eventSink: EventSink? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    
    // Storage for active button platform views (used by the platform view layer)
    val buttonViewInstances = mutableMapOf<Int, RevolutPayButtonView>()

    // Controller reused by the one-shot pay() (custom button) flow
    private var oneShotController: RevolutPaymentController? = null
    private var oneShotControllerActivity: ComponentActivity? = null

    private var isInitialized = false
    private var currentEnvironment: RevolutPaymentsSDK.Environment? = null
    private var currentEnvironmentLabel: String? = null
    private var currentMerchantPublicKey: String? = null

    override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        this.flutterPluginBinding = flutterPluginBinding
        context = flutterPluginBinding.applicationContext
        sharedInstance = this
        
        // Setup method channel
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        
        // Setup event channel
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL_NAME)
        eventChannel.setStreamHandler(object : StreamHandler {
            override fun onListen(arguments: Any?, events: EventSink?) {
                eventSink = events
                sendEvent("onEventChannelReady", mapOf("ready" to true))
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        
        // Setup log channel for callbacks
        logChannel = MethodChannel(flutterPluginBinding.binaryMessenger, LOG_CHANNEL_NAME)
        
        // Register platform view factories
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE_BUTTON,
            RevolutPayButtonViewFactory(flutterPluginBinding.binaryMessenger, this)
        )
        flutterPluginBinding.platformViewRegistry.registerViewFactory(
            VIEW_TYPE_PROMO_BANNER,
            RevolutPayPromoBannerViewFactory(this)
        )
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "init" -> handleInitialize(call, result)
            "getPlatformVersion" -> handleGetPlatformVersion(call, result)
            "getSdkVersion" -> handleGetSdkVersion(call, result)
            "pay" -> handlePay(call, result)
            // The Revolut Pay Lite SDK exposes no manual "confirmation flow" / controller
            // API. These method names used to be fake stubs that returned success without
            // doing anything. They now fail honestly — use the RevolutPayButton widget for
            // the standard flow, or pay() to drive your own button.
            "createController",
            "disposeController",
            "setOrderToken",
            "setSavePaymentMethodForMerchant",
            "continueConfirmationFlow" -> handleUnsupportedConfirmationFlow(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleInitialize(call: MethodCall, result: Result) {
        try {
            val args = call.arguments as? Map<String, Any>
            val merchantPublicKey = args?.get("merchantPublicKey") as? String
            
            if (merchantPublicKey.isNullOrEmpty()) {
                logToDart("ERROR", "Missing merchant public key in initialization")
                result.error("INVALID_ARGUMENTS", "Missing merchant public key", null)
                return
            }
            
            // Validate merchant key format
            if (merchantPublicKey.isEmpty()) {
                logToDart("ERROR", "Merchant public key cannot be empty")
                result.error("INVALID_ARGUMENTS", "Merchant public key cannot be empty", null)
                return
            }
            
            // Test with invalid keys to see if validation works
            if (merchantPublicKey == "test" || merchantPublicKey == "invalid" || merchantPublicKey.length < 10) {
                logToDart("WARNING", "Using potentially invalid merchant key: $merchantPublicKey")
            }
            
            // Get environment from arguments (default to sandbox)
            val environmentRaw = (args?.get("environment") as? String)?.trim()
            val normalizedEnvironment = environmentRaw?.lowercase()
            val resolvedEnvironment = when (normalizedEnvironment) {
                "production", "prod", "live", "main" -> "production"
                "sandbox", "test", "testing", "dev", "development", null -> "sandbox"
                else -> {
                    logToDart("WARNING", "Unknown environment '$environmentRaw', defaulting to sandbox")
                    "sandbox"
                }
            }
            val revolutEnvironment = if (resolvedEnvironment == "production") {
                RevolutPaymentsSDK.Environment.PRODUCTION
            } else {
                RevolutPaymentsSDK.Environment.SANDBOX
            }

            currentMerchantPublicKey = merchantPublicKey
            currentEnvironment = revolutEnvironment
            currentEnvironmentLabel = resolvedEnvironment
            
            logToDart(
                "INFO",
                "Initializing Revolut Pay SDK with merchant     public key: $merchantPublicKey, " +
                    "environmentArg=${environmentRaw ?: "null"} resolved=$resolvedEnvironment"
            )
            
            // Configure the SDK according to official documentation
            RevolutPaymentsSDK.configure(
                RevolutPaymentsSDK.Configuration(
                    merchantPublicKey = merchantPublicKey,
                    environment = revolutEnvironment
                )
            )

            logCurrentConfiguration("handleInitialize")
            
            logToDart("INFO", "SDK configuration applied - testing functionality...")
            
            // REAL VALIDATION: Test if SDK is properly configured
            logToDart("INFO", "Testing RevolutPay SDK functionality...")
            
            isInitialized = true
            
            logToDart(
                "INFO",
                "Revolut Pay SDK initialization complete | environment=$resolvedEnvironment " +
                    "(sdk=${revolutEnvironment.name}) | merchantKey=${maskMerchantKey(merchantPublicKey)}"
            )

            logToDart("SUCCESS", "Revolut Pay SDK initialized successfully with merchant key: $merchantPublicKey")
            result.success(true)
        } catch (e: Exception) {
            logToDart("ERROR", "Failed to initialize Revolut SDK: ${e.message}")
            result.error("INIT_ERROR", "Failed to initialize Revolut SDK: ${e.message}", null)
        }
    }

    private fun handleGetSdkVersion(call: MethodCall, result: Result) {
        try {
            // Reports the bundled native Revolut Pay (Lite) SDK version.
            result.success(mapOf(
                "version" to "3.2.0",
                "platform" to "Android",
                "buildNumber" to "1"
            ))
        } catch (e: Exception) {
            result.error("GET_SDK_VERSION_ERROR", "Failed to get SDK version: ${e.message}", null)
        }
    }

    private fun handleGetPlatformVersion(call: MethodCall, result: Result) {
        try {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        } catch (e: Exception) {
            result.error("GET_PLATFORM_VERSION_ERROR", "Failed to get platform version: ${e.message}", null)
        }
    }

    /**
     * One-shot payment for merchants that render their own ("custom") button.
     *
     * Mirrors Revolut's official Lite SDK "custom button" sample: a
     * [RevolutPaymentController] is bound to the host Activity, then
     * controller.pay(OrderParams) is invoked. The host Activity MUST be a
     * ComponentActivity (use FlutterFragmentActivity). The final outcome is
     * delivered asynchronously over the event channel (onOrderCompleted /
     * onOrderFailed / onUserPaymentAbandoned); this call only reports that the
     * flow was started.
     */
    private fun handlePay(call: MethodCall, result: Result) {
        try {
            if (!isInitialized) {
                result.error("NOT_INITIALIZED", "SDK not initialized. Call init() first.", null)
                return
            }

            val orderToken = call.argument<String>("orderToken") ?: ""
            if (orderToken.isEmpty()) {
                result.error("INVALID_ARGUMENTS", "orderToken is required", null)
                return
            }
            val savePaymentMethodForMerchant = call.argument<Boolean>("savePaymentMethodForMerchant") ?: false
            val requestShipping = call.argument<Boolean>("shouldRequestShipping") ?: false
            val returnUrlString = call.argument<String>("returnURL") ?: "revolut-sdk-bridge://revolut-pay"
            val preferredMode = resolvePreferredMode(call.argument<String>("preferredMode"))

            val activity = activityBinding?.activity
            if (activity !is ComponentActivity) {
                logToDart(
                    "ERROR",
                    "pay() requires the host Activity to be a ComponentActivity. " +
                        "Make MainActivity extend FlutterFragmentActivity."
                )
                result.error(
                    "ACTIVITY_NOT_SUPPORTED",
                    "Host Activity must be a ComponentActivity (extend FlutterFragmentActivity) to take payments.",
                    null
                )
                return
            }

            val returnUri = runCatching { Uri.parse(returnUrlString) }.getOrNull()
            if (returnUri == null) {
                result.error("INVALID_ARGUMENTS", "Invalid returnURL: $returnUrlString", null)
                return
            }

            val controller = ensureOneShotController(activity)
            if (controller == null) {
                result.error("CONTROLLER_UNAVAILABLE", "Unable to create Revolut payment controller.", null)
                return
            }

            val orderParams = OrderParams(
                orderToken = orderToken,
                returnUri = returnUri,
                requestShipping = requestShipping,
                savePaymentMethodForMerchant = savePaymentMethodForMerchant,
                customer = null,
                preferredMode = preferredMode
            )

            logToDart("INFO", "Starting one-shot payment for order token: $orderToken")
            controller.pay(orderParams)

            // The real outcome arrives asynchronously through the event channel.
            result.success(mapOf(
                "status" to "initiated",
                "orderToken" to orderToken
            ))
            sendEvent("onPaymentStatusUpdate", mapOf(
                "status" to "initiated",
                "orderToken" to orderToken
            ))
        } catch (e: Exception) {
            logToDart("ERROR", "Failed to initiate payment: ${e.message}")
            result.error("PAY_ERROR", "Failed to initiate payment: ${e.message}", null)
        }
    }

    /** Lazily creates (and reuses) a payment controller bound to the host Activity. */
    private fun ensureOneShotController(activity: ComponentActivity): RevolutPaymentController? {
        val existing = oneShotController
        if (existing != null && oneShotControllerActivity === activity) {
            return existing
        }
        return try {
            val controller = RevolutPaymentsSDK.revolutPay.createController(activity) { paymentResult ->
                handleOneShotPaymentResult(paymentResult)
            }
            oneShotController = controller
            oneShotControllerActivity = activity
            controller
        } catch (e: Exception) {
            logToDart("ERROR", "Failed to create payment controller: ${e.message}")
            null
        }
    }

    private fun handleOneShotPaymentResult(paymentResult: PaymentResult) {
        when (paymentResult) {
            PaymentResult.Success -> sendEvent(
                "onOrderCompleted",
                mapOf<String, Any>("success" to true, "timestamp" to System.currentTimeMillis())
            )
            is PaymentResult.UserAbandonedPayment -> sendEvent(
                "onUserPaymentAbandoned",
                mapOf<String, Any>("success" to false, "timestamp" to System.currentTimeMillis())
            )
            is PaymentResult.Failure -> sendEvent(
                "onOrderFailed",
                mapOf<String, Any>(
                    "success" to false,
                    "error" to (paymentResult.exception.message ?: "payment_failure"),
                    "cause" to (paymentResult.exception.message ?: "payment_failure"),
                    "timestamp" to System.currentTimeMillis()
                )
            )
        }
    }

    /**
     * Honest failure for the legacy "confirmation flow" method names. The Revolut Pay
     * Lite SDK has no manual controller/ConfirmationFlow API — these used to return fake
     * success. Use the RevolutPayButton widget, or pay() for a custom button.
     */
    private fun handleUnsupportedConfirmationFlow(call: MethodCall, result: Result) {
        val message = "'${call.method}' is not supported: the Revolut Pay Lite SDK has no manual " +
            "confirmation-flow/controller API. Use the RevolutPayButton widget for the standard flow, " +
            "or pay() to drive your own custom button."
        logToDart("WARNING", message)
        result.error("UNSUPPORTED", message, null)
    }

    private fun sendEvent(method: String, data: Map<String, Any>) {
        try {
            eventSink?.success(mapOf(
                "method" to method,
                "data" to data
            ))
        } catch (e: Exception) {
            // Log the error but don't crash
            android.util.Log.w("RevolutSdkBridge", "Failed to send event: $method", e)
        }
    }
    
    // Public method for platform view to access sendEvent
    fun sendEventPublic(method: String, data: Map<String, Any>) {
        sendEvent(method, data)
    }
    
    private fun logToDart(level: String, message: String) {
        try {
            val logData = mapOf(
                "level" to level,
                "message" to message,
                "timestamp" to (System.currentTimeMillis() / 1000.0),
                "source" to "Android_Plugin"
            )
            
            logChannel.invokeMethod("onLog", logData)
        } catch (e: Exception) {
            // Fallback to console logging if logChannel fails
            android.util.Log.w("RevolutSdkBridge", "[$level] $message", e)
        }
    }

    private fun maskMerchantKey(key: String?): String {
        if (key.isNullOrBlank()) return "UNSET"
        if (key.length <= 6) return "****${key.takeLast(2)}"
        val prefix = key.take(4)
        val suffix = key.takeLast(4)
        return "$prefix...$suffix (len=${key.length})"
    }

    private fun logCurrentConfiguration(origin: String) {
        val envLabel = currentEnvironmentLabel?.lowercase() ?: "unset"
        val sdkEnv = currentEnvironment?.name ?: "UNKNOWN"
        val maskedKey = maskMerchantKey(currentMerchantPublicKey)
        val message = "$origin | environment=$envLabel (sdk=$sdkEnv) | merchantKey=$maskedKey"
        android.util.Log.i(TAG, message)
        logToDart("INFO", message)
    }

    fun publishCurrentConfiguration(origin: String) {
        logCurrentConfiguration(origin)
    }
    
    // Public method for platform view to access logging
    fun logToDartPublic(level: String, message: String) {
        logToDart(level, message)
    }
    
    fun getActivity(): Activity? = activityBinding?.activity

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        sharedInstance = null
        flutterPluginBinding = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        intent.data?.let { uri ->
            logToDart("INFO", "Handling new intent with URI: $uri")
            RevolutPaymentsSDK.revolutPay.handle(uri)
            return true
        }
        return false
    }
}

/** Platform view factory for Revolut Pay button */
class RevolutPayButtonViewFactory(
    private val messenger: io.flutter.plugin.common.BinaryMessenger,
    private val plugin: RevolutSdkBridgePlugin
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    
    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String, Any?>
        return RevolutPayButtonView(context!!, viewId, creationParams, messenger, plugin)
    }
}

/** Platform view for Revolut Pay button */
class RevolutPayButtonView(
    private val context: Context,
    private val viewId: Int,
    creationParams: Map<String, Any?>?,
    private val messenger: io.flutter.plugin.common.BinaryMessenger,
    private val plugin: RevolutSdkBridgePlugin
) : PlatformView {
    
    companion object {
        private const val TAG = "RevolutPayButton"
    }

    private lateinit var buttonView: View
    private val paymentChannel: MethodChannel
    private var orderToken: String? = null
    private var returnUrl: String? = null
    private var shouldRequestShipping: Boolean = false
    private var savePaymentMethodForMerchant: Boolean = false
    private var preferredMode: String? = null
    private var paymentController: RevolutPaymentController? = null
    private var componentActivity: ComponentActivity? = null
    private var revolutPayButton: com.revolut.revolutpay.api.RevolutPayButton? = null
    private var isPaymentInProgress: Boolean = false
    private var lifecycleObserver: DefaultLifecycleObserver? = null
    private var paymentStateJob: Job? = null

    init {
        android.util.Log.i(TAG, "═══════════════════════════════════════")
        android.util.Log.i(TAG, "🆕 >>> RevolutPayButtonView INIT START (viewId: $viewId)")
        android.util.Log.i(TAG, "═══════════════════════════════════════")
        
        paymentChannel = MethodChannel(messenger, "revolut_pay_button_payment_$viewId")
        android.util.Log.d(TAG, ">>> INIT: Payment channel created")

        val params = creationParams ?: emptyMap()
        android.util.Log.d(TAG, ">>> INIT: Creation params: $params")
        orderToken = params["orderToken"] as? String
        returnUrl = params["returnURL"] as? String
        shouldRequestShipping = params["shouldRequestShipping"] as? Boolean ?: false
        savePaymentMethodForMerchant = params["savePaymentMethodForMerchant"] as? Boolean ?: false
        preferredMode = params["preferredMode"] as? String

        val buttonParamsMap = (params["buttonParams"] as? Map<*, *>)?.toStringAnyMap()

        plugin.logToDartPublic(
            "INFO",
            "Creating platform view with ID: $viewId, orderToken: $orderToken"
        )

        buttonView = try {
            createRevolutPayButtonInView(context, buttonParamsMap)
        } catch (e: Exception) {
            plugin.logToDartPublic("ERROR", "Failed to create Revolut Pay button: ${e.message}")
            createPlaceholderButton(context)
        }

        plugin.buttonViewInstances[viewId] = this
        android.util.Log.d(TAG, ">>> INIT: View instance stored, starting controller initialization...")
        plugin.publishCurrentConfiguration("RevolutPayButtonView.init(viewId=$viewId)")
        
        initializeController()
        
        android.util.Log.i(TAG, "═══════════════════════════════════════")
        android.util.Log.i(TAG, "✅ >>> RevolutPayButtonView INIT COMPLETE (viewId: $viewId)")
        android.util.Log.i(TAG, "═══════════════════════════════════════")
    }

    private fun createPlaceholderButton(context: Context): View = View(context).apply {
        setBackgroundColor(android.graphics.Color.parseColor("#0075EB"))
        minimumHeight = 200
        minimumWidth = 400

        setOnClickListener {
            plugin.logToDartPublic("INFO", "Placeholder button clicked")
            handleButtonClick()
        }
    }

    private fun createRevolutPayButtonInView(
        context: Context,
        params: Map<String, Any?>?
    ): View {
        android.util.Log.d(TAG, ">>> createRevolutPayButtonInView: START")
        val resolvedParams = buildButtonParams(params)
        android.util.Log.d(TAG, ">>> createRevolutPayButtonInView: Calling SDK provideButton...")
        
        val button = RevolutPaymentsSDK.revolutPay.provideButton(
            context = context,
            params = resolvedParams
        )
        android.util.Log.d(TAG, ">>> createRevolutPayButtonInView: Button created successfully!")
        
        revolutPayButton = button
        button.setOnClickListener {
            android.util.Log.i(TAG, "🔵 >>> BUTTON CLICKED! <<<")
            plugin.logToDartPublic("INFO", "Native Revolut Pay button clicked")
            handleButtonClick()
        }
        android.util.Log.d(TAG, ">>> createRevolutPayButtonInView: Click listener attached - DONE")
        return button
    }

    private fun handleButtonClick() {
        android.util.Log.i(TAG, "🟢 >>> handleButtonClick: START - orderToken=$orderToken")
        plugin.publishCurrentConfiguration("handleButtonClick(viewId=$viewId)")
        
        // Prevent multiple simultaneous payment attempts
        if (isPaymentInProgress) {
            android.util.Log.w(TAG, "⚠️ >>> handleButtonClick: Payment already in progress, ignoring click")
            plugin.logToDartPublic("WARNING", "Payment already in progress, ignoring duplicate click")
            return
        }
        
        isPaymentInProgress = true
        android.util.Log.d(TAG, ">>> handleButtonClick: Payment in progress flag set to TRUE")
        revolutPayButton?.showBlockingLoading(true)
        
        plugin.logToDartPublic("INFO", "Processing button click, order token: $orderToken")
        
        android.util.Log.d(TAG, ">>> handleButtonClick: Sending onButtonClick event...")
        plugin.sendEventPublic(
            "onButtonClick",
            mapOf(
                "buttonId" to viewId.toString(),
                "orderToken" to (orderToken ?: ""),
                "timestamp" to System.currentTimeMillis()
            )
        )
        android.util.Log.d(TAG, ">>> handleButtonClick: Event sent, calling startPayment()...")
        startPayment()
        android.util.Log.i(TAG, "🟢 >>> handleButtonClick: END")
    }

    private fun startPayment() {
        android.util.Log.i(TAG, "🚀 >>> startPayment: START")
        plugin.publishCurrentConfiguration("startPayment(viewId=$viewId)")
        
        val controller = paymentController
        val token = orderToken
        
        android.util.Log.d(TAG, ">>> startPayment: Checking controller... controller=${if (controller != null) "EXISTS" else "NULL"}")
        if (controller == null) {
            android.util.Log.e(TAG, "❌ >>> startPayment: Controller is NULL! Cannot proceed.")
            plugin.logToDartPublic("ERROR", "Payment controller unavailable for view $viewId")
            sendPaymentResult(false, "Payment controller unavailable", "controller_unavailable")
            return
        }
        android.util.Log.d(TAG, "✅ >>> startPayment: Controller OK")

        android.util.Log.d(TAG, ">>> startPayment: Checking token... token=$token")
        if (token.isNullOrBlank()) {
            android.util.Log.e(TAG, "❌ >>> startPayment: Token is NULL or BLANK!")
            plugin.logToDartPublic("ERROR", "Missing order token for view $viewId")
            sendPaymentResult(false, "Order token is missing", "missing_order_token")
            return
        }
        android.util.Log.d(TAG, "✅ >>> startPayment: Token OK: $token")

        val uriString = returnUrl ?: "revolut-sdk-bridge://revolut-pay"
        android.util.Log.d(TAG, ">>> startPayment: Parsing return URI: $uriString")
        val returnUri = runCatching { Uri.parse(uriString) }.getOrNull()
        if (returnUri == null) {
            android.util.Log.e(TAG, "❌ >>> startPayment: Failed to parse URI: $uriString")
            plugin.logToDartPublic("ERROR", "Invalid return URI: $uriString")
            sendPaymentResult(false, "Invalid return URI", "invalid_return_uri")
            return
        }
        android.util.Log.d(TAG, "✅ >>> startPayment: Return URI OK: $returnUri")

        android.util.Log.d(TAG, ">>> startPayment: Building OrderParams...")
        android.util.Log.d(TAG, ">>> startPayment: Parameters - token=$token, returnUri=$returnUri, requestShipping=$shouldRequestShipping, savePaymentMethod=$savePaymentMethodForMerchant")
        
        val orderParams = OrderParams(
            orderToken = token,
            returnUri = returnUri,
            requestShipping = shouldRequestShipping,
            savePaymentMethodForMerchant = savePaymentMethodForMerchant,
            customer = null,
            preferredMode = resolvePreferredMode(preferredMode)
        )
        android.util.Log.d(TAG, "✅ >>> startPayment: OrderParams built successfully")
        android.util.Log.d(TAG, ">>> startPayment: OrderParams object: $orderParams")
        android.util.Log.d(TAG, ">>> startPayment: Controller object: $controller")
        android.util.Log.d(TAG, ">>> startPayment: Controller class: ${controller.javaClass.name}")

        android.util.Log.w(TAG, "═══════════════════════════════════════")
        android.util.Log.w(TAG, "🔥🔥🔥 >>> ABOUT TO CALL controller.pay()! 🔥🔥🔥")
        android.util.Log.w(TAG, "═══════════════════════════════════════")
        
        try {
            android.util.Log.w(TAG, ">>> Entering try block for controller.pay()...")
            controller.pay(orderParams)
            android.util.Log.w(TAG, "═══════════════════════════════════════")
            android.util.Log.w(TAG, "✅✅✅ >>> controller.pay() RETURNED SUCCESSFULLY!")
            android.util.Log.w(TAG, "═══════════════════════════════════════")
            android.util.Log.w(TAG, ">>> Payment UI should be opening NOW...")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "═══════════════════════════════════════")
            android.util.Log.e(TAG, "❌❌❌ >>> controller.pay() THREW EXCEPTION!")
            android.util.Log.e(TAG, "═══════════════════════════════════════")
            android.util.Log.e(TAG, ">>> Exception type: ${e.javaClass.simpleName}")
            android.util.Log.e(TAG, ">>> Exception message: ${e.message}")
            e.printStackTrace()
            sendPaymentResult(false, "Payment failed to start", e.message ?: "unknown_error")
            return
        }
        
        android.util.Log.i(TAG, "🚀 >>> startPayment: END")
    }

    private fun sendPaymentResult(success: Boolean, message: String, error: String?) {
        val resultData = mapOf(
            "success" to success,
            "message" to message,
            "error" to (error ?: ""),
            "timestamp" to (System.currentTimeMillis() / 1000.0),
            "viewId" to viewId,
            "orderToken" to (orderToken ?: "")
        )

        // CRITICAL: Reset payment in progress flag to allow future payments
        isPaymentInProgress = false
        android.util.Log.d(TAG, ">>> sendPaymentResult: Payment in progress flag reset to FALSE")

        // CRITICAL: Always hide the loading indicator when sending results
        // This prevents infinite loading states on errors
        revolutPayButton?.showBlockingLoading(false)
        android.util.Log.d(TAG, ">>> sendPaymentResult: Hiding blocking loading indicator")

        paymentChannel.invokeMethod("onPaymentResult", resultData)

        if (success) {
            plugin.sendEventPublic(
                "onOrderCompleted",
                mapOf<String, Any>(
                    "success" to true,
                    "orderId" to (orderToken ?: ""),
                    "orderToken" to (orderToken ?: ""),
                    "timestamp" to System.currentTimeMillis(),
                    "additionalData" to resultData
                )
            )
        } else {
            plugin.sendEventPublic(
                "onOrderFailed",
                mapOf<String, Any>(
                    "success" to false,
                    "error" to (error ?: ""),
                    "cause" to (error ?: ""),
                    "timestamp" to System.currentTimeMillis(),
                    "additionalData" to resultData
                )
            )
        }

        plugin.logToDartPublic("INFO", "Payment result sent to Flutter: $resultData")
    }

    private fun initializeController() {
        android.util.Log.i(TAG, "🎯 >>> initializeController: START")
        plugin.publishCurrentConfiguration("initializeController(viewId=$viewId)")
        
        // Prevent duplicate controller initialization
        if (paymentController != null) {
            android.util.Log.w(TAG, "⚠️ >>> initializeController: Controller already exists, skipping re-initialization")
            return
        }
        
        val activity = plugin.getActivity()
        android.util.Log.d(TAG, ">>> initializeController: Got activity: ${activity?.javaClass?.simpleName}")
        android.util.Log.d(TAG, ">>> initializeController: Activity full class: ${activity?.javaClass?.name}")
        android.util.Log.d(TAG, ">>> initializeController: Activity superclass: ${activity?.javaClass?.superclass?.simpleName}")
        
        // Check the full inheritance chain
        activity?.javaClass?.let { clazz ->
            android.util.Log.d(TAG, ">>> Activity inheritance chain:")
            var currentClass: Class<*>? = clazz
            var level = 0
            while (currentClass != null && level < 10) {
                android.util.Log.d(TAG, ">>>   [$level] ${currentClass.simpleName}")
                currentClass = currentClass.superclass
                level++
            }
        }
        
        if (activity !is ComponentActivity) {
            android.util.Log.e(TAG, "❌ >>> initializeController: Activity is NOT ComponentActivity! It's: ${activity?.javaClass?.simpleName}")
            android.util.Log.e(TAG, "❌ >>> This means MainActivity.kt hasn't been rebuilt yet or doesn't extend FlutterFragmentActivity")
            android.util.Log.e(TAG, "❌ >>> Please UNINSTALL the app and rebuild: adb uninstall com.example.revolut_sdk_bridge_example && flutter run")
            plugin.logToDartPublic(
                "WARNING",
                "Host activity is not a ComponentActivity; payment controller unavailable"
            )
            return
        }
        android.util.Log.w(TAG, "✅✅✅ >>> initializeController: Activity IS ComponentActivity!")

        componentActivity = activity

        lifecycleObserver?.let { existing ->
            activity.lifecycle.removeObserver(existing)
        }
        
        android.util.Log.d(TAG, ">>> initializeController: Creating payment controller...")
        try {
            paymentController = RevolutPaymentsSDK.revolutPay.createController(activity) { result ->
                android.util.Log.i(TAG, "💰 >>> Payment result callback received: ${result.javaClass.simpleName}")
                handlePaymentResult(result)
            }
            android.util.Log.w(TAG, "🎉🎉🎉 >>> initializeController: Payment controller CREATED successfully!")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "❌❌❌ >>> initializeController: FAILED to create controller!", e)
            return
        }

        val observer = object : DefaultLifecycleObserver {
            override fun onResume(owner: LifecycleOwner) {
                val state = paymentController?.paymentState?.value
                val isProcessingState = state is PaymentState.Processing
                android.util.Log.d(
                    TAG,
                    ">>> Lifecycle onResume(viewId=$viewId) | paymentState=${state?.javaClass?.simpleName ?: "null"} | processing=$isProcessingState"
                )

                if (!isProcessingState) {
                    if (isPaymentInProgress) {
                        android.util.Log.d(TAG, ">>> Lifecycle onResume: resetting payment progress flag")
                    }
                    isPaymentInProgress = false
                    revolutPayButton?.showBlockingLoading(false)
                }
            }

            override fun onDestroy(owner: LifecycleOwner) {
                owner.lifecycle.removeObserver(this)
                if (lifecycleObserver === this) {
                    lifecycleObserver = null
                }
            }
        }
        activity.lifecycle.addObserver(observer)
        lifecycleObserver = observer

        android.util.Log.d(TAG, ">>> initializeController: Subscribing to payment state updates...")
        val controller = paymentController
        val button = revolutPayButton
        if (controller == null || button == null) {
            android.util.Log.w(TAG, "⚠️ >>> initializeController: Missing controller ($controller) or button ($button), skipping state subscription")
        } else {
            android.util.Log.d(TAG, ">>> initializeController: Binding payment state to button")
            button.bindPaymentState(controller, activity)

            paymentStateJob?.cancel()
            paymentStateJob = activity.lifecycleScope.launch {
                controller.paymentState.collectLatest { state ->
                    val isProcessingState = state is PaymentState.Processing
                    android.util.Log.d(
                        TAG,
                        ">>> paymentState update(viewId=$viewId): ${state.javaClass.simpleName} | inProgress=$isPaymentInProgress"
                    )
                    if (!isProcessingState && isPaymentInProgress) {
                        android.util.Log.d(TAG, ">>> paymentState update: state not processing, resetting progress flag")
                        isPaymentInProgress = false
                    }
                }
            }
        }
        
        android.util.Log.i(TAG, "🎯 >>> initializeController: END")
    }

    private fun handlePaymentResult(result: PaymentResult) {
        android.util.Log.i(TAG, "💰 >>> handlePaymentResult: START - result type: ${result.javaClass.simpleName}")
        
        when (result) {
            PaymentResult.Success -> {
                android.util.Log.w(TAG, "🎉🎉🎉 >>> handlePaymentResult: SUCCESS!")
                sendPaymentResult(true, "Payment completed successfully", null)
            }
            is PaymentResult.UserAbandonedPayment -> {
                android.util.Log.w(TAG, "⚠️ >>> handlePaymentResult: User abandoned payment")
                sendPaymentResult(
                    success = false,
                    message = "Payment abandoned by user",
                    error = "user_abandoned_payment"
                )
            }
            is PaymentResult.Failure -> {
                android.util.Log.e(TAG, "❌ >>> handlePaymentResult: FAILURE - ${result.exception.message}", result.exception)
                sendPaymentResult(
                    success = false,
                    message = "Payment failed",
                    error = result.exception.message ?: "payment_failure"
                )
            }
        }

        // Note: Loading indicator is now hidden in sendPaymentResult()
        android.util.Log.i(TAG, "💰 >>> handlePaymentResult: END")
    }

    private fun buildButtonParams(params: Map<String, Any?>?): ButtonParams {
        val radius = enumValueOrDefault(params?.get("radius") as? String, Radius.MEDIUM)
        val size = enumValueOrDefault(params?.get("size") as? String, Size.LARGE)
        val boxText = enumValueOrDefault(params?.get("boxText") as? String, BoxText.NONE)

        val variantMap = params?.get("variantModes") as? Map<*, *>
        val lightVariant = enumValueOrDefault(
            variantMap?.get("lightTheme") as? String,
            Variant.DARK
        )
        val darkVariant = enumValueOrDefault(
            variantMap?.get("darkTheme") as? String,
            Variant.LIGHT
        )

        val currency = (params?.get("boxTextCurrency") as? String)?.uppercase()
            ?.let { enumValueOrNull<BoxTextCurrency>(it) } ?: BoxTextCurrency.GBP

        return ButtonParams(
            radius = radius,
            buttonSize = size,
            variantModes = VariantModes(lightMode = lightVariant, darkMode = darkVariant),
            boxText = boxText,
            boxTextCurrency = currency
        )
    }

    override fun getView(): View = buttonView

    override fun dispose() {
        paymentChannel.setMethodCallHandler(null)
        lifecycleObserver?.let { observer ->
            componentActivity?.lifecycle?.removeObserver(observer)
        }
        lifecycleObserver = null
        paymentStateJob?.cancel()
        paymentStateJob = null
        isPaymentInProgress = false
        revolutPayButton?.showBlockingLoading(false)
        paymentController = null
        revolutPayButton = null
        componentActivity = null
        plugin.buttonViewInstances.remove(viewId)
    }

    private fun Map<*, *>?.toStringAnyMap(): Map<String, Any?>? {
        if (this == null) return null
        return entries.mapNotNull { (key, value) ->
            key?.toString()?.let { it to value }
        }.toMap()
    }

    private inline fun <reified T : Enum<T>> enumValueOrDefault(
        value: String?,
        default: T
    ): T = enumValueOrNull<T>(value) ?: default

    private inline fun <reified T : Enum<T>> enumValueOrNull(value: String?): T? {
        if (value.isNullOrBlank()) return null
        return runCatching { enumValueOf<T>(value.uppercase()) }.getOrNull()
    }
}

/** Platform view factory for the Revolut Pay promotional banner */
class RevolutPayPromoBannerViewFactory(
    private val plugin: RevolutSdkBridgePlugin
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context?, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val creationParams = args as? Map<String, Any?>
        return RevolutPayPromoBannerView(context!!, creationParams, plugin)
    }
}

/**
 * Platform view that renders the native Revolut Pay promotional banner via
 * RevolutPaymentsSDK.revolutPay.providePromotionalBannerWidget(...).
 *
 * The promotional banner requires customer details (email, phone, country) — unlike the
 * pay button, it cannot be rendered without them.
 */
class RevolutPayPromoBannerView(
    private val context: Context,
    creationParams: Map<String, Any?>?,
    private val plugin: RevolutSdkBridgePlugin
) : PlatformView {

    private val bannerView: View

    init {
        bannerView = try {
            buildBanner(creationParams)
        } catch (e: Exception) {
            plugin.logToDartPublic("ERROR", "Failed to create promotional banner: ${e.message}")
            View(context)
        }
    }

    private fun buildBanner(params: Map<String, Any?>?): View {
        val promo = (params?.get("promoParams") as? Map<*, *>)?.mapKeys { it.key.toString() }
            ?: throw IllegalArgumentException("Missing promoParams")

        val transactionId = promo["transactionId"] as? String
            ?: throw IllegalArgumentException("Missing transactionId")

        val paymentAmount = when (val amount = promo["paymentAmount"]) {
            is Int -> amount.toLong()
            is Long -> amount
            is Double -> amount.toLong()
            is String -> amount.toLongOrNull() ?: 0L
            else -> 0L
        }

        val currency = (promo["currency"] as? String)?.uppercase()
            ?.let { runCatching { RevolutCurrency.valueOf(it) }.getOrNull() }
            ?: RevolutCurrency.GBP

        val customerMap = (promo["customer"] as? Map<*, *>)?.mapKeys { it.key.toString() }
            ?: throw IllegalArgumentException(
                "Promotional banner requires customer details (email, phone, country)"
            )

        val countryCode = resolveCountryCode(customerMap["country"] as? String)

        val customer = Customer(
            name = customerMap["name"] as? String,
            phone = (customerMap["phone"] as? String).orEmpty(),
            email = (customerMap["email"] as? String).orEmpty(),
            dateOfBirth = null,
            country = countryCode
        )

        val bannerParams = PromoBannerParams(
            transactionId = transactionId,
            currency = currency,
            paymentAmount = paymentAmount,
            customer = customer
        )

        // themeId is an Android style resource (R.style.*) and is optional, so we rely on the
        // SDK default theme. A Dart-side string cannot map to a resource id; if you need a
        // custom banner theme, pass a style resource here and rebuild.
        return RevolutPaymentsSDK.revolutPay.providePromotionalBannerWidget(
            context = context,
            params = bannerParams
        )
    }

    private fun resolveCountryCode(code: String?): CountryCode {
        val normalized = code?.trim()?.uppercase()
        if (normalized.isNullOrEmpty()) return CountryCode.GB
        return runCatching {
            val companion = CountryCode.Companion
            val getter = companion::class.java.getMethod("get$normalized")
            getter.invoke(companion) as CountryCode
        }.getOrDefault(CountryCode.GB)
    }

    override fun getView(): View = bannerView

    override fun dispose() {}
}

private fun resolvePreferredMode(value: String?): PreferredMode = when (value?.trim()?.lowercase()) {
    "retailonly", "retail-only", "retail_only" -> PreferredMode.RetailOnly
    "business" -> PreferredMode.Business
    "businessonly", "business-only", "business_only" -> PreferredMode.BusinessOnly
    else -> PreferredMode.Retail
}

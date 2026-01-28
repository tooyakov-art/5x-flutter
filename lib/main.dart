import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
// NOTE: flutter_windowmanager_plus removed - was causing iOS crash
// Screen protection disabled for now, will re-add with platform channels later

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase BEFORE runApp - CRITICAL for auth
  try {
    await Firebase.initializeApp();
    print("✅ Firebase initialized successfully");
  } catch (e) {
    print("⚠️ Firebase init error: $e");
  }

  // Catch any unhandled Flutter errors
  FlutterError.onError = (FlutterErrorDetails details) {
    print("❌ Flutter error: ${details.exception}");
    FlutterError.presentError(details);
  };

  runApp(const MaterialApp(
    home: X5BridgeApp(),
    debugShowCheckedModeBanner: false,
  ));
}

class X5BridgeApp extends StatefulWidget {
  const X5BridgeApp({super.key});

  @override
  State<X5BridgeApp> createState() => _X5BridgeAppState();
}

class _X5BridgeAppState extends State<X5BridgeApp> with SingleTickerProviderStateMixin {
  InAppPurchase? _inAppPurchase;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  String? _loadError;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  bool _screenProtectionEnabled = false;

  // 🛡️ SCREEN PROTECTION - DISABLED
  // flutter_windowmanager_plus was causing iOS crash
  // TODO: Re-implement with platform channels
  Future<void> _enableScreenProtection() async {
    if (!Platform.isAndroid) return;
    print("🛡️ Screen protection disabled (package removed)");
  }

  Future<void> _disableScreenProtection() async {
    if (!Platform.isAndroid) return;
    print("🛡️ Screen protection disabled (package removed)");
  }

  @override
  void initState() {
    super.initState();

    // 🌀 ANIMATION SETUP (safe to do in initState)
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _fadeAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(_animationController);

    // 🚀 Defer platform-specific initialization to after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPlatformState();
    });

    // ⏰ TIMEOUT: Hide loading after 15 seconds no matter what
    Future.delayed(const Duration(seconds: 15), () {
      if (mounted && _isLoading) {
        print("⚠️ Loading timeout - forcing hide");
        setState(() {
          _isLoading = false;
          if (_loadError == null) {
            _loadError = "Загрузка занимает слишком долго. Проверьте интернет.";
          }
        });
      }
    });
  }

  Future<void> _initPlatformState() async {
    // 🖥️ FULLSCREEN MODE (Immersive) - wrapped in try-catch
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ));
    } catch (e) {
      print("⚠️ SystemChrome error: $e");
    }

    // 💸 IAP LISTENER - wrapped in try-catch
    await _initIAP();
  }

  Future<void> _initIAP() async {
    try {
      // Lazy initialization of IAP
      _inAppPurchase = InAppPurchase.instance;

      final bool available = await _inAppPurchase!.isAvailable();
      if (!available) {
        print("⚠️ IAP not available on this device");
        return;
      }

      final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase!.purchaseStream;
      _subscription = purchaseUpdated.listen((purchaseDetailsList) {
        _listenToPurchaseUpdated(purchaseDetailsList);
      }, onDone: () {
        _subscription?.cancel();
      }, onError: (error) {
        print("💰 IAP STREAM ERROR: $error");
      });
      print("✅ IAP initialized successfully");
    } catch (e, stackTrace) {
      print("⚠️ IAP initialization error: $e");
      print("Stack trace: $stackTrace");
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // 👂 ОСНОВНАЯ ЛОГИКА ОБРАБОТКИ ПОКУПКИ
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⏳ Оплата обрабатывается...")),
        );
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Ошибка оплаты: ${purchaseDetails.error?.message}")),
          );
           // 3. Обработка Ошибок (вызов JS)
          _webViewController?.evaluateJavascript(
              source: "window.onAppPaymentFailed('${purchaseDetails.error?.message ?? "Unknown error"}');"
          );
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          
          // 1. Завершаем транзакцию (ОБЯЗАТЕЛЬНО для Apple)
          if (purchaseDetails.pendingCompletePurchase) {
             await _inAppPurchase?.completePurchase(purchaseDetails);
          }
          
          // 2. Уведомляем Веб Сайт (вызов JS)
          _webViewController?.evaluateJavascript(
              source: "window.onAppPaymentSuccess('${purchaseDetails.productID}');"
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Оплата прошла успешно!"), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  // 🚀 ЗАПУСК ПОКУПКИ (Вызывается из React)
  Future<void> _buyProduct(String productId) async {
    if (_inAppPurchase == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Магазин не инициализирован")),
      );
      return;
    }

    final bool available = await _inAppPurchase!.isAvailable();
    if (!available) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Магазин недоступен")),
      );
      return;
    }

    // Defining supported product IDs for reference/validation
    const Set<String> _kIds = <String>{'x5_pro_monthly', 'x5_pro_yearly', 'x5_credits_1000'};

    // Explicitly add the requested product to the query set
    final Set<String> ids = {productId};
    final ProductDetailsResponse response = await _inAppPurchase!.queryProductDetails(ids);

    if (response.notFoundIDs.isNotEmpty) {
       print("❌ Product not found: ${response.notFoundIDs}");
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Продукт не найден: $productId")),
      );
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);

    // Differentiate between Consumable (Credits) and Non-Consumable/Subscription (Pro Plans)
    if (productId == 'x5_credits_1000') {
      // Consumable: Can be purchased multiple times (e.g., Credits)
      // autoConsume: true is default for buyConsumable on Android, but handled manually via completePurchase on iOS usually.
      // flutter_inapp_purchase documentation suggests using buyConsumable for consumables.
      _inAppPurchase!.buyConsumable(purchaseParam: purchaseParam);
    } else {
      // Non-Consumable or Subscription: One-time unlock or auto-renewing (e.g., Pro Plan)
      _inAppPurchase!.buyNonConsumable(purchaseParam: purchaseParam);
    }
  }

  // ♻️ ВОССТАНОВЛЕНИЕ ПОКУПОК
  Future<void> _restorePurchases() async {
    if (_inAppPurchase == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Магазин не инициализирован")),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Восстановление покупок...")),
    );
    try {
      await _inAppPurchase!.restorePurchases();
      // Note: restoration results come through the same _subscription stream
      // We rely on the stream listener to handle the 'restored' status.
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Ошибка восстановления: $e")),
      );
    }
  }

  // 🍎 APPLE SIGN IN
  Future<void> _signInWithApple() async {
    try {
      // Generate nonce for security
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // Check if identity token exists
      if (appleCredential.identityToken == null) {
        throw Exception('Apple Sign In returned no identity token');
      }

      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(oauthCredential);

      // Send success back to React
      final user = userCredential.user;
      final displayName = appleCredential.givenName != null
          ? '${appleCredential.givenName} ${appleCredential.familyName ?? ""}'.trim()
          : user?.displayName ?? 'Apple User';

      _webViewController?.evaluateJavascript(source: '''
        window.onAppAuthSuccess && window.onAppAuthSuccess({
          uid: "${user?.uid ?? ''}",
          email: "${user?.email ?? ''}",
          displayName: "$displayName",
          photoURL: "${user?.photoURL ?? ''}"
        });
      ''');
    } on SignInWithAppleAuthorizationException catch (e) {
      // Handle specific Apple Sign In errors (user cancelled, etc.)
      print("❌ Apple Sign In Authorization Error: ${e.code} - ${e.message}");
      final errorMsg = e.code == AuthorizationErrorCode.canceled
          ? 'User cancelled'
          : e.message;
      _webViewController?.evaluateJavascript(source: '''
        window.onAppAuthFailed && window.onAppAuthFailed("$errorMsg");
      ''');
    } catch (e) {
      print("❌ Apple Sign In Error: $e");
      _webViewController?.evaluateJavascript(source: '''
        window.onAppAuthFailed && window.onAppAuthFailed("$e");
      ''');
    }
  }

  // 🔵 GOOGLE SIGN IN
  Future<void> _signInWithGoogle() async {
    try {
      // iOS requires explicit clientId from GoogleService-Info.plist
      final googleSignIn = Platform.isIOS
          ? GoogleSignIn(clientId: '931639129066-drd4qhjo5pgki47itjup0dibft0a7i3f.apps.googleusercontent.com')
          : GoogleSignIn();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        // User cancelled
        _webViewController?.evaluateJavascript(source: '''
          window.onAppAuthFailed && window.onAppAuthFailed("User cancelled");
        ''');
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      // Send success back to React
      _webViewController?.evaluateJavascript(source: '''
        window.onAppAuthSuccess && window.onAppAuthSuccess({
          uid: "${user?.uid ?? ''}",
          email: "${user?.email ?? ''}",
          displayName: "${user?.displayName ?? ''}",
          photoURL: "${user?.photoURL ?? ''}"
        });
      ''');
    } catch (e) {
      print("❌ Google Sign In Error: $e");
      _webViewController?.evaluateJavascript(source: '''
        window.onAppAuthFailed && window.onAppAuthFailed("$e");
      ''');
    }
  }

  // 🔐 Helper: Generate random nonce for Apple Sign In
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  // 🔐 Helper: SHA256 hash for Apple Sign In nonce
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false, // Prevent resize when keyboard opens
      body: Stack(
        children: [
          // 🌐 LAYER 1: WEBVIEW
          InAppWebView(
            initialSettings: InAppWebViewSettings(
              applicationNameForUserAgent: Platform.isIOS ? "X5_IOS_CLIENT" : "X5_ANDROID_CLIENT",
              javaScriptEnabled: true,
              transparentBackground: true,
              useHybridComposition: true, // For better Android performance
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              // 🚫 DISABLE CACHE - Always load fresh content
              cacheEnabled: false,
              clearCache: true,
              cacheMode: CacheMode.LOAD_NO_CACHE,
            ),
            initialUrlRequest: URLRequest(
              url: WebUri("https://x5marketing.com"), 
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
              
              // 💰 PAY BRIDGE
              controller.addJavaScriptHandler(
                handlerName: 'payBridge',
                callback: (args) {
                  if (args.isNotEmpty) _buyProduct(args[0].toString());
                },
              );
              
              // ♻️ RESTORE BRIDGE
              controller.addJavaScriptHandler(
                handlerName: 'restoreBridge',
                callback: (args) {
                   _restorePurchases();
                },
              );
              
              // 🔐 AUTH BRIDGE
              controller.addJavaScriptHandler(
                handlerName: 'authBridge',
                callback: (args) {
                  if (args.isEmpty) return;
                  final provider = args[0].toString();

                  // Run auth in separate async context to avoid blocking WebView
                  Future.microtask(() async {
                    try {
                      if (provider == 'apple') {
                        await _signInWithApple();
                      } else if (provider == 'google') {
                        await _signInWithGoogle();
                      }
                    } catch (e) {
                      print("❌ Auth bridge error: $e");
                      _webViewController?.evaluateJavascript(source: '''
                        window.onAppAuthFailed && window.onAppAuthFailed("$e");
                      ''');
                    }
                  });
                },
              );
              
              // 🔔 PUSH BRIDGE (placeholder)
              controller.addJavaScriptHandler(
                handlerName: 'pushBridge',
                callback: (args) {},
              );
              
              // 🛡️ SCREEN PROTECTION BRIDGE
              controller.addJavaScriptHandler(
                handlerName: 'screenBridge',
                callback: (args) async {
                  if (args.isEmpty) return;
                  final action = args[0].toString();
                  
                  if (action == 'protect') {
                    await _enableScreenProtection();
                  } else if (action == 'unprotect') {
                    await _disableScreenProtection();
                  }
                },
              );
            },
            // 🎤 Handle microphone/camera permission requests from web
            onPermissionRequest: (controller, request) async {
              print("🎤 Permission request: ${request.resources}");
              return PermissionResponse(
                resources: request.resources,
                action: PermissionResponseAction.GRANT,
              );
            },
            onLoadStop: (controller, url) async {
              print("✅ Page loaded: $url");
              // Wait a bit to ensure smooth transition
              await Future.delayed(const Duration(seconds: 1));
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _loadError = null;
                });
              }
            },
            onReceivedError: (controller, request, error) {
              print("❌ Received error: ${error.type} - ${error.description}");
              if (mounted && error.type != WebResourceErrorType.CANCELLED) {
                setState(() {
                  _isLoading = false;
                  _loadError = "Ошибка сети: ${error.description}";
                });
              }
            },
            onProgressChanged: (controller, progress) {
              print("📊 Loading: $progress%");
            },
          ),

          // 🌀 LAYER 2: LOADING OVERLAY
          if (_isLoading)
            Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: const Text(
                        "X5",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 60,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          fontFamily: 'Arial',
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white10,
                        color: Colors.white,
                        minHeight: 2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ❌ LAYER 3: ERROR OVERLAY
          if (_loadError != null && !_isLoading)
            Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.wifi_off, color: Colors.white54, size: 64),
                    const SizedBox(height: 20),
                    Text(
                      _loadError!,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _loadError = null;
                        });
                        _webViewController?.reload();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      ),
                      child: const Text("Повторить"),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

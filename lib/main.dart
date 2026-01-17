import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

void main() {
  runApp(const MaterialApp(home: X5BridgeApp()));
}

class X5BridgeApp extends StatefulWidget {
  const X5BridgeApp({super.key});

  @override
  State<X5BridgeApp> createState() => _X5BridgeAppState();
}

class _X5BridgeAppState extends State<X5BridgeApp> with SingleTickerProviderStateMixin {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    // 🖥️ FULLSCREEN MODE (Immersive)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // 🌀 ANIMATION SETUP
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _fadeAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(_animationController);

    // 💸 IAP LISTENER
    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      print("💰 IAP STREAM ERROR: $error");
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // ... (Keep existing IAP methods: _listenToPurchaseUpdated, _buyProduct) ...
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
             await _inAppPurchase.completePurchase(purchaseDetails);
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
    final bool available = await _inAppPurchase.isAvailable();
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
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(ids);

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
      _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    } else {
      // Non-Consumable or Subscription: One-time unlock or auto-renewing (e.g., Pro Plan)
      _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
    }
  }

  // ♻️ ВОССТАНОВЛЕНИЕ ПОКУПОК
  Future<void> _restorePurchases() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("⏳ Восстановление покупок...")),
    );
    try {
      await _inAppPurchase.restorePurchases();
      // Note: restoration results come through the same _subscription stream
      // We rely on the stream listener to handle the 'restored' status.
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Ошибка восстановления: $e")),
      );
    }
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
              applicationNameForUserAgent: "X5_APP_CLIENT",
              javaScriptEnabled: true,
              transparentBackground: true,
              useHybridComposition: true, // For better Android performance
              allowsInlineMediaPlayback: true,
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
              controller.addJavaScriptHandler(
                handlerName: 'payBridge',
                callback: (args) {
                  if (args.isNotEmpty) _buyProduct(args[0].toString());
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'restoreBridge',
                callback: (args) {
                   _restorePurchases();
                },
              );
              controller.addJavaScriptHandler(
                handlerName: 'pushBridge',
                callback: (args) {},
              );
            },
            onLoadStop: (controller, url) async {
              // Wait a bit to ensure smooth transition
              await Future.delayed(const Duration(seconds: 1));
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            onProgressChanged: (controller, progress) {
               // Optional: Update granular progress if needed
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
                          fontFamily: 'Arial', // Fallback, system font usually looks good
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
        ],
      ),
    );
  }
}

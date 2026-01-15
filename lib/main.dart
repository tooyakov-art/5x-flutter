import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
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

class _X5BridgeAppState extends State<X5BridgeApp> {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    // 💸 СЛУШАЕМ СТАТУС ОПЛАТЫ ОТ APPLE/GOOGLE
    final Stream<List<PurchaseDetails>> purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      // Обработка ошибок стрима
      print("💰 IAP STREAM ERROR: $error");
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  // 👂 ОСНОВНАЯ ЛОГИКА ОБРАБОТКИ ПОКУПКИ
  void _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
        // Показываем юзеру, что процесс идет
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⏳ Оплата обрабатывается...")),
        );
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          // Ошибка оплаты
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Ошибка оплаты: ${purchaseDetails.error?.message}")),
          );
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          
          // ✅ УСПЕХ!
          final bool valid = true; // Тут можно добавить проверку чека на сервере
          if (valid) {
            // Сообщаем React сайту, что оплата прошла!
            // bridgeSuccess - это функция, которую React должен слушать (или мы просто кидаем event)
            _webViewController?.evaluateJavascript(source: "window.postMessage({target: 'PAYMENT_SUCCESS', product: '${purchaseDetails.productID}'}, '*')");
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("✅ Оплата прошла успешно!"), backgroundColor: Colors.green),
            );
          }
        }

        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
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

    // Запрашиваем продукт у магазина
    const Set<String> _kIds = <String>{'premium_monthly', 'premium_yearly'}; // Дефолтные ID, если React пришлет фигню
    final Set<String> ids = {productId}; 
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(ids);

    if (response.notFoundIDs.isNotEmpty) {
       // Если айдишник не найден в Apple Connect / Google Console
       print("❌ Product not found: ${response.notFoundIDs}");
       ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Продукт не найден: $productId")),
      );
      return;
    }

    final ProductDetails productDetails = response.productDetails.first;
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: productDetails);
    
    // Запускаем нативный диалог оплаты
    _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: InAppWebView(
          initialSettings: InAppWebViewSettings(
            applicationNameForUserAgent: "X5_APP_CLIENT",
            javaScriptEnabled: true,
          ),
          initialUrlRequest: URLRequest(
            url: WebUri("https://x5marketing.com"), 
          ),
          onWebViewCreated: (controller) {
            _webViewController = controller;

            // 💎 PAY BRIDGE: React вызывает payBridge('product_id')
            controller.addJavaScriptHandler(
              handlerName: 'payBridge',
              callback: (args) {
                print("💎 PAY SIGNAL: $args");
                if (args.isNotEmpty) {
                  String productId = args[0].toString();
                  // Запускаем процесс оплаты
                  _buyProduct(productId);
                }
              },
            );

            // 🔔 PUSH BRIDGE
            controller.addJavaScriptHandler(
              handlerName: 'pushBridge',
              callback: (args) {
                print("🔔 PUSH SIGNAL: $args");
                // TODO: Сохранить токен или логику пушей
              },
            );
          },
        ),
      ),
    );
  }
}

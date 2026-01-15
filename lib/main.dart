import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  runApp(const MaterialApp(home: X5BridgeApp()));
}

class X5BridgeApp extends StatefulWidget {
  const X5BridgeApp({super.key});

  @override
  State<X5BridgeApp> createState() => _X5BridgeAppState();
}

class _X5BridgeAppState extends State<X5BridgeApp> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Стильный черный фон
      body: SafeArea(
        child: InAppWebView(
          initialSettings: InAppWebViewSettings(
            // ГЛАВНОЕ: Паспорт. React увидит эту строку и поймет, что он в приложении.
            applicationNameForUserAgent: "X5_APP_CLIENT",
          ),
          initialUrlRequest: URLRequest(
            // Вставь сюда свой сайт. Если тестируешь локально, пиши localhost, но лучше реальный.
            url: WebUri("https://x5marketing.com"), 
          ),
          onWebViewCreated: (controller) {
            // Слушаем команды от сайта
            controller.addJavaScriptHandler(
              handlerName: 'payBridge',
              callback: (args) {
                // Если сработает — ты увидишь это в консоли и на экране
                print("💎 СИГНАЛ ОТ REACT ПОЛУЧЕН: $args");
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("🚀 BRIDGE WORKED! Payload: ${args[0]}"),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

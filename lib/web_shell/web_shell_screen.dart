import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:webview_flutter/webview_flutter.dart';

// CHANGE THIS TO YOUR TARGET URL
const String kInitialUrl = 'https://www.perplexity.ai/';

/// Provider to keep track of current connectivity (online/offline). check net access
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final checker = InternetConnectionChecker();

  // Start with current status.
  bool isConnected = await checker.hasConnection;
  yield isConnected;

  // Listen for connectivity changes and validate via InternetConnectionChecker.
  await for (final result in connectivity.onConnectivityChanged) {
    if (result == ConnectivityResult.none) {
      yield false;
    } else {
      final hasInternet = await checker.hasConnection;
      yield hasInternet;
    }
  }
});

class WebShellScreen extends ConsumerStatefulWidget {
  const WebShellScreen({super.key});

  @override
  ConsumerState<WebShellScreen> createState() => _WebShellScreenState();
}

class _WebShellScreenState extends ConsumerState<WebShellScreen> {
  late final WebViewController _webViewController;
  bool _isLoading = true;
  bool _hadError = false;

  @override
  void initState() {
    super.initState();

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'NativeBridge',
        onMessageReceived: _onJsMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _hadError = false;
            });
          },
          onPageFinished: (url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (error) {
            setState(() {
              _isLoading = false;
              _hadError = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(kInitialUrl));
  }

  void _onJsMessage(JavaScriptMessage message) {
    // Example: website calls window.NativeBridge.postMessage('showSnack:Hello');
    final text = message.message;
    if (text.startsWith('showSnack:')) {
      final content = text.substring('showSnack:'.length);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(content)),
      );
    }
    // You can parse JSON here for more complex commands.
  }

  Future<bool> _handleWillPop() async {
    if (await _webViewController.canGoBack()) {
      _webViewController.goBack();
      return false; // don't pop app
    }
    return true; // allow app to close
  }

  void _reload() {
    setState(() {
      _isLoading = true;
      _hadError = false;
    });
    _webViewController.reload();
  }

  @override
  Widget build(BuildContext context) {
    final connectivityAsync = ref.watch(connectivityProvider);

    return WillPopScope(
      onWillPop: _handleWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Advanced Web Shell'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
            ),
          ],
        ),
        body: Column(
          children: [
            // Offline banner
            connectivityAsync.when(
              data: (isOnline) => AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: isOnline ? 0 : 32,
                width: double.infinity,
                color: Colors.red,
                alignment: Alignment.center,
                child: isOnline
                    ? const SizedBox.shrink()
                    : const Text(
                  'No internet connection',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            // Progress bar
            if (_isLoading)
              const LinearProgressIndicator(
                minHeight: 2,
              ),

            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _webViewController),

                  // Error overlay if the page failed to load
                  if (_hadError)
                    Container(
                      color: Colors.white,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          const Text(
                            'Failed to load page',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: _reload,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

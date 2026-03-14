import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../app_bar/app_bar.dart';
import 'knowledge_base_utils.dart';

class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  double _progress = 0;
  bool _loadError = false;
  Timer? _loadTimeout;

  @override
  void initState() {
    super.initState();
    _loadTimeout = Timer(const Duration(seconds: 20), () {
      if (mounted && _progress < 1 && !_loadError) {
        setState(() => _loadError = true);
      }
    });
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError) {
      return Scaffold(
        appBar: MyAppBar.build(context) as AppBar,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'Не удалось загрузить страницу в приложении',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: openKnowledgeBaseInBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Открыть в браузере'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: MyAppBar.build(context) as AppBar,
      body: Column(
        children: [
          if (_progress < 1)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey.shade200,
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(knowledgeBaseUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                useHybridComposition: true,
              ),
              onWebViewCreated: (_) {},
              onLoadStart: (controller, url) {
                if (mounted) setState(() => _progress = 0);
              },
              onLoadStop: (controller, url) {
                _loadTimeout?.cancel();
                if (mounted) setState(() => _progress = 1);
              },
              onProgressChanged: (controller, progress) {
                if (mounted) setState(() => _progress = progress / 100);
              },
              onReceivedError: (controller, request, error) {
                if (request.isForMainFrame == true && mounted) {
                  _loadTimeout?.cancel();
                  setState(() => _loadError = true);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

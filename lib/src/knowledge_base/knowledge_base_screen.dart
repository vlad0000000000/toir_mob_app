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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (_loadError) {
      return Scaffold(
        appBar: MyAppBar.build(context) as AppBar,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.cloud_off_rounded,
                      size: 48, color: cs.error),
                ),
                const SizedBox(height: 16),
                Text(
                  'Не удалось загрузить страницу',
                  textAlign: TextAlign.center,
                  style: tt.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Проверьте интернет-соединение или откройте справку в браузере.',
                  textAlign: TextAlign.center,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: openKnowledgeBaseInBrowser,
                  icon: const Icon(Icons.open_in_browser_rounded),
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
              minHeight: 2,
              backgroundColor: cs.surfaceContainerHigh,
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

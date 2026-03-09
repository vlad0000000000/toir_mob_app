import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../app_bar/app_bar.dart';

const _knowledgeBaseUrl = 'https://docs.toir.sampo-smart.ru/m';

Future<void> _openInBrowser() async {
  final uri = Uri.parse(_knowledgeBaseUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class KnowledgeBaseScreen extends StatefulWidget {
  const KnowledgeBaseScreen({super.key});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _webViewFailed = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => setState(() => _isLoading = true),
            onPageFinished: (_) => setState(() => _isLoading = false),
            onWebResourceError: (error) {
              if (error.isForMainFrame != false && mounted) {
                setState(() => _webViewFailed = true);
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(_knowledgeBaseUrl));
    } catch (_) {
      if (mounted) setState(() => _webViewFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_webViewFailed) {
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
                  onPressed: _openInBrowser,
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
      body: Stack(
        children: [
          if (_controller != null) WebViewWidget(controller: _controller!),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

import 'package:url_launcher/url_launcher.dart';

const knowledgeBaseUrl = 'https://docs.toir.sampo-smart.ru/m';

Future<void> openKnowledgeBaseInBrowser() async {
  final uri = Uri.parse(knowledgeBaseUrl);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

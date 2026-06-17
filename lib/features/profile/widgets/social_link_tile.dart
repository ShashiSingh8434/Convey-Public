import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SocialLinkTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? username;
  final String urlPrefix;

  const SocialLinkTile({
    super.key,
    required this.icon,
    required this.label,
    required this.username,
    required this.urlPrefix,
  });

  @override
  Widget build(BuildContext context) {
    if (username == null || username!.isEmpty) {
      return const SizedBox.shrink();
    }

    final url = '$urlPrefix$username';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white54),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                Text(
                  username!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Open Link',
            icon: const Icon(
              Icons.open_in_new,
              size: 20,
              color: Colors.white54,
            ),
            onPressed: () async {
              final uri = Uri.parse(url);

              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                debugPrint('Launch error: $e');
              }
            },
          ),
        ],
      ),
    );
  }
}

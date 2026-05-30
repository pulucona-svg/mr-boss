import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/theme_provider.dart';

class MoreOptionsScreen extends ConsumerWidget {
  const MoreOptionsScreen({super.key});

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF070716) : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF140C37), Color(0xFF070716)],
                )
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.blue.shade50, Colors.white],
                ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Center(
                child: Column(
                  children: [
                    const Text(
                      'Mirror Laikipia',
                      style: TextStyle(
                        color: Color(0xFF7B5CFF),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Learn, Discover and Grow.',
                      style: TextStyle(
                        color: subTextColor,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Section 1: MORE ABOUT MIRROR LAIKIPIA
              _buildSectionTitle('MORE ABOUT MIRROR LAIKIPIA', textColor),
              const SizedBox(height: 16),
              _buildGridMenu([
                _buildMenuItem('About Us', textColor),
                _buildMenuItem('Privacy Policy', textColor),
                _buildMenuItem('Contact Us', textColor),
                _buildMenuItem('Terms and Conditions', textColor),
                _buildMenuItem('Community Guidelines', textColor),
                _buildMenuItem('Copyright Policy', textColor),
                _buildMenuItem('Advertise With Us', textColor),
                _buildMenuItem('Become a Contributor', textColor),
                _buildMenuItem('Help & Support', textColor),
              ]),
              const SizedBox(height: 40),

              // Section 2: SOCIAL MEDIA
              _buildSectionTitle('SOCIAL MEDIA', textColor),
              const SizedBox(height: 16),
              _buildSocialGrid([
                _buildSocialItem(
                  FontAwesomeIcons.facebook,
                  'Facebook',
                  'https://www.facebook.com/profile.php?id=100087730341282',
                  textColor,
                ),
                _buildSocialItem(
                  FontAwesomeIcons.tiktok,
                  'TikTok',
                  'https://www.tiktok.com/@mirrorlaikipia',
                  textColor,
                ),
                _buildSocialItem(
                  FontAwesomeIcons.instagram,
                  'Instagram',
                  'https://www.instagram.com/asielejohn',
                  textColor,
                ),
                _buildSocialItem(
                  FontAwesomeIcons.youtube,
                  'YouTube',
                  'https://youtube.com/@mirrorlaikipia',
                  textColor,
                ),
                _buildSocialItem(
                  FontAwesomeIcons.whatsapp,
                  'WhatsApp Support',
                  'https://wa.me/254714072774',
                  textColor,
                ),
              ]),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: textColor,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 1,
          width: double.infinity,
          color: textColor.withOpacity(0.2),
        ),
      ],
    );
  }

  Widget _buildGridMenu(List<Widget> items) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 3.5,
      mainAxisSpacing: 8,
      crossAxisSpacing: 16,
      children: items,
    );
  }

  Widget _buildMenuItem(String label, Color textColor) {
    return GestureDetector(
      onTap: () {
        // Placeholder for future content
      },
      child: Container(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: TextStyle(
            color: textColor.withOpacity(0.8),
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildSocialGrid(List<Widget> items) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 3.5,
      mainAxisSpacing: 8,
      crossAxisSpacing: 16,
      children: items,
    );
  }

  Widget _buildSocialItem(FaIconData icon, String label, String url, Color textColor) {
    return GestureDetector(
      onTap: () => _launchURL(url),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FaIcon(icon, color: textColor.withOpacity(0.8), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: textColor.withOpacity(0.8),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

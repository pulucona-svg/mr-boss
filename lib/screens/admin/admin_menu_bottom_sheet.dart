import 'package:flutter/material.dart';
import '../../services/admin_service.dart';
import 'manual_ads_admin_screen.dart';
import 'materials_admin_menu_bottom_sheet.dart';
import 'admin_messages_screen.dart';
import 'admin_notifications_screen.dart';
import 'curriculum_admin_screen.dart';
import '../explore_screen.dart';

class AdminMenuBottomSheet extends StatelessWidget {
  final AdminCapabilities capabilities;

  const AdminMenuBottomSheet({
    super.key,
    required this.capabilities,
  });

  static IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'campaign_outlined':
      case 'campaign':
        return Icons.campaign_outlined;
      case 'explore_outlined':
      case 'newspaper_outlined':
      case 'newspaper':
      case 'article':
        return Icons.newspaper_outlined;
      case 'menu_book_outlined':
      case 'menu_book':
        return Icons.menu_book_outlined;
      case 'people_outline':
      case 'people':
      case 'group':
        return Icons.people_outline;
      case 'table_chart_outlined':
      case 'table_chart':
      case 'curriculum':
        return Icons.table_chart_outlined;
      case 'notifications_active_outlined':
      case 'notifications':
        return Icons.notifications_active_outlined;
      case 'chat_outlined':
      case 'chat':
      case 'forum':
        return Icons.chat_outlined;
      default:
        return Icons.admin_panel_settings_outlined;
    }
  }

  static String _getModuleEmoji(String id) {
    switch (id) {
      case 'manual_ads':
        return '📢';
      case 'news_articles':
        return '📰';
      case 'materials':
        return '📚';
      case 'users':
        return '👥';
      case 'curriculum':
        return '📑';
      case 'notifications':
        return '🔔';
      case 'admin_messages':
        return '💬';
      default:
        return '⚡';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0C1D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Grab Handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1),
                    ),
                    child: const Icon(Icons.shield_outlined, color: Colors.amber, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ADMIN CONSOLE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF00E676),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Backend Verified (${capabilities.role.toUpperCase()})',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white12, height: 1),

            // Dynamic Backend-Driven Capabilities List
            Flexible(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shrinkWrap: true,
                itemCount: capabilities.menu.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = capabilities.menu[index];
                  final iconData = _getIconData(item.icon);
                  final emoji = _getModuleEmoji(item.id);
                  final isEnabled = item.enabled;

                  return Container(
                    decoration: BoxDecoration(
                      color: isEnabled ? Colors.white.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.015),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isEnabled ? const Color(0xFF20C8FF).withValues(alpha: 0.2) : Colors.white10,
                        width: 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: isEnabled
                              ? const Color(0xFF20C8FF).withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          iconData,
                          color: isEnabled ? const Color(0xFF20C8FF) : Colors.white30,
                          size: 20,
                        ),
                      ),
                      title: Row(
                        children: [
                          Text('$emoji ', style: const TextStyle(fontSize: 14)),
                          Text(
                            item.title,
                            style: TextStyle(
                              color: isEnabled ? Colors.white : Colors.white38,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        item.subtitle,
                        style: TextStyle(
                          color: isEnabled ? Colors.white60 : Colors.white24,
                          fontSize: 12,
                        ),
                      ),
                      trailing: item.badge != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                              ),
                              child: Text(
                                item.badge!,
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : Icon(
                              isEnabled ? Icons.arrow_forward_ios_rounded : Icons.lock_outline_rounded,
                              size: 14,
                              color: isEnabled ? Colors.white38 : Colors.white24,
                            ),
                      onTap: isEnabled
                          ? () {
                              if (item.id == 'manual_ads') {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const ManualAdsAdminScreen(),
                                  ),
                                );
                              } else if (item.id == 'news_articles') {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const ExploreScreen(isAdminMode: true),
                                  ),
                                );
                              } else if (item.id == 'materials') {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (modalContext) => const MaterialsAdminMenuBottomSheet(),
                                );
                              } else if (item.id == 'curriculum') {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const CurriculumAdminScreen(),
                                  ),
                                );
                              } else if (item.id == 'admin_messages') {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const AdminMessagesScreen(),
                                  ),
                                );
                              } else if (item.id == 'notifications') {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => const AdminNotificationsScreen(),
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(Icons.info_outline, color: Color(0xFF20C8FF), size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            '${item.title}: Module coming in the next implementation phase.',
                                            style: const TextStyle(fontSize: 13, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: const Color(0xFF141232),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

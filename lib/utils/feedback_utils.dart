import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';
import '../screens/archive_trash_screen.dart';

enum FeedbackActionType {
  pin,
  unpin,
  archive,
  unarchive,
  moveToTrash,
  restore,
  permanentDelete,
}

class FeedbackUtils {
  static void showActionFeedback({
    required BuildContext context,
    required FeedbackActionType type,
    required int count,
    required bool isDownloads,
  }) {
    final messenger = ConnectivityService().messengerKey.currentState;
    if (messenger == null) return;

    String message = '';
    String? actionLabel;
    VoidCallback? onAction;

    final String itemLabel = count == 1 ? 'material' : 'materials';

    switch (type) {
      case FeedbackActionType.pin:
        message = '$count $itemLabel pinned';
        break;
      case FeedbackActionType.unpin:
        message = '$count $itemLabel unpinned';
        break;
      case FeedbackActionType.archive:
        message = '$count $itemLabel archived';
        actionLabel = 'VIEW';
        onAction = () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ArchiveTrashScreen(isDownloads: isDownloads, isTrash: false),
            ),
          );
        };
        break;
      case FeedbackActionType.unarchive:
        message = '$count $itemLabel unarchived';
        break;
      case FeedbackActionType.moveToTrash:
        message = '$count $itemLabel moved to Trash';
        actionLabel = 'VIEW';
        onAction = () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ArchiveTrashScreen(isDownloads: isDownloads, isTrash: true),
            ),
          );
        };
        break;
      case FeedbackActionType.restore:
        message = '$count $itemLabel restored';
        break;
      case FeedbackActionType.permanentDelete:
        message = '$count $itemLabel permanently deleted';
        break;
    }

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: const Color(0xFF20C8FF),
                onPressed: onAction,
              )
            : null,
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF181739),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}

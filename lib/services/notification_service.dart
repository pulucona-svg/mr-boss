import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/notification.dart';
import 'persistence_service.dart';
import 'interstitial_ad_service.dart';
import '../widgets/admin_notification_popup.dart';

class NotificationService extends ChangeNotifier {
  static NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  @visibleForTesting
  static void resetInstance([NotificationService? customInstance]) {
    _instance.disposeStreams();
    _instance = customInstance ?? NotificationService._internal();
  }

  NotificationService._internal() {
    init();
  }

  bool _isInitialized = false;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<QuerySnapshot>? _firestoreSubscription;

  final List<AppNotification> _firestoreNotifications = [];
  final List<AppNotification> _localNotifications = [];
  List<AppNotification> _notifications = [];

  final Set<String> _readIds = {};
  final Set<String> _seenIds = {};
  bool _isInitialSnapshot = true;

  /// Optional callback hook for unit testing or custom handling of new announcements
  void Function(AppNotification notification)? onNewNotificationArrival;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    try {
      _setupAuthListener();
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  void _setupAuthListener() {
    try {
      _authSubscription?.cancel();
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          _loadReadIds(user.uid);
          _startFirestoreListener();
        } else {
          _stopFirestoreListener();
          _loadReadIds(null);
        }
      });

      final current = FirebaseAuth.instance.currentUser;
      if (current != null) {
        _loadReadIds(current.uid);
        _startFirestoreListener();
      } else {
        _loadReadIds(null);
      }
    } catch (e) {
      debugPrint('NotificationService _setupAuthListener error: $e');
    }
  }

  void _startFirestoreListener() {
    try {
      _firestoreSubscription?.cancel();
      _isInitialSnapshot = true;
      _firestoreSubscription = FirebaseFirestore.instance
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots()
          .listen(
            (snapshot) => _handleFirestoreSnapshot(snapshot),
            onError: (e) {
              debugPrint('NotificationService: Firestore stream error: $e');
            },
          );
    } catch (e) {
      debugPrint('NotificationService _startFirestoreListener error: $e');
    }
  }

  void _stopFirestoreListener() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _firestoreNotifications.clear();
    _rebuildMergedList();
  }

  Future<void> _loadReadIds(String? userId) async {
    try {
      final key = userId != null ? 'read_notifications_$userId' : 'read_notifications_anonymous';
      final saved = PersistenceService().getStringList(key);
      _readIds.clear();
      if (saved != null) {
        _readIds.addAll(saved);
      }
      _rebuildMergedList();
    } catch (e) {
      debugPrint('NotificationService _loadReadIds error: $e');
    }
  }

  Future<void> _persistReadIds() async {
    try {
      String? userId;
      try {
        userId = FirebaseAuth.instance.currentUser?.uid;
      } catch (_) {}
      final key = userId != null ? 'read_notifications_$userId' : 'read_notifications_anonymous';
      await PersistenceService().setStringList(key, _readIds.toList());
    } catch (e) {
      debugPrint('NotificationService _persistReadIds error: $e');
    }
  }

  void _handleFirestoreSnapshot(QuerySnapshot snapshot) {
    final List<AppNotification> items = [];
    final List<AppNotification> newArrivals = [];

    for (final doc in snapshot.docs) {
      final isRead = _readIds.contains(doc.id);
      final notification = AppNotification.fromFirestore(doc, isRead: isRead);
      items.add(notification);

      if (!_isInitialSnapshot) {
        if (!_seenIds.contains(doc.id)) {
          _seenIds.add(doc.id);
          newArrivals.add(notification);
        }
      } else {
        _seenIds.add(doc.id);
      }
    }

    _firestoreNotifications.clear();
    _firestoreNotifications.addAll(items);
    _rebuildMergedList();

    if (_isInitialSnapshot) {
      _isInitialSnapshot = false;
    } else if (newArrivals.isNotEmpty) {
      for (final newNotif in newArrivals) {
        _triggerNewNotificationAlert(newNotif);
      }
    }
  }

  void _triggerNewNotificationAlert(AppNotification notification) {
    if (onNewNotificationArrival != null) {
      onNewNotificationArrival!(notification);
      return;
    }

    // Play alert sound & haptic chime
    playNotificationChime();

    // Show stylish in-app notification popup if navigation context is available
    final context = InterstitialAdService.navigatorKey.currentContext;
    if (context != null) {
      AdminNotificationPopup.show(context, notification);
    }
  }

  static Future<void> playNotificationChime() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('NotificationService sound/haptic error: $e');
    }
  }

  void _rebuildMergedList() {
    final Map<String, AppNotification> map = {};
    for (final n in _firestoreNotifications) {
      n.isRead = _readIds.contains(n.id);
      map[n.id] = n;
    }
    for (final n in _localNotifications) {
      n.isRead = _readIds.contains(n.id);
      if (!map.containsKey(n.id)) {
        map[n.id] = n;
      }
    }
    _notifications = map.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    notifyListeners();
  }

  void addNotification({
    required NotificationType type,
    required String senderName,
    required String resourceTitle,
    String? id,
  }) {
    final notifId = id ?? '${DateTime.now().microsecondsSinceEpoch}_${_localNotifications.length}';
    _seenIds.add(notifId);
    final notification = AppNotification(
      id: notifId,
      type: type,
      senderName: senderName,
      resourceTitle: resourceTitle,
      timestamp: DateTime.now(),
      isRead: false,
    );
    _localNotifications.insert(0, notification);
    _rebuildMergedList();
  }

  void addModerationNotification({
    required NotificationType type,
    required String resourceTitle,
    String? id,
    String? title,
    String? message,
    String? materialId,
    String? remark,
    List<String>? rejectionReasons,
  }) {
    final notifId = id ?? '${DateTime.now().microsecondsSinceEpoch}_${_localNotifications.length}';
    if (_localNotifications.any((n) => n.id == notifId) ||
        _firestoreNotifications.any((n) => n.id == notifId)) {
      return;
    }
    _seenIds.add(notifId);
    final notification = AppNotification(
      id: notifId,
      type: type,
      senderName: 'Admin',
      resourceTitle: resourceTitle,
      timestamp: DateTime.now(),
      isRead: _readIds.contains(notifId),
      title: title,
      message: message,
      materialId: materialId,
      remark: remark,
      rejectionReasons: rejectionReasons,
    );
    _localNotifications.insert(0, notification);
    _rebuildMergedList();
  }

  void markAsRead(String id) {
    if (!_readIds.contains(id)) {
      _readIds.add(id);
      _persistReadIds();
      final index = _notifications.indexWhere((n) => n.id == id);
      if (index != -1) {
        _notifications[index].isRead = true;
        notifyListeners();
      }
    }
  }

  void markAllAsRead() {
    for (final n in _notifications) {
      n.isRead = true;
      _readIds.add(n.id);
    }
    _persistReadIds();
    notifyListeners();
  }

  void clearNotifications() {
    _localNotifications.clear();
    _rebuildMergedList();
  }

  void disposeStreams() {
    _authSubscription?.cancel();
    _firestoreSubscription?.cancel();
  }

  @visibleForTesting
  void handleTestSnapshot(List<AppNotification> items) {
    final List<AppNotification> newArrivals = [];
    for (final n in items) {
      if (!_isInitialSnapshot) {
        if (!_seenIds.contains(n.id)) {
          _seenIds.add(n.id);
          newArrivals.add(n);
        }
      } else {
        _seenIds.add(n.id);
      }
    }
    _firestoreNotifications.clear();
    _firestoreNotifications.addAll(items);
    _rebuildMergedList();

    if (_isInitialSnapshot) {
      _isInitialSnapshot = false;
    } else if (newArrivals.isNotEmpty) {
      for (final newNotif in newArrivals) {
        _triggerNewNotificationAlert(newNotif);
      }
    }
  }

  @visibleForTesting
  void setInitialLoadComplete() {
    _isInitialSnapshot = false;
  }

  @visibleForTesting
  Set<String> get readIds => Set.unmodifiable(_readIds);

  @visibleForTesting
  Set<String> get seenIds => Set.unmodifiable(_seenIds);
}

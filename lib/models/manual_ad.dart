import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Representation of a manual / sponsored advertisement in Mirror Laikipia.
class ManualAd {
  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String contactUrl;
  final int colorValue;
  final bool isActive;
  final bool isAsset;
  final String type;
  final String placement; // 'interstitial' | 'carousel'
  final String? mediaFileId;
  final int views;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ManualAd({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.contactUrl,
    this.colorValue = 0xFF20C8FF,
    this.isActive = true,
    this.isAsset = false,
    this.type = 'image',
    String placement = 'interstitial',
    this.mediaFileId,
    this.views = 0,
    this.createdAt,
    this.updatedAt,
  }) : placement = (placement.toLowerCase().trim() == 'app_launch' ||
            placement.toLowerCase().trim() == 'app_launch_interstitial' ||
            placement.toLowerCase().trim() == 'applaunch' ||
            placement.toLowerCase().trim() == 'app launch' ||
            placement.toLowerCase().trim() == 'app launch ads')
        ? 'app_launch'
        : (placement.toLowerCase().trim() == 'carousel' ? 'carousel' : 'interstitial');

  Color get color => Color(colorValue);
  bool get isAppLaunch => placement == 'app_launch' || placement == 'app_launch_interstitial';

  ManualAd copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? imageUrl,
    String? contactUrl,
    int? colorValue,
    bool? isActive,
    bool? isAsset,
    String? type,
    String? placement,
    String? mediaFileId,
    int? views,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ManualAd(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      imageUrl: imageUrl ?? this.imageUrl,
      contactUrl: contactUrl ?? this.contactUrl,
      colorValue: colorValue ?? this.colorValue,
      isActive: isActive ?? this.isActive,
      isAsset: isAsset ?? this.isAsset,
      type: type ?? this.type,
      placement: placement ?? this.placement,
      mediaFileId: mediaFileId ?? this.mediaFileId,
      views: views ?? this.views,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'subtitle': subtitle,
      'url': imageUrl,
      'imageUrl': imageUrl,
      'contactUrl': contactUrl,
      'color': colorValue,
      'colorValue': colorValue,
      'isActive': isActive,
      'isAsset': isAsset,
      'type': type,
      'placement': isAppLaunch ? 'app_launch' : placement,
      'views': views,
      if (mediaFileId != null) 'mediaFileId': mediaFileId,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// JSON serialization for local persistent caching (SharedPreferences).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'imageUrl': imageUrl,
      'contactUrl': contactUrl,
      'colorValue': colorValue,
      'isActive': isActive,
      'isAsset': isAsset,
      'type': type,
      'placement': isAppLaunch ? 'app_launch' : placement,
      'views': views,
      if (mediaFileId != null) 'mediaFileId': mediaFileId,
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  /// Converts this ad into the parameter map expected by ManualInterstitialAdDialog.
  Map<String, dynamic> toDialogData() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'url': imageUrl,
      'contactUrl': contactUrl,
      'color': color,
      'type': type,
      'placement': isAppLaunch ? 'app_launch' : placement,
      'isAsset': isAsset,
      'isAppLaunch': isAppLaunch,
      'views': views,
    };
  }

  factory ManualAd.fromJson(Map<String, dynamic> json) {
    return ManualAd.fromMap(json['id'] as String? ?? '', json);
  }

  factory ManualAd.fromMap(String id, Map<String, dynamic> map) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return null;
    }

    int parseColor(dynamic val) {
      if (val is int) return val;
      if (val is Color) return val.toARGB32();
      if (val is String) {
        final clean = val.replaceAll('#', '').trim();
        if (clean.length == 6) {
          return int.tryParse('0xFF$clean') ?? 0xFF20C8FF;
        } else if (clean.length == 8) {
          return int.tryParse('0x$clean') ?? 0xFF20C8FF;
        }
      }
      return 0xFF20C8FF;
    }

    final rawPlacement = (map['placement'] as String?)?.toLowerCase().trim();
    final String placement;
    if (rawPlacement == 'carousel') {
      placement = 'carousel';
    } else if (rawPlacement == 'app_launch' ||
        rawPlacement == 'app_launch_interstitial' ||
        rawPlacement == 'applaunch' ||
        rawPlacement == 'app launch' ||
        rawPlacement == 'app launch ads') {
      placement = 'app_launch';
    } else {
      placement = 'interstitial';
    }

    return ManualAd(
      id: id,
      title: map['title'] as String? ?? 'Sponsored',
      subtitle: map['subtitle'] as String? ?? '',
      imageUrl: (map['url'] as String?) ?? (map['imageUrl'] as String?) ?? '',
      contactUrl: map['contactUrl'] as String? ?? '',
      colorValue: parseColor(map['color'] ?? map['colorValue']),
      isActive: map['isActive'] as bool? ?? map['active'] as bool? ?? true,
      isAsset: map['isAsset'] as bool? ?? (!((map['url'] as String? ?? map['imageUrl'] as String? ?? '').startsWith('http'))),
      type: map['type'] as String? ?? 'image',
      placement: placement,
      mediaFileId: (map['mediaFileId'] as String?) ?? (map['fileId'] as String?),
      views: (map['views'] as num?)?.toInt() ?? 0,
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
    );
  }

  /// Isolated emergency bootstrap fallback used ONLY if local cache is completely empty
  /// on first launch before any server synchronization has ever occurred.
  static ManualAd get emergencyBootstrapAd => ManualAd(
    id: 'emergency_bootstrap_cyber',
    title: 'Davy Cybers 💻',
    subtitle: 'Professional cyber services for all your document and technical needs.',
    imageUrl: 'assets/ad_cyber.jpeg',
    contactUrl: 'https://wa.me/254108462492',
    colorValue: 0xFF20C8FF,
    isActive: true,
    isAsset: true,
    views: 0,
    type: 'image',
    placement: 'interstitial',
  );
}

import 'package:uuid/uuid.dart';
import 'persistence_service.dart';
import 'package:flutter/foundation.dart';

class DeviceIdManager {
  static const String _deviceIdKey = 'mirror_persistent_device_id';

  /// Gets the persistent device ID from storage, or generates and saves one if it doesn't exist.
  static Future<String> getPersistentDeviceId() async {
    final persistence = PersistenceService();
    String? deviceId = persistence.getString(_deviceIdKey);

    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await persistence.setString(_deviceIdKey, deviceId);
      debugPrint('DeviceIdManager: Generated new persistent deviceId: $deviceId');
    } else {
      debugPrint('DeviceIdManager: Retrieved existing persistent deviceId: $deviceId');
    }

    return deviceId;
  }
}

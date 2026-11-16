import 'package:flutter/services.dart';

/// How much room is left on the phone, for the Home header. Answered by the
/// platform; nothing is sent anywhere.
class DeviceStorage {
  const DeviceStorage();

  static const _channel = MethodChannel('com.pictoiq.app/device');

  /// Free space in bytes, or null when the platform cannot say.
  Future<int?> freeBytes() async {
    try {
      return await _channel.invokeMethod<int>('freeBytes');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

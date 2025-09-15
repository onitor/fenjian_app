import 'package:flutter/services.dart';
import 'dart:io';

class DeviceIdentifier {
  static const MethodChannel _channel = MethodChannel('com.example.device_info');

  static Future<String> getDeviceId() async {
    try {
      if (!Platform.isAndroid) return 'UNSUPPORTED_PLATFORM';
      final String id = await _channel.invokeMethod('getAndroidId');
      return id.isNotEmpty ? id : 'UNKNOWN_ANDROID_ID';
    } catch (e) {
      print('获取设备 ANDROID_ID 失败: $e');
      return 'UNKNOWN_ANDROID_ID';
    }
  }
}

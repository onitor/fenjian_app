// lib/api.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'http_service.dart';

class ApiClient {
  final HttpService _http = HttpService();

  static Future<ApiClient> create() async => ApiClient();

  // 设备信息（按 mac / ANDROID_ID）
  Future<Map<String, dynamic>> getEquipmentByMac(String mac) async {
    final resp = await _http.get(
      '/tx_equipment_mgmt/get_equipment_inform_by_mac',
      queryParameters: {'mac_address': mac},
    );
    return _http.parseJson<Map<String, dynamic>>(resp);
  }

  // 获取小程序码（服务器返回 base64 字符串）
  Future<String> getWxacodeBase64({
    required String path,
    required int width,
    required String eqNumber,
  }) async {
    final resp = await _http.post(
      '/tx_base/tx_getwxacode',
      data: jsonEncode({'path': path, 'width': width, 'eqNumber': eqNumber}),
    );
    return _http.parseJson<String>(resp);
  }
}

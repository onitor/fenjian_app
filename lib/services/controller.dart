import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import '../dio/mqtt_service.dart';
import '../models/EquipmentInfo.dart';
import 'package:get_storage/get_storage.dart';
import 'package:dio/dio.dart';
import 'http_service.dart';

class EquipmentController extends GetxController {
  final Rxn<EquipmentInfo> equipmentInfo = Rxn<EquipmentInfo>();
  final box = GetStorage();
  final RxBool isBoundRx = false.obs;


  String? runtimeUserId;                          // 运行期兜底 userId
  String? _userRole;                              // '1','2','3','5'...
  late final MqttService mqtt;

  String? _toStrOrNull(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  bool get orderReady {
    final eqId = equipmentId?.toString().trim();
    final uid  = userId?.toString().trim();
    return (eqId != null && eqId.isNotEmpty) && (uid != null && uid.isNotEmpty);
  }
  void _recomputeBound() {
    final eq  = equipmentNumber?.trim();
    final uid = userId?.trim();
    final bound = (eq != null && eq.isNotEmpty) && (uid != null && uid.isNotEmpty);
    if (isBoundRx.value != bound) {
      isBoundRx.value = bound;           //  驱动 Obx
      debugPrint('[EC] isBound -> $bound (eq=$eq, uid=$uid)');
    }
    update();                             //  同时兼容 GetBuilder
  }
  String? get equipmentId => equipmentInfo.value?.eqId;
  String? get equipmentNumber {
    final s = equipmentInfo.value?.equipmentNumber;
    final fromInfo = (s != null && s.trim().isNotEmpty) ? s.trim() : null;
    final fromBox  = _toStrOrNull(box.read('equipmentNumber'));
    return fromInfo ?? fromBox;
  }

  String? get userId => _toStrOrNull(runtimeUserId);

  String get userRole {
    if (_userRole != null) return _userRole!;
    _userRole = equipmentInfo.value?.userRole ?? '1';
    return _userRole!;
  }

  set userRole(String role) {
    _userRole = role;
    debugPrint('[EC] userRole=$role');
    update(); //  通知 GetBuilder 重建
    _recomputeBound();
  }

  bool get isPicker => userRole == '5';             // 分拣员
  bool get isEmployeeMode => userRole == '3' || userRole == '5';

  void cacheUserIdFromMqtt(String? uid) {
    final v = _toStrOrNull(uid);
    if (v == null) return;
    runtimeUserId = v;
    box.write('equipmentUserId', v);
    debugPrint('[EC] cacheUserIdFromMqtt -> $runtimeUserId');
    update(); //  通知 GetBuilder 重建
    _recomputeBound();
  }

  @override
  void onInit() {
    super.onInit();
    box.remove('equipmentUserId');
    mqtt = Get.find<MqttService>();          // main 里 initialBinding 注入
    mqtt.setOnMessage(_onMqttPayload);       // 只拿 payload
  }

  Future<void> fetchEquipmentInfoByAndroidId(String androidId) async {
    if (_fetching) { await _inflightCompleter?.future; return; }
    _fetching = true;
    _inflightCompleter = Completer<void>();
    try {
      const maxRetry = 2;
      const delayMs = Duration(milliseconds: 500);
      String? lastErr;
      for (var i = 0; i <= maxRetry; i++) {
        final ok = await _doFetchOnce(androidId);
        if (ok) { lastErr = null; break; }
        lastErr = '设备信息为空或解析失败';
        if (i < maxRetry) await Future.delayed(delayMs);
      }
      if (lastErr != null) {
        // 可提示
      }
    } catch (e) {
      Get.snackbar('异常', '网络请求失败：$e');
    } finally {
      _fetching = false;
      _inflightCompleter?.complete();
      _inflightCompleter = null;
    }
  }

  bool _fetching = false;
  Completer<void>? _inflightCompleter;

  dynamic _tryParseJson(dynamic data) {
    if (data == null) return null;
    if (data is Map || data is List) return data;
    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return null;
      try { return jsonDecode(s); } catch (_) { return null; }
    }
    return null;
  }

  Future<bool> _doFetchOnce(String androidId) async {
    final resp = await HttpService().dio.get(
      '/tx_equipment_mgmt/get_equipment_inform_by_mac',
      queryParameters: {'mac_address': androidId},
      options: Options(responseType: ResponseType.plain, receiveDataWhenStatusError: true),
    );

    final raw = resp.data;
    final parsed = _tryParseJson(raw);
    if (resp.statusCode != 200 || parsed is! Map || parsed['code'] != 0) {
      // ...
      return false;
    }

    final data = parsed['data'];
    if (data is! Map<String, dynamic>) return false;

    final eqNo = _toStrOrNull(data['equipmentNumber']);
    final eqUserIdFromApi = _toStrOrNull(data['equipmentUserId']); // 仅记录，不参与绑定判定

    if (eqNo != null) box.write('equipmentNumber', eqNo);
    if (eqUserIdFromApi != null) box.write('equipmentUserId_fromApi', eqUserIdFromApi);

    // 仅用接口数据，不做兜底合并
    equipmentInfo.value = EquipmentInfo.fromJson(data);

    update();
    _recomputeBound(); // 此时通常为 false（直到 MQTT 来）

    final curEq = equipmentNumber;
    if (curEq != null && curEq.isNotEmpty) {
      try { await mqtt.connectAndSubscribeOnce(curEq); } catch (e) {
        debugPrint('[EC] MQTT connect/subscribe error: $e');
      }
    }

    // 不再因为有 runtimeUserId 而“视为成功”
    final stillEmpty = _toStrOrNull(data['equipmentUserId']) == null && _toStrOrNull(runtimeUserId) == null;
    if (stillEmpty) {
      debugPrint('[fetchEq] userId 为空，等待 MQTT 绑定');
      return false;
    }
    return true;
  }

  void _onMqttPayload(String payload) {
    Map<String, dynamic>? m;

    // 1) 先按标准 JSON 解析
    try {
      m = jsonDecode(payload);
    } catch (_) {
      m = null;
    }

    // 2) 失败则尝试“单引号 JSON”纠正
    if (m == null) {
      final fixed = _coerceSingleQuotedJson(payload);
      if (fixed != null) {
        try {
          m = jsonDecode(fixed);
        } catch (_) {
          m = null;
        }
      }
    }

    if (m == null) {
      debugPrint('[EC] MQTT payload parse failed, raw="$payload"');
      return;
    }

    final eqNo = _toStrOrNull(m['equipmentNumber'] ?? m['eqNumber']);
    final uid  = _toStrOrNull(m['userId']?.toString() ?? m['uid']?.toString());
    final role = _toStrOrNull(m['userRole'] ?? m['role'] ?? m['roleCode']);

    final curEq = equipmentNumber;

    // 如果本机还没有设备号而 MQTT 给了，就落地一次
    if ((curEq == null || curEq.isEmpty) && eqNo != null) {
      box.write('equipmentNumber', eqNo);
      debugPrint('[EC] Adopted equipmentNumber from MQTT: $eqNo');
    } else if (eqNo != null && curEq != null && eqNo != curEq) {
      debugPrint('[EC] MQTT ignored: eq mismatch msg=$eqNo local=$curEq');
      return;
    }

    if (uid != null) {
      cacheUserIdFromMqtt(uid);   // 内部会 update() + _recomputeBound()
    }
    if (role != null) {
      userRole = role;            // 内部会 update() + _recomputeBound()
    }

    // 双保险
    _recomputeBound();
  }

  /// 把常见的“单引号 JSON”粗暴转成可被 jsonDecode 接受的字符串。
  /// - 仅在字符串形如 { ... } 或 [ ... ] 时尝试
  /// - 把未转义的 `'` 统一替换为 `"`（简单粗暴，但对中文内容/纯数字没副作用）
  /// - 也顺便去掉可能尾部多余的空白
  String? _coerceSingleQuotedJson(String raw) {
    if (raw.isEmpty) return null;
    final s = raw.trim();
    if (!(s.startsWith('{') || s.startsWith('['))) return null;

    // 先把 \r\n 之类整理一下
    var t = s.replaceAll('\r', '').replaceAll('\n', '');

    // 将未转义的单引号替换为双引号
    t = t.replaceAll(RegExp(r"(?<!\\)'"), '"');

    return t;
  }



  Future<void> unbindEquipmentUser() async {
    final number = box.read('equipmentNumber');
    try {
      await HttpService().post(
        '/tx_equipment_mgmt/unbind_equipment_user',
        data: {'equipmentNumber': number},
      );
    } finally {
      box.remove('equipmentUserId');
      runtimeUserId = null;
    }
  }
}


class QrCodeController extends GetxController {
  /// 请求二维码图片，增加设备编号参数
  Future<Uint8List?> fetchQrCodeImage(String equipmentNumber) async {
    try {
      final Map<String, dynamic> params = {
        'path': 'pages/login/Login',
        'width': 280,
        'eqNumber': equipmentNumber,
      };

      print(" 准备发送请求，参数如下：");
      params.forEach((key, value) => print(" - $key: $value (${value.runtimeType})"));

      final response = await HttpService().dio.post(
        '/tx_base/tx_getwxacode',
        data: params,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      // print(" 接口状态码: ${response.statusCode}");

      final data = response.data is String
          ? json.decode(response.data)
          : response.data;

      if (data['data'] == null || data['data']['qrCode'] == null) {
        print(" 响应中 qrCode 字段缺失");
        return null;
      }

      final qrBase64 = data['data']['qrCode'];
      print(" 接收到 base64 字符串长度: ${qrBase64.length}");

      // 尝试 Base64 解码
      final bytes = base64Decode(qrBase64);

      // 判断是否是 JSON 错误信息
      try {
        final errMsg = json.decode(utf8.decode(bytes));
        print(" 实际是后端错误信息: $errMsg");
        return null;
      } catch (_) {
        print(" Base64 解码通过，非 JSON，可能是图片");
      }

      return bytes;
    } catch (e) {
      print(" 请求异常: $e");
      return null;
    }
  }

}

// lib/services/scale/scale_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 设备信息（来自原生 list）
class ScaleUsbDevice {
  final int vendorId;
  final int productId;
  final String deviceName; // /dev/bus/usb/001/004 等

  ScaleUsbDevice({
    required this.vendorId,
    required this.productId,
    required this.deviceName,
  });

  factory ScaleUsbDevice.fromMap(Map<dynamic, dynamic> m) => ScaleUsbDevice(
    vendorId: (m['vendorId'] as num).toInt(),
    productId: (m['productId'] as num).toInt(),
    deviceName: (m['deviceName'] ?? '').toString(),
  );

  @override
  String toString() =>
      'USB(vendorId=0x${vendorId.toRadixString(16)}, productId=0x${productId.toRadixString(16)}, name=$deviceName)';
}

/// 统一接口（无 Mock）
abstract class ScaleService {
  /// 启动串口读取。三选一传参：
  /// - 指定 [deviceName] 精确匹配；或
  /// - 指定 [vid] + [pid]；若都不传，由原生自行选择（不推荐）。
  Future<void> start({
    int baud = 9600,
    int? vid,
    int? pid,
    String? deviceName,
    double? factor1, // 秤1系数
    double? factor2, // 秤2系数
  });

  Future<void> stop();

  /// 列出原生可见的 USB 设备（仅 Android 有效）
  Future<List<ScaleUsbDevice>> listDevices();

  /// 监听某个秤的实时重量（kg），按原生上报的 `id` 区分（缺省为 1）
  Stream<double> watchCurrentWeight(int id);

  /// 获取/操作累计值（纯前端累计，不影响原生）
  double getAccumulatedWeight(int id);
  void accumulate(int id, double weight);
  void clear(int id);

  /// 去皮（支持单秤/全部）
  /// - [id] 传 1/2 则只去对应秤；不传或传 null 表示两秤一起去皮
  Future<void> tare({int? id}); // 🆕 修改签名：支持 id

  /// 如需透传当前重量给原生/上报服务器，可在此实现
  Future<void> sendWeight(int id, double weight);
}

/// =======================================================
/// ANDROID 实现（无模拟）
/// =======================================================
class AndroidScaleService implements ScaleService {
  static const MethodChannel _m =
  MethodChannel('com.example.fenjian_app.scale/methods');
  static const EventChannel _e =
  EventChannel('com.example.fenjian_app.scale/weight');

  final Map<int, StreamController<double>> _streams = {};
  final Map<int, double> _acc = {}; // 前端累计
  StreamSubscription? _sub;
  bool _started = false;

  /// 监听原生推送，事件形如：{ "id": 1, "weight": 12.34 }
  void _ensureEventSubscribed() {
    if (_sub != null) return;
    _sub = _e.receiveBroadcastStream().listen((event) {
      if (event is Map) {
        final id = (event['id'] as num?)?.toInt() ?? 1;
        final w = (event['weight'] as num?)?.toDouble();
        if (w != null) {
          _streams[id]?.add(w);
        }
      }
    }, onError: (_) {
      // 不打断 UI；需要可在此上报日志
    });
  }

  @override
  Future<void> start({
    int baud = 9600,
    int? vid,
    int? pid,
    String? deviceName,
    double? factor1,
    double? factor2,
  }) async {
    if (_started) return;
    _ensureEventSubscribed();

    final args = <String, dynamic>{"baud": baud};
    if (deviceName != null && deviceName.isNotEmpty) {
      args["deviceName"] = deviceName;
    } else if (vid != null && pid != null) {
      args["vid"] = vid;
      args["pid"] = pid;
    }
    if (factor1 != null) args["factor1"] = factor1;
    if (factor2 != null) args["factor2"] = factor2;

    await _m.invokeMethod('start', args);
    _started = true;
  }

  @override
  Future<void> stop() async {
    if (!_started) return;
    try {
      await _m.invokeMethod('stop');
    } finally {
      _started = false;
      // 不主动关闭 _sub，方便后续重新 start；如需彻底释放可在此 cancel
    }
  }

  @override
  Future<List<ScaleUsbDevice>> listDevices() async {
    final res = await _m.invokeMethod<List<dynamic>>('list');
    if (res == null) return const [];
    return res.whereType<Map>().map((m) => ScaleUsbDevice.fromMap(m)).toList(growable: false);
  }

  @override
  Stream<double> watchCurrentWeight(int id) {
    final ctrl = _streams[id] ??= StreamController<double>.broadcast();
    return ctrl.stream;
  }

  @override
  double getAccumulatedWeight(int id) => _acc[id] ?? 0.0;

  @override
  void accumulate(int id, double weight) =>
      _acc[id] = (getAccumulatedWeight(id) + weight);

  @override
  void clear(int id) => _acc[id] = 0.0;

  @override
  Future<void> tare({int? id}) async { // 🆕 支持 id 透传
    // 兼容：如果 id 为 null，就不带该字段（或传 null），原生会按“全部去皮”处理
    final Map<String, dynamic>? args =
    (id == null) ? null : <String, dynamic>{"id": id};
    await _m.invokeMethod('tare', args);
  }

  @override
  Future<void> sendWeight(int id, double weight) async {
    // 需要透传到原生/服务端时在这里实现
    // await _m.invokeMethod('sendWeight', {"id": id, "weight": weight"});
  }

  /// 可选：完全释放（在页面销毁时调用）
  void dispose() {
    _sub?.cancel();
    for (final c in _streams.values) {
      c.close();
    }
    _streams.clear();
  }
}

/// 工厂：仅 Android 返回真服务，其它平台为关闭版（无模拟）
ScaleService createScaleService() {
  return AndroidScaleService();
}

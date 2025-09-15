// lib/services/scale/scale_service.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class ScaleService {
  /// 监听某个秤的实时重量流（kg）
  Stream<double> watchCurrentWeight(int id);

  /// 获取某个秤的累计重量（kg）
  double getAccumulatedWeight(int id);

  /// 将当前读数累计到某个秤
  void accumulate(int id, double weight);

  /// 去皮
  void tare(int id);

  /// 清零累计
  void clear(int id);

  /// 发送当前重量（如需上传/透传）
  Future<void> sendWeight(int id, double weight);
}

/// --------------------
/// 1) Mock 实现（开发/无硬件）
/// --------------------
class MockScaleService implements ScaleService {
  final _ctrl = StreamController<double>.broadcast();
  double _cur = 0.0;
  final Map<int, double> _acc = {1: 0.0};
  Timer? _t;

  MockScaleService() {
    // 简单模拟一个秤：在 0~5kg 内缓动
    final rnd = Random();
    _t = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _cur += (rnd.nextDouble() - 0.5) * 0.2;
      _cur = _cur.clamp(0.0, 5.0);
      _ctrl.add(double.parse(_cur.toStringAsFixed(2)));
    });
  }

  @override
  Stream<double> watchCurrentWeight(int id) => _ctrl.stream;

  @override
  double getAccumulatedWeight(int id) => _acc[id] ?? 0.0;

  @override
  void accumulate(int id, double weight) {
    _acc[id] = ( _acc[id] ?? 0.0 ) + weight;
  }

  @override
  void tare(int id) {
    // 仅模拟：将当前读数视作去皮后 0
    _cur = 0.0;
  }

  @override
  void clear(int id) {
    _acc[id] = 0.0;
  }

  @override
  Future<void> sendWeight(int id, double weight) async {
    // Mock：不做事
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  void dispose() {
    _t?.cancel();
    _ctrl.close();
  }
}

/// --------------------
/// 2) Android 实现（平台通道）
/// --------------------
class AndroidScaleService implements ScaleService {
  static const MethodChannel _m = MethodChannel('com.example.fenjian_app.scale/methods');
  static const EventChannel _e = EventChannel('com.example.fenjian_app.scale/weight');

  final _ctrl = StreamController<double>.broadcast();
  final Map<int, double> _acc = {1: 0.0};
  StreamSubscription? _sub;

  AndroidScaleService() {
    // 订阅原生事件
    _sub = _e.receiveBroadcastStream().listen((event) {
      if (event is Map && event['weight'] != null) {
        final w = (event['weight'] as num).toDouble();
        _ctrl.add(w);
      }
    }, onError: (e) {
      // 不中断 UI
      // debugPrint('Scale stream error: $e');
    });

    // 启动串口（参数按需改：端口、波特率）
    // 若原生侧已自启动，这里可以省略
    _m.invokeMethod('start', {"port": "/dev/ttyS3", "baud": 9600});
  }

  @override
  Stream<double> watchCurrentWeight(int id) => _ctrl.stream;

  @override
  double getAccumulatedWeight(int id) => _acc[id] ?? 0.0;

  @override
  void accumulate(int id, double weight) => _acc[id] = ( _acc[id] ?? 0.0 ) + weight;

  @override
  void tare(int id) { _m.invokeMethod('tare'); }

  @override
  void clear(int id) { _acc[id] = 0.0; }

  @override
  Future<void> sendWeight(int id, double weight) async {
    // 如需上传或透传到原生，在这里实现
  }

  void dispose() {
    _m.invokeMethod('stop');
    _sub?.cancel();
    _ctrl.close();
  }
}

/// --------------------
/// 3) 简单工厂：按平台选择实现
/// --------------------
ScaleService createScaleService() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return AndroidScaleService();
  }
  return MockScaleService();
}

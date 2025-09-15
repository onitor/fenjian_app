import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? _client;
  StreamSubscription? _updatesSub;

  // 当前消息回调（HomePage 或其他页面可随时替换）
  Function(String)? _onMessage;

  // 已订阅的主题集合（避免重复订阅）
  final Set<String> _subscribed = {};

  // 外部可关日志（mqtt_client 内部日志很多，默认关闭）
  final bool logEnabled;

  MqttService({this.logEnabled = false});

  /// —— 对外：判断是否已连接 ——
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  /// —— 对外：设置收到消息时的回调（可在不同页面替换） ——
  void setOnMessage(void Function(String msg)? handler) {
    _onMessage = handler;
  }

  /// —— 兼容你旧代码的入口名（与 connectAndSubscribeOnce 相同） ——
  Future<void> connectAndSubscribe(String topicOrDevice) =>
      connectAndSubscribeOnce(topicOrDevice);

  /// —— 新增：保证只连一次 & 只订一次（弱网友好） ——
  Future<void> connectAndSubscribeOnce(String topicOrDevice) async {
    // 1) 未连接则连接
    if (!isConnected) {
      await _connect();
    }
    // 2) 确保订阅到位（可重复调用，无副作用）
    final topics = _expandTopics(topicOrDevice);
    for (final t in topics) {
      await _ensureSubscribed(t);
    }
  }

  /// —— 主连接逻辑 ——
  Future<void> _connect() async {
    // 若已存在连接，先清理监听，避免重复 listen
    await _updatesSub?.cancel();
    _updatesSub = null;

    final clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';
    final c = MqttServerClient('175.178.82.123', clientId);
    _client = c;

    // 连接参数（弱网更稳）
    c.port = 1883;
    c.keepAlivePeriod = 30;                  // 心跳 30s
    c.connectTimeoutPeriod = 8000;          // 连接超时 8s
    c.logging(on: logEnabled);               // 默认关闭内部日志，避免 PING 刷屏
    c.useWebSocket = false;
    c.secure = false;
    c.setProtocolV311();

    // 自动重连 & 自动恢复订阅
    c.autoReconnect = true;
    c.resubscribeOnAutoReconnect = true;

    // 回调
    c.onConnected = () => print(' [MQTT] connected');
    c.onDisconnected = () =>
        print('🔌 [MQTT] disconnected: ${c.connectionStatus?.disconnectionOrigin}');
    c.onAutoReconnect = () => print(' [MQTT] auto reconnecting…');
    c.onAutoReconnected = () => print(' [MQTT] auto reconnected');
    c.pongCallback = () {
      if (logEnabled) print(' [MQTT] pong');
    };

    c.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs('MQTT1', 'odoo')
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    print(' [MQTT] connecting…');
    try {
      await c.connect();
    } catch (e) {
      print(' [MQTT] connect error: $e');
      print(' state=${c.connectionStatus?.state} rc=${c.connectionStatus?.returnCode}');
      try { c.disconnect(); } catch (_) {}
      rethrow;
    }

    // 统一的消息监听（只绑定一次）
    _updatesSub = c.updates?.listen((List<MqttReceivedMessage<MqttMessage>> events) {
      for (final evt in events) {
        final msg = evt.payload as MqttPublishMessage;
        final payload = utf8.decode(msg.payload.message);
        print(' [MQTT] << topic="${evt.topic}" payload=$payload');
        _onMessage?.call(payload);
      }
    });
  }

  /// —— 如果传设备号（无斜杠），扩展成多候选主题；如果像完整主题（有 /），原样返回 ——
  List<String> _expandTopics(String input) {
    final t = input.trim();
    if (t.contains('/')) return [t]; // 完整主题

    final e = t.startsWith('/') ? t.substring(1) : t;
    final set = <String>{
      e,
      '/$e',
      'device/$e',
      'device/$e/#',
      'tx/equipment/$e',
      'tx/equipment/$e/#',
    };
    return set.toList();
  }

  Future<void> _ensureSubscribed(String topic) async {
    if (_client == null) throw StateError('MQTT client not initialized');
    if (!isConnected) throw StateError('MQTT not connected');
    if (_subscribed.contains(topic)) return;

    try {
      _client!.subscribe(topic, MqttQos.atLeastOnce); // 提升 QoS，降低丢包
      _subscribed.add(topic);
      print(' [MQTT] subscribed: "$topic"');
    } catch (e) {
      print('⚠ [MQTT] subscribe failed "$topic": $e');
    }
  }

  void disconnect() {
    try { _updatesSub?.cancel(); } catch (_) {}
    _updatesSub = null;
    try { _client?.disconnect(); } catch (_) {}
    _client = null;
    _subscribed.clear();
    print('🛑 [MQTT] manual disconnect');
  }
}

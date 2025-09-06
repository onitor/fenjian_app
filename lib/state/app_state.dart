// lib/state/app_state.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_client.dart';
import '../services/scale/scale_service.dart';
import '../models/models.dart';

/// 由 main.dart 里的 ProviderScope override 注入
final apiProvider = Provider<ApiClient>((ref) => throw UnimplementedError());

/// 按平台选择 ScaleService：Android 用通道实现，其它平台/开发期用 Mock
final scaleProvider = Provider<ScaleService>((ref) => createScaleService());

/// 当前绑定分拣员
final boundWorkerProvider = FutureProvider<Worker?>((ref) async {
  final api = ref.read(apiProvider);
  return api.getBoundWorker();
});

/// 库位列表
final locationsProvider = FutureProvider<List<Location>>((ref) async {
  final api = ref.read(apiProvider);
  return api.getAllLocations();
});

/// 当前选中订单
class CurrentOrder extends StateNotifier<OrderBrief?> {
  CurrentOrder(): super(null);
  void set(OrderBrief? o) => state = o;
}
final currentOrderProvider =
StateNotifierProvider<CurrentOrder, OrderBrief?>((ref) => CurrentOrder());

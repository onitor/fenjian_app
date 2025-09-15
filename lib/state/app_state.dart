import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_client.dart';
import '../services/scale_service.dart';

final apiProvider = Provider<ApiClient>((ref) => throw UnimplementedError());
final scaleProvider = Provider<ScaleService>((ref) => createScaleService());

// 其它业务 Provider（绑定人员、库位、当前订单等）先注释/删除，等页面需要时再加。

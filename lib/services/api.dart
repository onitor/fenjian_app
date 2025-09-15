// lib/api/sorting_api.dart
import 'dart:io';
import 'package:dio/dio.dart';
import 'http_service.dart';

class SortingApi {
  final Dio _dio = HttpService().dio;

  // (1) 获取所有分拣单
  Future<List<Map<String, dynamic>>> getAllPickOrders({
    required String pickUserId,
    required String equipmentId,
    String? pickState, // null=全部
  }) async {
    final r = await _dio.get('/tx_tms_mgmt/get_all_tms_pick_order', queryParameters: {
      'pickUserId': pickUserId,
      'equipment_id': equipmentId,
      if (pickState != null) 'pickState': pickState,
    });
    return (r.data['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
  }

  // (2) 绑定分拣员
  Future<void> bindPicker({
    required String tmsOrderId,
    required String tmsOrderCode,
    required String pickUserId,
  }) async {
    await _dio.post('/tx_tms_mgmt/tms_pick_order_bind', data: {
      'tmsOrderId': tmsOrderId,
      'tmsOrderCode': tmsOrderCode,
      'pickUserId': pickUserId,
    });
  }

  // (3) 获取分拣单详细信息（注意：返回 data 是 List）
  Future<Map<String, dynamic>?> getTmsOrderInform({required String tmsOrderId}) async {
    final r = await _dio.get('/tx_tms_mgmt/get_tms_order_inform', queryParameters: {
      'tmsOrderId': tmsOrderId,
    });
    final list = (r.data['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return list.isNotEmpty ? list.first : null;
  }

  // —— 订单详情（带视频）——
  Future<Map<String, dynamic>?> getPurchaseOrderInfo({required String orderId}) async {
    final r = await _dio.get('/tx_purchase_order/get_order_infor', queryParameters: {
      'orderId': orderId,
    });
    final list = (r.data['data'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    return list.isNotEmpty ? list.first : null;
  }

  // (4) 修改订单行（分拣重量/类别）
  Future<void> updatePickOrderLine({
    required String orderLineId,
    required String productId,
    required double qty,
  }) async {
    await _dio.post('/tx_tms_mgmt/tx_update_pick_order_line', data: {
      'orderLineId': orderLineId,
      'productId': productId,
      'qty': qty,
    });
  }

  // (5) 新增订单行
  Future<void> addPickOrderLine({
    required String orderId,
    required String productId,
    required double sortWeight,
  }) async {
    await _dio.post('/tx_purchase_order/add_tx_pick_order_line', data: {
      'orderId': orderId,
      'productId': productId,
      'sortWeight': sortWeight,
    });
  }

  // (6) 生成异常订单（多文件）
  Future<void> createAbnormalOrder({
    required String orderId,
    required String remark,
    required List<File> files,
  }) async {
    final form = FormData();
    form.fields.add(MapEntry('orderId', orderId));
    form.fields.add(MapEntry('remark', remark));
    for (final f in files) {
      form.files.add(MapEntry('files', await MultipartFile.fromFile(f.path)));
    }
    await _dio.post('/tx_purchase_order/tx_update_abnormal_order', data: form);
  }

  // (7) 分拣完成
  Future<void> finishPickTmsOrder({
    required String tmsOrderId,
    required String tmsOrderCode,
  }) async {
    await _dio.post('/tx_tms_mgmt/finish_pick_tms_order', data: {
      'tmsOrderId': tmsOrderId,
      'tmsOrderCode': tmsOrderCode,
    });
  }

  // (9) 入库-修改明细
  Future<void> updatePickWarehousingOrderLine({
    required String pickLineId,
    required String productId,
    required double qty,
  }) async {
    await _dio.post('/tx_tms_mgmt/update_pick_warehousing_order_line', data: {
      'pickLineId': pickLineId,   // ⚠️= moveId
      'productId': productId,
      'qty': qty,
    });
  }

  // (10) 入库-新增明细
  Future<void> addPickWarehousingOrderLine({
    required String pickLineId,
    required String productId,
    required double qty,
  }) async {
    await _dio.post('/tx_tms_mgmt/add_pick_warehousing_order_line', data: {
      'pickLineId': pickLineId,   // ⚠️= moveId
      'productId': productId,
      'qty': qty,
    });
  }

  // (11) 入库-确认
  Future<void> confirmPickWarehousingOrder({required String pickId}) async {
    await _dio.post('/tx_tms_mgmt/confirm_pick_warehousing_order', data: {
      'pickId': pickId,
    });
  }

  // (12) 入库-完成
  Future<void> finishPickWarehousingOrder({required String pickId}) async {
    await _dio.post('/tx_tms_mgmt/finish_pick_warehousing_order', data: {
      'pickId': pickId,
    });
  }

  // (13) 订单称重完成
  Future<void> finishWeighingTmsOrder({
    required String tmsOrderId,
    required String tmsOrderCode,
  }) async {
    await _dio.post('/tx_tms_mgmt/finish_weighing_tms_order', data: {
      'tmsOrderId': tmsOrderId,
      'tmsOrderCode': tmsOrderCode,
    });
  }
}

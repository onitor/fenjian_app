// lib/services/sorting_locator.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import '../services/http_service.dart';

class ResolvedShipment {
  final String shipmentId;     // TMS 订单ID
  final String shipmentName;   // TMS 订单号
  final String equipmentNumber;
  final String destination;
  final String containerCode;  // ✅ 新增：柜号（用于 get_tms_order_container_code）
  final List<ResolvedPO> purchaseOrders;
  ResolvedShipment({
    required this.shipmentId,
    required this.shipmentName,
    required this.equipmentNumber,
    required this.destination,
    required this.containerCode, // ✅ 新增
    required this.purchaseOrders,
  });
}

class ResolvedPO {
  final String id;             // orderId
  final String number;         // orderNumber
  final String state;          // orderState
  final String createAt;       // orderCreateDate
  final double totalAmount;    // amountTotal
  final double recTotalPrice;  // recTotalPrice
  final double totalWeight;    // totalWeight
  ResolvedPO({
    required this.id,
    required this.number,
    required this.state,
    required this.createAt,
    required this.totalAmount,
    required this.recTotalPrice,
    required this.totalWeight,
  });
}

class SortingLocatorApi {
  final _http = HttpService().dio;

  Future<ResolvedShipment?> resolveShipmentByContainer({
    required String containerCode,
    int limit = 1,
  }) async {
    try {
      final resp = await _http.get(
        '/tx_tms_mgmt/get_tms_order_container_code',
        queryParameters: {'containerCode': containerCode, 'limit': limit},
        options: Options(responseType: ResponseType.plain),
      );
      final data = resp.data is String ? jsonDecode(resp.data) : resp.data;
      if (data?['code'] != 0) return null;

      final List list = (data['data'] as List?) ?? [];
      if (list.isEmpty) return null;

      // 取第一条运输单（limit 默认 1）
      final m = list.first as Map<String, dynamic>;
      final shipmentId   = (m['orderId'] ?? '').toString();
      final shipmentName = (m['orderName'] ?? '').toString();
      final equipmentNum = (m['equipmentNumber'] ?? '').toString();
      final dest         = (m['destination'] ?? '').toString();
      final contCode     = (m['containerCode'] ?? '').toString();

      final poList = <ResolvedPO>[];
      for (final po in (m['purchaseOrders'] as List? ?? [])) {
        final mm = po as Map<String, dynamic>;
        poList.add(
          ResolvedPO(
            id: (mm['orderId'] ?? '').toString(),
            number: (mm['orderNumber'] ?? '').toString(),
            state: (mm['orderState'] ?? '').toString(),
            createAt: (mm['orderCreateDate'] ?? '').toString(),
            totalAmount: (mm['amountTotal'] ?? 0).toDouble(),
            recTotalPrice: (mm['recTotalPrice'] ?? 0).toDouble(),
            totalWeight: (mm['totalWeight'] ?? 0).toDouble(),
          ),
        );
      }

      // 倒序：最新投放 → 最早投放（按 createAt）
      poList.sort((a, b) => b.createAt.compareTo(a.createAt));

      return ResolvedShipment(
        shipmentId: shipmentId,
        shipmentName: shipmentName,
        equipmentNumber: equipmentNum,
        destination: dest,
        containerCode: contCode,
        purchaseOrders: poList,
      );
    } catch (_) {
      return null;
    }
  }

  // (2) 绑定分拣员
  Future<void> bindPicker({
    required String tmsOrderId,
    required String tmsOrderCode,
    required String pickUserId,
  }) async {
    await _http.post(
      '/tx_tms_mgmt/tms_pick_order_bind',
      data: {
        'tmsOrderId': tmsOrderId,
        'tmsOrderCode': tmsOrderCode,
        'pickUserId': pickUserId,
      },
    );
  }

}

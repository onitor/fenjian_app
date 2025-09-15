// lib/models/sorting_models.dart
import 'dart:convert';

double _d(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

class TmsPickOrder {
  final String id;              // orderId
  final String name;            // orderName
  final String equipmentNumber; // TX00008
  final String pickState;       // pick / draft / weighing / audit / finish / cancel
  final double totalWeight;
  final double totalAmount;

  /// 概览里的用户订单（仅聚合）
  final List<PurchaseOrderLite> purchaseOrders;

  TmsPickOrder({
    required this.id,
    required this.name,
    required this.equipmentNumber,
    required this.pickState,
    required this.totalWeight,
    required this.totalAmount,
    required this.purchaseOrders,
  });

  factory TmsPickOrder.fromJson(Map<String, dynamic> j) => TmsPickOrder(
    id: j['orderId'].toString(),
    name: (j['orderName'] ?? '').toString(),
    equipmentNumber: (j['equipmentNumber'] ?? '').toString(),
    pickState: (j['pickState'] ?? '').toString(),
    totalWeight: _d(j['totalWeight']),
    totalAmount: _d(j['totalAmount']),
    purchaseOrders: ((j['purchaseOrders'] as List?) ?? const [])
        .map((e) => PurchaseOrderLite.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

class PurchaseOrderLite {
  final String id;          // orderId
  final String number;      // orderNumber
  final String state;       // orderState
  final String createAt;    // orderCreateDate
  final double totalWeight;
  final double totalAmount; // amountTotal or recTotalPrice(相等)

  PurchaseOrderLite({
    required this.id,
    required this.number,
    required this.state,
    required this.createAt,
    required this.totalWeight,
    required this.totalAmount,
  });

  factory PurchaseOrderLite.fromJson(Map<String, dynamic> j) => PurchaseOrderLite(
    id: j['orderId'].toString(),
    number: (j['orderNumber'] ?? '').toString(),
    state: (j['orderState'] ?? '').toString(),
    createAt: (j['orderCreateDate'] ?? '').toString(),
    totalWeight: _d(j['totalWeight']),
    totalAmount: _d(j['recTotalPrice'] ?? j['amountTotal']),
  );
}

/// 详情页：包含 txPickingIds（入库单）
class TmsPickOrderDetail extends TmsPickOrder {
  final String destination;
  final String destinationId;
  final double initTotalWeight; // 初始总重（柜）
  final double cabinetWeight;   // 柜重
  final String state;           // 运输单状态

  /// 入库单
  final List<PickTicket> pickTickets;

  TmsPickOrderDetail({
    required super.id,
    required super.name,
    required super.equipmentNumber,
    required super.pickState,
    required super.totalWeight,
    required super.totalAmount,
    required super.purchaseOrders,
    required this.destination,
    required this.destinationId,
    required this.initTotalWeight,
    required this.cabinetWeight,
    required this.state,
    required this.pickTickets,
  });

  factory TmsPickOrderDetail.fromJson(Map<String, dynamic> j) => TmsPickOrderDetail(
    id: j['orderId'].toString(),
    name: (j['orderName'] ?? '').toString(),
    equipmentNumber: (j['equipmentNumber'] ?? '').toString(),
    pickState: (j['pickState'] ?? '').toString(),
    totalWeight: _d(j['totalWeight']),
    totalAmount: _d(j['totalAmount']),
    purchaseOrders: ((j['purchaseOrders'] as List?) ?? const [])
        .map((e) => PurchaseOrderLite.fromJson(e as Map<String, dynamic>)).toList(),
    destination: (j['destination'] ?? '').toString(),
    destinationId: (j['destinationId'] ?? '').toString(),
    initTotalWeight: _d(j['initTotalWeight']),
    cabinetWeight: _d(j['cabinetWeight']),
    state: (j['state'] ?? '').toString(),
    pickTickets: ((j['txPickingIds'] as List?) ?? const [])
        .map((e) => PickTicket.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

/// 入库单（txPickingIds）
class PickTicket {
  final String pickId;
  final String pickNumber;
  final String pickState;
  final String pickCreateDate;
  final List<PickLine> lines;

  PickTicket({
    required this.pickId,
    required this.pickNumber,
    required this.pickState,
    required this.pickCreateDate,
    required this.lines,
  });

  factory PickTicket.fromJson(Map<String, dynamic> j) => PickTicket(
    pickId: j['pickId'].toString(),
    pickNumber: (j['pickNumber'] ?? '').toString(),
    pickState: (j['pickState'] ?? '').toString(),
    pickCreateDate: (j['pickCreateDate'] ?? '').toString(),
    lines: ((j['pickLine'] as List?) ?? const [])
        .map((e) => PickLine.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

/// 入库明细行 —— 注意：moveId 就是 (9)(10) 里的 pickLineId
class PickLine {
  final String pickLineId;  // ⚠️= moveId
  final String productId;
  final String productName;
  final double qty;         // productUomQty

  PickLine({
    required this.pickLineId,
    required this.productId,
    required this.productName,
    required this.qty,
  });

  factory PickLine.fromJson(Map<String, dynamic> j) => PickLine(
    pickLineId: j['moveId'].toString(),       // ⭐ 关键映射
    productId: j['productId'].toString(),
    productName: (j['productName'] ?? '').toString(),
    qty: _d(j['productUomQty']),
  );
}

/// 采购单详细（带视频 & 行）
class PurchaseOrderDetail {
  final String id;        // orderId
  final String number;    // orderNumber
  final String userName;  // orderUserName
  final double totalWeight;
  final double totalAmount;
  final List<VideoItem> videos;
  final List<PurchaseOrderLine> lines;

  PurchaseOrderDetail({
    required this.id,
    required this.number,
    required this.userName,
    required this.totalWeight,
    required this.totalAmount,
    required this.videos,
    required this.lines,
  });

  factory PurchaseOrderDetail.fromJson(Map<String, dynamic> j) => PurchaseOrderDetail(
    id: j['orderId'].toString(),
    number: (j['orderNumber'] ?? '').toString(),
    userName: (j['orderUserName'] ?? '').toString(),
    totalWeight: _d(j['totalWeight']),
    totalAmount: _d(j['recTotalPrice'] ?? j['amountTotal']),
    videos: _parseVideos(j['videoUrl']),
    lines: ((j['orderLine'] as List?) ?? const [])
        .map((e) => PurchaseOrderLine.fromJson(e as Map<String, dynamic>)).toList(),
  );

  static List<VideoItem> _parseVideos(dynamic v) {
    if (v == null) return const [];
    // videoUrl 是一个 JSON 字符串（数组），需要二次解析
    try {
      final arr = (v is String) ? (jsonDecode(v) as List) : (v as List);
      return arr.map((e) => VideoItem.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return const [];
    }
  }
}

class VideoItem {
  final String id;
  final String url;
  VideoItem({required this.id, required this.url});
  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
    id: (j['id'] ?? '').toString(),
    url: (j['url'] ?? '').toString(),
  );
}

class PurchaseOrderLine {
  final String id;          // id
  final String productId;
  final String productName;
  final double qty;         // 当前重量（qty/initWeight/sortWeight 由状态决定）
  final String uomName;
  final double unitPrice;
  final double totalPrice;

  PurchaseOrderLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.uomName,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory PurchaseOrderLine.fromJson(Map<String, dynamic> j) => PurchaseOrderLine(
    id: j['id'].toString(),
    productId: j['productId'].toString(),
    productName: (j['productName'] ?? '').toString(),
    qty: _d(j['sortWeight'] ?? j['qty'] ?? j['initWeight']),
    uomName: (j['uomName'] ?? 'kg').toString(),
    unitPrice: _d(j['recUnitPrice']),
    totalPrice: _d(j['recTotalPrice']),
  );
}

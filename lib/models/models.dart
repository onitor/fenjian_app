class Worker {
  final String id; // 员工/分拣员ID（扫码结果）
  final String name;
  const Worker({required this.id, required this.name});
}

class Location {
  final int locationId;
  final String locationName;
  const Location({required this.locationId, required this.locationName});
  factory Location.fromJson(Map<String, dynamic> j) => Location(
    locationId: j['locationId'] as int,
    locationName: j['locationName'] as String,
  );
}

class Product {
  final int productId;
  final String name;
  final String uom;
  const Product({required this.productId, required this.name, this.uom = 'kg'});
  factory Product.fromJson(Map<String, dynamic> j) => Product(
    productId: j['productId'] as int,
    name: (j['productName'] ?? j['name']) as String,
    uom: (j['uomName'] ?? 'kg') as String,
  );
}

class OrderBrief {
  final int id;
  final String orderNumber;
  final String userName;
  final double totalWeight;
  const OrderBrief({required this.id, required this.orderNumber, required this.userName, required this.totalWeight});
}

class OrderDetailLine {
  final int id;
  final Product product;
  final double qtyInit; // 初始重量
  final double sortWeight; // 分拣重量（当前称重）
  const OrderDetailLine({required this.id, required this.product, required this.qtyInit, required this.sortWeight});
}

class PickingBrief {
  final int id;
  final String number;
  final String state;
  const PickingBrief({required this.id, required this.number, required this.state});
}
/// 分拣单状态（你后端定义）
enum PickState {
  draft,      // 草稿
  pick,       // 分拣中
  weighing,   // 称重
  audit,      // 审核中
  finish,     // 完成
  cancel,     // 取消
  all,        // 特殊：全部（请求时不传 pickState）
}

String? pickStateParam(PickState s) {
  switch (s) {
    case PickState.all: return null;
    default: return s.name; // 与后端保持完全一致的字符串
  }
}

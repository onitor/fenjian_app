// lib/get/sorting_order_detail_controller.dart
import 'dart:io';
import 'package:get/get.dart';
import '../models/sorting_models.dart';
import 'api.dart';

class SortingOrderDetailController extends GetxController {
  final api = SortingApi();

  final RxBool loading = false.obs;
  final Rx<TmsPickOrderDetail?> detail = Rx<TmsPickOrderDetail?>(null);

  /// 运输单主键（来自路由）
  late final String orderId;

  Future<void> load(String id) async {
    orderId = id;
    loading.value = true;
    try {
      final j = await api.getTmsOrderInform(tmsOrderId: id);
      if (j == null) {
        detail.value = null;
      } else {
        detail.value = TmsPickOrderDetail.fromJson(j);
      }
    } finally {
      loading.value = false;
    }
  }

  // —— 分拣动作（订单行）——
  Future<void> updateLine({
    required String orderLineId,
    required String productId,
    required double qty,
  }) async {
    await api.updatePickOrderLine(orderLineId: orderLineId, productId: productId, qty: qty);
  }

  Future<void> addLine({
    required String orderId,     // 采购单ID（purchaseOrders[i].orderId）
    required String productId,
    required double sortWeight,
  }) async {
    await api.addPickOrderLine(orderId: orderId, productId: productId, sortWeight: sortWeight);
  }

  Future<void> markAbnormal({
    required String orderId,     // 采购单ID
    required String remark,
    required List<File> files,
  }) async {
    await api.createAbnormalOrder(orderId: orderId, remark: remark, files: files);
  }

  // —— 入库 —— 取 pickId / moveId
  String? get firstPickId => detail.value?.pickTickets.isNotEmpty == true ? detail.value!.pickTickets.first.pickId : null;

  Future<void> whUpdateLine({
    required String pickLineId,  // = moveId
    required String productId,
    required double qty,
  }) async {
    await api.updatePickWarehousingOrderLine(pickLineId: pickLineId, productId: productId, qty: qty);
  }

  Future<void> whAddLine({
    required String pickLineId,  // = moveId
    required String productId,
    required double qty,
  }) async {
    await api.addPickWarehousingOrderLine(pickLineId: pickLineId, productId: productId, qty: qty);
  }

  Future<void> whConfirm() async {
    final id = firstPickId;
    if (id == null) return;
    await api.confirmPickWarehousingOrder(pickId: id);
  }

  Future<void> whFinish() async {
    final id = firstPickId;
    if (id == null) return;
    await api.finishPickWarehousingOrder(pickId: id);
  }

  // —— 完成动作 —— 返回里运输单号字段是 orderName
  Future<void> finishWeighing() async {
    final d = detail.value;
    if (d == null) return;
    await api.finishWeighingTmsOrder(tmsOrderId: d.id, tmsOrderCode: d.name);
  }

  Future<void> finishPicking() async {
    final d = detail.value;
    if (d == null) return;
    await api.finishPickTmsOrder(tmsOrderId: d.id, tmsOrderCode: d.name);
  }

  // —— 查询单个采购单详情（带视频/行）——
  Future<PurchaseOrderDetail?> loadPurchaseOrderDetail(String purchaseOrderId) async {
    final j = await api.getPurchaseOrderInfo(orderId: purchaseOrderId);
    return j == null ? null : PurchaseOrderDetail.fromJson(j);
  }
}

// lib/services/sorting_work_controller.dart
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' as dio;
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../services/http_service.dart';

class SortingWorkController extends GetxController {
  // === 基础状态 ===
  final detail = Rxn<OrderDetailVM>();
  final isPageBusy = false.obs;

  /// 两台秤的忙碌状态（避免互相阻塞）
  final isBusyScale1 = false.obs;
  final isBusyScale2 = false.obs;

  /// 动态产品分类（来自后端 /tx_purchase_order/get_order_inform 的 orderLine）
  final categories = <CategoryVM>[].obs;
  final selected1 = Rx<CategoryVM?>(null);
  final selected2 = Rx<CategoryVM?>(null);

  /// 展示用累计（以服务端为准：从 orderLine.sortWeight 汇总；提交后也会局部更新）
  final totals = <int, double>{}.obs; // key: productId, val: sum sortWeight

  /// 异常状态本地切换（提交时以 submitAbnormal 为准）
  final abnormal = false.obs;

  final _dio = HttpService().dio;
  final _box = GetStorage();

  late int orderId;     // 采购单 ID
  late String orderNumber;
  late int equipmentId; // 设备 ID（称/柜）
  late String equipmentName;
  late String shipmentId; // tmsOrderId，用于 finish

  // ============== 生命周期/加载 ==============
  Future<void> load(String orderIdFromRoute) async {
    isPageBusy.value = true;
    try {
      // 取路由参数
      final args = Get.arguments ?? {};
      shipmentId = (args['shipmentId'] ?? '').toString();

      if (orderIdFromRoute.trim().isEmpty) {
        Get.snackbar('提示', '订单ID为空');
        Get.back();
        return;
      }
      orderId = int.tryParse(orderIdFromRoute) ?? 0;
      if (orderId <= 0) {
        Get.snackbar('提示', '无效的订单ID：$orderIdFromRoute');
        Get.back();
        return;
      }

      await _fetchOrderDetailAndBuildState(orderId);
    } catch (e) {
      Get.snackbar('错误', e.toString());
      // 出错也尽量不崩页
    } finally {
      isPageBusy.value = false;
    }
  }

  // 读取订单详情并构建：detail / categories / totals
  Future<void> _fetchOrderDetailAndBuildState(int oid) async {
    final resp = await _dio.get(
      '/tx_purchase_order/get_order_inform',
      queryParameters: {'orderId': oid},
    );

    final data = _normalizeRespData(resp); // ✅ 先规范化
    _ensureOk(data);                       // ✅ 再校验

    // 适配两种返回：{code,msg,data:[...]} 或直接 [...]
    final list = (data is Map) ? (data['data'] as List? ?? const []) : (data as List? ?? const []);
    if (list.isEmpty) throw Exception('订单不存在或无数据');

    // 一般后端返回 data 是数组，这里只取第一条
    final m = list.first as Map<String, dynamic>;

    // 解析视频（后端返回的是字符串化的 JSON 数组）
    final videoList = <OrderVideo>[];
    final rawVideo = (m['videoUrl'] ?? '').toString();
    if (rawVideo.isNotEmpty) {
      try {
        final arr = json.decode(rawVideo);
        if (arr is List) {
          for (final it in arr) {
            if (it is Map<String, dynamic>) {
              videoList.add(OrderVideo(
                id: it['id']?.toString() ?? '',
                url: it['url']?.toString() ?? '',
              ));
            }
          }
        }
      } catch (_) {
        // 忽略解析错误，不阻断
      }
    }

    final lines = (m['orderLine'] ?? []) as List;
    final orderLines = <OrderLineVM>[];
    final tmpCategories = <CategoryVM>[];
    final tmpTotals = <int, double>{};

    for (final it in lines) {
      final mm = it as Map<String, dynamic>;
      final pid = (mm['productId'] ?? 0) as int;
      final pname = (mm['productName'] ?? '').toString();
      final sortWeight = (mm['sortWeight'] ?? 0).toDouble();
      final initWeight = (mm['initWeight'] ?? 0).toDouble();

      orderLines.add(OrderLineVM(
        id: (mm['id'] ?? 0) as int,
        productId: pid,
        productName: pname,
        qty: (mm['qty'] ?? 0).toDouble(),
        initWeight: initWeight,
        sortWeight: sortWeight,
        uomId: (mm['uomId'] ?? 0) as int,
        uomName: (mm['uomName'] ?? '').toString(),
        recUnitPrice: (mm['recUnitPrice'] ?? 0).toDouble(),
        recTotalPrice: (mm['recTotalPrice'] ?? 0).toDouble(),
      ));

      // 用 orderLine 直接生成分类
      tmpCategories.add(CategoryVM(
        productId: pid,
        name: pname,
      ));

      // 汇总 totals（以 sortWeight 为准）
      tmpTotals[pid] = (tmpTotals[pid] ?? 0) + sortWeight;
    }

    // 去重分类（同 productId）
    final unique = <int, CategoryVM>{};
    for (final c in tmpCategories) {
      unique[c.productId] = c;
    }

    // 构建 detail
    final vm = OrderDetailVM(
      id: oid,
      orderNumber: (m['orderNumber'] ?? '').toString(),
      orderState: (m['orderState'] ?? '').toString(),
      equipmentId: (m['equipmentId'] ?? 0) as int,
      equipmentName: (m['equipmentName'] ?? '').toString(),
      totalWeight: (m['totalWeight'] ?? 0).toDouble(),
      recTotalPrice: (m['recTotalPrice'] ?? 0).toDouble(),
      amountTotal: (m['amountTotal'] ?? 0).toDouble(),
      videos: videoList,
      lines: orderLines,
    );

    detail.value = vm;
    orderNumber = vm.orderNumber;
    equipmentId = vm.equipmentId;
    equipmentName = vm.equipmentName;

    categories
      ..clear()
      ..addAll(unique.values);

    totals
      ..clear()
      ..addAll(tmpTotals);

    // 默认不预选；也可根据上次选择记忆做预选
    selected1.value = null;
    selected2.value = null;
  }

  // ============== 两台秤：加入（B 接口） ==============
  Future<void> addFromScale({
    required int scaleNo, // 1 或 2
    required double weight,
    bool refreshAfterSubmit = false, // 提交后是否调用 _refreshOrderSummary()
  }) async {
    final sel = (scaleNo == 1 ? selected1.value : selected2.value);
    if (sel == null) {
      Get.snackbar('提示', '请选择分类');
      return;
    }
    if (weight <= 0) {
      Get.snackbar('提示', '请放置物品并等待稳定重量');
      return;
    }

    final busy = (scaleNo == 1 ? isBusyScale1 : isBusyScale2);
    if (busy.value) return; // 防抖
    busy.value = true;

    try {
      final payload = {
        'orderId': orderId,
        'productId': sel.productId,
        'sortWeight': weight,
      };

      final resp = await _dio.post(
        '/tx_purchase_order/add_tx_pick_order_line',
        data: payload,
      );
      final data = _normalizeRespData(resp);
      _ensureOk(data);

      // 成功：本地 totals 先行更新（以后端为准）
      totals[sel.productId] = (totals[sel.productId] ?? 0) + weight;
      totals.refresh();

      Get.snackbar('已加入',
          '称$scaleNo → ${sel.name} + ${weight.toStringAsFixed(2)} kg');

      // 可选：重新拉一遍订单聚合（若后端返回有 totals，更建议直接覆盖）
      if (refreshAfterSubmit) {
        await _refreshOrderSummary();
      }
    } catch (e) {
      Get.snackbar('错误', e.toString());
    } finally {
      busy.value = false;
    }
  }

  /// 重新拉取订单详情以刷新 totals / 明细（以后端为准）
  Future<void> _refreshOrderSummary() async {
    try {
      await _fetchOrderDetailAndBuildState(orderId);
    } catch (e) {
      // 刷新失败不阻断主流程
    }
  }

  // ============== 异常提报 ==============
  /// remark: 异常原因；files：文件ID列表 或 上传返回的 key（按你们后端约定）
  Future<void> submitAbnormal({
    required String remark,
    List<String>? files,
  }) async {
    if (remark.trim().isEmpty) {
      Get.snackbar('提示', '请填写异常说明');
      return;
    }

    isPageBusy.value = true;
    try {
      final dataMap = {
        'orderId': orderId,
        'remark': remark,
        if (files != null) 'files': files,
      };

      final resp = await _dio.post(
        '/tx_purchase_order/tx_update_abnormal_order',
        data: dataMap,
      );
      final data = _normalizeRespData(resp);
      _ensureOk(data);

      abnormal.value = true;
      Get.snackbar('成功', '已提交异常订单');
      // 异常后可选择刷新详情
      await _refreshOrderSummary();
    } catch (e) {
      Get.snackbar('错误', e.toString());
    } finally {
      isPageBusy.value = false;
    }
  }

  // ============== 一键完成（闭环） ==============
  /// 调用 /tx_tms_mgmt/finish_pick_tms_order ，参数 tmsOrderId（shipmentId）
  Future<void> submitAllAndFinish() async {
    if (shipmentId.isEmpty) {
      Get.snackbar('提示', '缺少运输单 ID（tmsOrderId）');
      return;
    }

    isPageBusy.value = true;
    try {
      final resp = await _dio.post(
        '/tx_tms_mgmt/finish_pick_tms_order',
        data: {'tmsOrderId': shipmentId},
      );
      final data = _normalizeRespData(resp);
      _ensureOk(data);

      // 记录进度，并返回列表页
      final key = 'progress_$shipmentId';
      _box.write(key, orderId.toString());
      Get.snackbar('完成', '已确认完成分拣');
      Get.back(); // 回到列表
    } catch (e) {
      Get.snackbar('错误', e.toString());
    } finally {
      isPageBusy.value = false;
    }
  }

  // ============== 工具方法（响应规范化与校验） ==============
  /// 规范化响应：把 String JSON / 纯 List 包装成 {code:0,data:list}
  dynamic _normalizeRespData(dio.Response resp) {
    dynamic data = resp.data;

    // 有的服务端把 JSON 当成纯字符串返回
    if (data is String) {
      final trimmed = data.trim();
      // 明显不是 JSON，可能是未登录的 HTML
      final isHtml = trimmed.startsWith('<!DOCTYPE') || trimmed.startsWith('<html');
      if (isHtml) {
        throw Exception(_guessNonJsonReason(resp, fallback: '登录失效或被网关拦截，请重新登录'));
      }
      // 尝试解析 JSON
      try {
        data = json.decode(trimmed);
      } catch (_) {
        throw Exception('接口返回非 JSON：${_guessNonJsonReason(resp, fallback: '无法解析服务端返回')}\n$trimmed');
      }
    }

    return data;
  }

  /// 统一校验：允许 {code:0,...} / {success:true,...} / {status:'OK',...}
  void _ensureOk(dynamic data) {
    if (data is Map) {
      final code = data['code'];
      final success = data['success'];
      final status = (data['status'] ?? '').toString().toUpperCase();

      final ok = (code == 0) || (success == true) || (status == 'OK');
      if (!ok) {
        final msg = (data['msg'] ?? data['message'] ?? data['error'] ?? '接口返回失败').toString();
        throw Exception(msg);
      }
      return;
    }

    if (data is List) {
      // 有些 GET 直接返回数组，这里视作成功
      return;
    }

    throw Exception('接口返回格式错误');
  }

  String _guessNonJsonReason(dio.Response resp, {required String fallback}) {
    final sc = resp.statusCode ?? -1;
    // 注意这里加了 ?.
    final ct = resp.headers.value('content-type') ?? '';
    if (sc == 401) return '未授权（401），请检查登录态或鉴权头';
    if (sc == 403) return '无权限（403），请检查接口权限';
    if (sc == 404) return '接口不存在（404），请核对路径';
    if (ct.contains('text/html')) return '返回了 HTML（可能是登录页或网关页面）';
    return fallback;
  }


  // ============== 其它小工具 ==============
  void toggleAbnormalFlagOnly() {
    abnormal.value = !abnormal.value;
  }

  void saveProgressAndBack() {
    final key = 'progress_$shipmentId';
    _box.write(key, orderId.toString());
    Get.back();
  }
  /// 仅保存当前/指定订单的进度，不做页面跳转
  /// - orderIdOverride：如果你想把“下一条”的 id 作为进度写入，可传入覆盖
  /// - silent：是否静默（不弹提示）
  Future<void> saveProgress({String? orderIdOverride, bool silent = true}) async {
    // shipmentId 在 load() 里已从路由参数取到，用它拼接进度键
    final key = 'progress_$shipmentId';

    final valueToSave = (orderIdOverride ?? orderId.toString()).trim();
    if (valueToSave.isEmpty) return;

    _box.write(key, valueToSave);

    if (!silent) {
      Get.snackbar('已保存', '当前进度：订单 $valueToSave');
    }
  }

}

// ================== 视图模型 ==================
class CategoryVM {
  final int productId;
  final String name;
  CategoryVM({required this.productId, required this.name});
}

class OrderVideo {
  final String id;
  final String url;
  OrderVideo({required this.id, required this.url});
}

class OrderLineVM {
  final int id;
  final int productId;
  final String productName;
  final double qty;
  final double initWeight;
  final double sortWeight;
  final int uomId;
  final String uomName;
  final double recUnitPrice;
  final double recTotalPrice;

  OrderLineVM({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.initWeight,
    required this.sortWeight,
    required this.uomId,
    required this.uomName,
    required this.recUnitPrice,
    required this.recTotalPrice,
  });
}

class OrderDetailVM {
  final int id;
  final String orderNumber;
  final String orderState;
  final int equipmentId;
  final String equipmentName;
  final double totalWeight;
  final double recTotalPrice;
  final double amountTotal;
  final List<OrderVideo> videos;
  final List<OrderLineVM> lines;

  OrderDetailVM({
    required this.id,
    required this.orderNumber,
    required this.orderState,
    required this.equipmentId,
    required this.equipmentName,
    required this.totalWeight,
    required this.recTotalPrice,
    required this.amountTotal,
    required this.videos,
    required this.lines,
  });
}

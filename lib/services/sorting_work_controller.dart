// lib/services/sorting_work_controller.dart
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' as dio;
import 'package:flutter/material.dart';
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
  final tmsLines = <TmsOrderLineVM>[].obs; // 当前分拣订单的累计行
  double get tmsTotalWeight => tmsLines.fold(0.0, (s, e) => s + (e.weight));

  late int orderId;     // 采购单 ID
  late String orderNumber;
  late int equipmentId; // 设备 ID（称/柜）
  late String equipmentName;
  late String shipmentId; // tmsOrderId，用于 finish
  late String containerCode;
  // ============== 生命周期/加载 ==============
  Future<void> load(String orderIdFromRoute) async {
    isPageBusy.value = true;
    try {
      // 取路由参数
      final args = Get.arguments ?? {};
      shipmentId = (args['shipmentId'] ?? '').toString();
      containerCode = (args['containerCode'] ?? '').toString();

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
      if (containerCode.isNotEmpty) {
        await fetchTmsLinesByContainerCode(containerCode);
      }
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
  Future<void> fetchTmsLinesByContainerCode(String code) async {
    try {
      final resp = await _dio.get(
        '/tx_tms_mgmt/get_tms_order_container_code',
        queryParameters: {'containerCode': code, 'limit': 1},
      );
      final data = _normalizeRespData(resp);
      _ensureOk(data);

      final List list = (data is Map) ? (data['data'] as List? ?? const []) : [];
      if (list.isEmpty) {
        tmsLines
          ..clear()
          ..refresh();
        return;
      }
      final m = list.first as Map<String, dynamic>;
      final lineList = (m['tmsOrderLine'] as List? ?? const []);

      final parsed = <TmsOrderLineVM>[];
      for (final it in lineList) {
        final mm = it as Map<String, dynamic>;
        parsed.add(TmsOrderLineVM(
          tmsOrderLineId: (mm['tmsOrderLineId'] ?? 0) as int,
          productId: (mm['productId'] ?? 0) as int,
          productName: (mm['productName'] ?? '').toString(),
          weight: (mm['weight'] ?? 0).toDouble(),
        ));
      }

      tmsLines
        ..clear()
        ..addAll(parsed)
        ..refresh();
    } catch (e) {
      // 不中断主流程，仅提示
      debugPrint('[TMS][ERR] 拉取 tmsOrderLine 失败: $e');
    }
  }


  // ============== 两台秤：加入（B 接口） ==============
  // ============== 两台秤：加入（新接口，使用 TMS 分拣订单ID） ==============
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
    if (shipmentId.isEmpty) {
      Get.snackbar('错误', '缺少分拣订单ID（tmsOrderId / shipmentId）');
      return;
    }

    final busy = (scaleNo == 1 ? isBusyScale1 : isBusyScale2);
    if (busy.value) return; // 防抖
    busy.value = true;

    try {
      final orderIdForAdd = int.tryParse(shipmentId) ?? shipmentId;

      // 新接口：/tx_tms_mgmt/add_tms_order_line
      final path = '/tx_tms_mgmt/add_tms_order_line';
      final payload = {
        'orderId': orderIdForAdd,     // 这里用 shipmentId（分拣订单ID），不是用户采购单ID
        'productId': sel.productId,   // 分类ID
        'weight': weight,             // 累加重量（kg）
      };

      debugPrint('[ADD][REQ] POST $path  $payload');
      final resp = await _dio.post(path, data: payload);
      final data = _normalizeRespData(resp);
      _ensureOk(data);
      debugPrint('[ADD][RESP] $data');

      // 本地 totals 仍按“当前用户订单”视图做先行展示（以后端为准）
      totals[sel.productId] = (totals[sel.productId] ?? 0) + weight;
      totals.refresh();

      Get.snackbar('已加入', '称$scaleNo → ${sel.name} + ${weight.toStringAsFixed(2)} kg');

      if (refreshAfterSubmit) {
        await _refreshOrderSummary();
      }
      if (containerCode.isNotEmpty) {
        await fetchTmsLinesByContainerCode(containerCode); //  刷新分拣累计
      }
    } catch (e) {
      Get.snackbar('错误', e.toString().replaceFirst('Exception: ', ''));
    } finally {
      busy.value = false;
    }
  }
  // ============== 修改累加记录（新接口，可供后续“编辑明细”用） ==============
  Future<bool> updateTmsOrderLine({
    required int tmsOrderLineId,
    required int productId,
    required double weight,
  }) async {
    if (weight < 0) {
      Get.snackbar('提示', '重量不能为负数');
      return false;
    }
    try {
      final path = '/tx_tms_mgmt/update_tms_order_line';
      final payload = {
        'tmsOrderLineId': tmsOrderLineId,
        'productId': productId,
        'weight': weight,
      };
      debugPrint('[UPD][REQ] POST $path  $payload');
      final resp = await _dio.post(path, data: payload);
      final data = _normalizeRespData(resp);
      _ensureOk(data);
      debugPrint('[UPD][RESP] $data');

      // 这里不做本地 totals 的盲目调整，因为不知道旧值，建议调用刷新
      await _refreshOrderSummary();
      return true;
    } catch (e) {
      Get.snackbar('错误', e.toString().replaceFirst('Exception: ', ''));
      return false;
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
  // SortingWorkController 内

  Future<bool> submitAbnormal({
    required String remark,
    List<String>? files,
  }) async {
    if (remark.trim().isEmpty) return false;

    isPageBusy.value = true;
    try {
      final path = '/tx_purchase_order/tx_update_abnormal_order';

      // 1) 与 Apifox 对齐：multipart/form-data + 始终带 files
      final map = <String, dynamic>{
        'orderId': orderId.toString(),
        'remark': remark,
        'files': (files != null && files.isNotEmpty) ? files.join(',') : '',
      };
      final formData = dio.FormData.fromMap(map);

      // —— 打印请求 ——
      final url = _dio.options.baseUrl.isEmpty
          ? path
          : (_dio.options.baseUrl.endsWith('/') || path.startsWith('/')
          ? '${_dio.options.baseUrl}$path'
          : '${_dio.options.baseUrl}$path');
      debugPrint('[ABN][REQ] POST $url');
      debugPrint('[ABN][REQ] contentType: multipart/form-data');
      debugPrint('[ABN][REQ] form: $map');

      // 2) 不要强制 contentType，Dio 会根据 FormData 自动设置 multipart/form-data
      final resp = await _dio.post(
        path,
        data: formData,
      );

      // —— 打印响应 ——
      final sc = resp.statusCode ?? 0;
      final raw = resp.data;
      debugPrint('[ABN][RESP] status=$sc');
      debugPrint('[ABN][RESP] raw=${raw is String ? raw : (raw?.toString() ?? 'null')}');

      // 3) 严判：返回里有 code 时，只认 0/200 成功
      final data = _normalizeRespData(resp);
      final ok = _isOkLoose(data, httpStatus: sc);
      if (!ok) {
        final msg = _extractMsg(data) ?? '后端未返回可识别的成功标记';
        throw Exception(msg);
      }

      abnormal.value = true;
      await _refreshOrderSummary();
      return true;
    } catch (e) {
      debugPrint('[ABN][ERR] $e');
      // 只弹真实错误信息
      Get.snackbar('错误', e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      isPageBusy.value = false;
    }
  }

// ========= 改造后的 _isOkLoose =========
  bool _isOkLoose(dynamic data, {required int httpStatus}) {
    if (data is Map) {
      final hasCode = data.containsKey('code');
      final codeStr = data['code']?.toString();
      final success = data['success'] == true;
      final status = (data['status'] ?? '').toString().toUpperCase();

      if (success || status == 'OK' || status == 'SUCCESS') return true;
      if (hasCode) return codeStr == '0' || codeStr == '200';
      return httpStatus >= 200 && httpStatus < 300;
    }
    if (data is List) return true;
    if (data is bool) return data;
    if (data is String) {
      final s = data.trim().toLowerCase();
      return s == 'ok' || s == 'success' || s == 'true';
    }
    return httpStatus >= 200 && httpStatus < 300;
  }

  String? _extractMsg(dynamic data) {
    if (data is Map) return (data['msg'] ?? data['message'] ?? data['error'])?.toString();
    if (data is String && data.isNotEmpty) return data;
    return null;
  }

  // ============== 一键完成（闭环） ==============
  /// 调用 /tx_tms_mgmt/finish_pick_tms_order ，参数 tmsOrderId（shipmentId）
  // ============== 一键完成（闭环） ==============
// 顺序：1) 订单分拣完成 -> 2) 订单称重完成 -> 3) 分拣入库完成-管理员审核
  Future<void> submitAllAndFinish() async {
    if (shipmentId.isEmpty) {
      Get.snackbar('提示', '缺少运输单 ID（tmsOrderId）');
      return;
    }

    isPageBusy.value = true;
    try {
      await _finishStep(
        title: '订单分拣完成',
        path: '/tx_tms_mgmt/finish_pick_tms_order',
        payload: {'tmsOrderId': shipmentId},
      );

      await _finishStep(
        title: '订单称重完成',
        path: '/tx_tms_mgmt/finish_weighing_tms_order',
        payload: {'tmsOrderId': shipmentId},
      );

      await _finishStep(
        title: '分拣入库完成-管理员审核',
        path: '/tx_tms_mgmt/tx_check_finish_pick_order',
        payload: {'tmsOrderId': shipmentId},
      );

      // 全部成功：记录进度并返回列表页
      final key = 'progress_$shipmentId';
      _box.write(key, orderId.toString());
      Get.snackbar('完成', '已完成分拣/称重/入库审核');
      Get.back();
    } catch (e) {
      // _finishStep 已抛出“带步骤名”的异常，这里透传即可
      Get.snackbar('错误', e.toString().replaceFirst('Exception: ', ''));
    } finally {
      isPageBusy.value = false;
    }
  }

  Future<void> _finishStep({
    required String title,
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    debugPrint('[FINISH][$title][REQ] POST $path  $payload');
    final resp = await _dio.post(path, data: payload);
    final data = _normalizeRespData(resp);
    try {
      _ensureOk(data);
    } catch (e) {
      final msg = (e.toString().replaceFirst('Exception: ', '')).trim();
      // 抛出带步骤名的错误，外层捕获后直接提示
      throw Exception('$title 失败：$msg');
    }
    debugPrint('[FINISH][$title][RESP] $data');
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
  /// 一键完成：串行执行 1/2/3，并统计无异常/异常订单数量用于弹窗展示
  Future<FinishDialogData> finishAndSummarizeForDialog({
    required String containerCode,
  }) async {
    bool s1 = false, s2 = false, s3 = false;
    String? e1, e2, e3;

    // 1) 订单分拣完成
    try {
      final r1 = await _dio.post(
        '/tx_tms_mgmt/finish_pick_tms_order',
        data: {'tmsOrderId': shipmentId},
      );
      _ensureOk(_normalizeRespData(r1));
      s1 = true;
    } catch (e) {
      e1 = e.toString().replaceFirst('Exception: ', '');
    }

    // 2) 订单称重完成（仅在 1 成功后继续）
    if (s1) {
      try {
        final r2 = await _dio.post(
          '/tx_tms_mgmt/finish_weighing_tms_order',
          data: {'tmsOrderId': shipmentId},
        );
        _ensureOk(_normalizeRespData(r2));
        s2 = true;
      } catch (e) {
        e2 = e.toString().replaceFirst('Exception: ', '');
      }
    }

    // 3) 分拣入库完成-管理员审核（仅在 1、2 都成功后继续；失败也不阻断分拣员离场）
    if (s1 && s2) {
      try {
        final r3 = await _dio.post(
          '/tx_tms_mgmt/tx_check_finish_pick_order',
          data: {'tmsOrderId': shipmentId},
        );
        _ensureOk(_normalizeRespData(r3));
        s3 = true;
      } catch (e) {
        e3 = e.toString().replaceFirst('Exception: ', '');
      }
    }

    // 4) 拉柜号总结（统计无异常/异常数量）
    int normal = 0, abnormal = 0;
    try {
      final resp = await _dio.get(
        '/tx_tms_mgmt/get_tms_order_container_code',
        queryParameters: {'containerCode': containerCode, 'limit': 1},
      );
      final data = _normalizeRespData(resp);
      _ensureOk(data);
      final list = (data is Map) ? (data['data'] as List? ?? const []) : (data as List? ?? const []);
      if (list.isNotEmpty) {
        final m = list.first as Map<String, dynamic>;
        final pos = (m['purchaseOrders'] as List? ?? const []);
        for (final it in pos) {
          final mm = it as Map<String, dynamic>;
          final st = (mm['orderState'] ?? '').toString().toLowerCase();
          if (st == 'finish') {
            normal++;
          } else {
            abnormal++;
          }
        }
      }
    } catch (_) {
      // 统计失败不影响主流程
    }

    // 可选：保存一下当前进度
    final key = 'progress_$shipmentId';
    _box.write(key, orderId.toString());

    return FinishDialogData(
      step1Ok: s1,
      step2Ok: s2,
      step3Ok: s3,
      err1: e1,
      err2: e2,
      err3: e3,
      normalCount: normal,
      abnormalCount: abnormal,
    );
  }

}

// 点击一键完成后弹窗要用到的汇总数据
class FinishDialogData {
  final bool step1Ok; // 分拣完成
  final bool step2Ok; // 称重完成
  final bool step3Ok; // 管理员审核
  final String? err1;
  final String? err2;
  final String? err3;
  final int normalCount;   // 无异常订单数（orderState == 'finish'）
  final int abnormalCount; // 异常订单数（其他状态视为异常）

  FinishDialogData({
    required this.step1Ok,
    required this.step2Ok,
    required this.step3Ok,
    this.err1,
    this.err2,
    this.err3,
    required this.normalCount,
    required this.abnormalCount,
  });

  // ✅ 允许回到扫码入口的条件：前两步都成功；第三步失败通常是因为有异常单转后台审核
  bool get canLeaveToHome => step1Ok && step2Ok;
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
class TmsOrderLineVM {
  final int tmsOrderLineId;
  final int productId;
  final String productName;
  final double weight;
  TmsOrderLineVM({
    required this.tmsOrderLineId,
    required this.productId,
    required this.productName,
    required this.weight,
  });
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

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/models.dart';

class ApiClient {
  final Dio _dio;
  ApiClient._(this._dio);

  static Future<ApiClient> create() async {
    final sp = await SharedPreferences.getInstance();
    final base = sp.getString('api_base') ?? K.defaultApiBase;
    final dio = Dio(BaseOptions(baseUrl: base, connectTimeout: const Duration(seconds: 6), receiveTimeout: const Duration(seconds: 8)));
    return ApiClient._(dio);
  }

  Future<void> setBaseUrl(String url) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('api_base', url);
    _dio.options.baseUrl = url;
  }

  String get baseUrl => _dio.options.baseUrl;

  // ========== 设备/人员绑定（示例实现：若无真实接口则本地保存） ==========
  Future<Worker> bindWorkerByQr(String qr) async {
    // TODO: 若后端有“绑定分拣员/设备”的接口，请在此处调用。
    // 这里做一个模拟：QR中若带名字用"id|name"，否则使用匿名名。
    final parts = qr.split('|');
    final worker = Worker(id: parts.first, name: (parts.length > 1 ? parts[1] : '分拣员'));
    final sp = await SharedPreferences.getInstance();
    await sp.setString('worker_id', worker.id);
    await sp.setString('worker_name', worker.name);
    return worker;
  }

  Future<Worker?> getBoundWorker() async {
    final sp = await SharedPreferences.getInstance();
    final id = sp.getString('worker_id');
    final name = sp.getString('worker_name');
    if (id == null) return null;
    return Worker(id: id, name: name ?? '分拣员');
  }

  Future<void> unbindWorker() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('worker_id');
    await sp.remove('worker_name');
  }

  // ========== 与您现有后端的关键接口（按Python版本映射） ==========

  Future<List<Location>> getAllLocations() async {
    // GET /tx_tms_mgmt/get_all_tms_location_dest
    final r = await _dio.get('/tx_tms_mgmt/get_all_tms_location_dest');
    final data = (r.data['data'] as List?) ?? [];
    return data.map((e) => Location.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<Product>> getProductList() async {
    // GET /tx_purchase_order/get_product_list
    final r = await _dio.get('/tx_purchase_order/get_product_list');
    final data = (r.data['data'] as List?) ?? [];
    return data.map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Response> submitTotalWeight({
    required int orderId,
    required double weight,
    required int locationId,
  }) async {
    // 按您的桌面端逻辑，这里通常会POST订单总重量+库位
    // TODO: 将URL换成真实的提交接口
    return _dio.post('/tx_sorting/submit_total_weight', data: {
      'orderId': orderId,
      'weight': weight,
      'locationId': locationId,
    });
  }

  Future<Map<String, dynamic>> fetchOrderByQr(String qr) async {
    // TODO: 替换为后端真实接口：根据扫码内容加载订单
    // 临时模拟：返回一个空对象结构
    return {'id': 1001, 'orderNumber': 'ORD-1001', 'userName': '张三', 'totalWeight': 0.0};
  }

  Future<List<Map<String, dynamic>>> fetchOrderDetails(int orderId) async {
    // TODO: 替换为后端真实接口
    return [
      {
        'id': 1,
        'product': {'productId': 10, 'productName': '纸类', 'uomName': 'kg'},
        'qtyInit': 0.0,
        'sortWeight': 0.0
      },
      {
        'id': 2,
        'product': {'productId': 11, 'productName': '塑料', 'uomName': 'kg'},
        'qtyInit': 0.0,
        'sortWeight': 0.0
      },
    ];
  }
}

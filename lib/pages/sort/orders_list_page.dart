// lib/pages/sort/orders_list_page.dart
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import '../../models/sorting_models.dart';
import '../../services/sorting_locator.dart';

class OrdersListPage extends StatefulWidget {
  const OrdersListPage({super.key});
  @override
  State<OrdersListPage> createState() => _OrdersListPageState();
}

class _OrdersListPageState extends State<OrdersListPage> {
  final box = GetStorage();
  ResolvedShipment? _resolved;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments;
    if (args is Map) {
      _resolved = args['shipment'] as ResolvedShipment?;
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolved;
    if (resolved == null) {
      // 参数缺失的兜底 UI（也可以自动返回上一页）
      return Scaffold(
        appBar: AppBar(title: const Text('运输单')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('参数缺失，返回重试'),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: () => Get.back(), child: const Text('返回')),
            ],
          ),
        ),
      );
    }
    final poList = resolved.purchaseOrders;

    // 续作：恢复上次处理到的索引
    final progressKey = 'progress_${resolved.shipmentId}';
    final lastPoId = box.read(progressKey)?.toString();
    int initialIndex = 0;
    if (lastPoId != null) {
      final idx = poList.indexWhere((e) => e.id == lastPoId);
      if (idx >= 0) initialIndex = idx;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('运输单 ${resolved.shipmentName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {})),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.local_shipping, size: 32),
              title: Text('设备：${resolved.equipmentNumber}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              subtitle: Text('目的地：${resolved.destination}', style: const TextStyle(fontSize: 16)),
              trailing: Text('共 ${poList.length} 单', style: const TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < poList.length; i++)
            _orderCard(
              index: i,
              isResume: (i == initialIndex),
              shipmentId: resolved.shipmentId,
              po: poList[i],
              onEnter: () {
                final poIds = poList.map((e) => e.id).toList();

                Get.toNamed('/work/${poList[i].id}', arguments: {
                  'shipmentId': resolved.shipmentId,
                  'shipmentName': resolved.shipmentName,
                  'equipmentNumber': resolved.equipmentNumber,
                  'destination': resolved.destination,
                  'poNumber': poList[i].number,
                  'orderId': poList[i].id,

                  // ✅ 新增
                  'poIds': poIds,
                  'index': i,
                })?.then((_) {
                  box.write(progressKey, poList[i].id);
                  setState(() {});
                });
              },
            ),
        ],
      ),
    );
  }

  Widget _orderCard({
    required int index,
    required bool isResume,
    required String shipmentId,
    required ResolvedPO po,
    required VoidCallback onEnter,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          leading: CircleAvatar(
            radius: 22,
            child: Text('${index + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          title: Text(
            '${po.number}    ¥${po.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '时间：${po.createAt}    重量：${po.totalWeight.toStringAsFixed(2)} kg',
              style: const TextStyle(fontSize: 16),
            ),
          ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200), // ✅ 给 trailing 一点横向空间
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isResume)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Chip(
                      label: Text('上次做到这', style: TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Color(0xFFE3F2FD),
                    ),
                  ),
                SizedBox(
                  height: 40, // ✅ 稍矮一点以防 ListTile 高度紧张
                  child: ElevatedButton(
                    onPressed: onEnter,
                    child: const Text('进入', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),

        ),
      ),
    );
  }
}

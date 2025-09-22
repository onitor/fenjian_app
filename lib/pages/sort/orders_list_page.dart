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

  // ✅ 与首页统一的按钮风格
  static const Color _primaryMint = Color(0xFF26A69A); // Teal 400
  final ButtonStyle _bigPrimaryBtn = ElevatedButton.styleFrom(
    backgroundColor: _primaryMint,
    foregroundColor: Colors.white,
    minimumSize: const Size(140, 56), // 列表页里的按钮更高一些
    textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    elevation: 1.5,
  );

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
      return Scaffold(
        backgroundColor: Colors.white, // ✅ 纯白背景
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

    // ✅ 统一卡片描边样式（简洁显眼）
    final shapeWithBorder = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFF80CBC4), width: 1.2), // Teal 200 作为描边
    );

    return Scaffold(
      backgroundColor: Colors.white, // ✅ 纯白背景
      appBar: AppBar(
        title: Text(
          '运输单 ${resolved.shipmentName}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {})),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // 顶部信息卡片
          Card(
            elevation: 0.5,
            shape: shapeWithBorder,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              leading: const Icon(Icons.local_shipping, size: 34),
              title: Text(
                '设备：${resolved.equipmentNumber}',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '目的地：${resolved.destination}',
                  style: const TextStyle(fontSize: 17),
                ),
              ),
              trailing: Text('共 ${poList.length} 单', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 6),

          // 订单列表
          for (int i = 0; i < poList.length; i++)
            _orderCard(
              shapeWithBorder: shapeWithBorder,
              buttonStyle: _bigPrimaryBtn,
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
    required ShapeBorder shapeWithBorder,
    required ButtonStyle buttonStyle,
    required int index,
    required bool isResume,
    required String shipmentId,
    required ResolvedPO po,
    required VoidCallback onEnter,
  }) {
    return Card(
      elevation: 0.5,
      shape: shapeWithBorder, // ✅ 简洁显眼的描边
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: ListTile(
          // ✅ 增加整体高度 & 触控面积
          contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          leading: CircleAvatar(
            radius: 26, // ✅ 更大圆标
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          title: Text(
            '${po.number}    ¥${po.totalAmount.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Text('时间：${po.createAt}', style: const TextStyle(fontSize: 17)),
                const SizedBox(width: 16),
                Text('重量：${po.totalWeight.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 17)),
              ],
            ),
          ),
          // ✅ 右侧左右布局：芯片 + 大按钮；并给足宽度避免溢出
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 240),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (isResume)
                  const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Chip(
                      label: Text(
                        '上次做到这',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Color(0xFFE3F2FD),
                    ),
                  ),
                SizedBox(
                  height: 56, // ✅ 与首页一致的大按钮高度
                  child: ElevatedButton.icon(
                    style: buttonStyle, // ✅ 白字 + 浅蓝绿色背景
                    onPressed: onEnter,
                    icon: const Icon(Icons.arrow_forward, size: 22),
                    label: const Text('进入', style: TextStyle(overflow: TextOverflow.ellipsis)),
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

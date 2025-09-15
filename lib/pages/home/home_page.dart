// lib/pages/home/home_scan_entry.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../dio/device_identifier.dart';
import '../../services/controller.dart';
import '../../services/sorting_locator.dart';

class HomeScanEntryPage extends StatefulWidget {
  const HomeScanEntryPage({super.key});
  @override
  State<HomeScanEntryPage> createState() => _HomeScanEntryPageState();
}

class _HomeScanEntryPageState extends State<HomeScanEntryPage> {
  final eqCtl = Get.find<EquipmentController>();
  final qrCtl = Get.put(QrCodeController());
  final _locator = SortingLocatorApi();

  final _cabinetCtrl = TextEditingController(); // 无线扫码枪当键盘输入
  Uint8List? _qrPng;
  bool _bindingBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    setState(() => _bindingBusy = true);
    try {
      final androidId = await DeviceIdentifier.getDeviceId();
      await eqCtl.fetchEquipmentInfoByAndroidId(androidId);
      final eq = eqCtl.equipmentNumber ?? '—';
      final bytes = await qrCtl.fetchQrCodeImage(eq);
      setState(() => _qrPng = bytes);
    } finally {
      setState(() => _bindingBusy = false);
    }
  }

  bool get _isBound =>
      (eqCtl.equipmentNumber?.isNotEmpty == true) &&
          (eqCtl.userId?.isNotEmpty == true);
  String _roleText(String code) {
    switch (code) {
      case '5': return '分拣员';
      case '3': return '员工';
      case '1': return '用户';
      case '2': return '管理员';
      default:  return '角色$code';
    }
  }

  Future<void> _goSorting() async {
    final input = _cabinetCtrl.text.trim();
    final bound = Get.find<EquipmentController>().isBoundRx.value; // ✅

    if (!bound) {
      Get.snackbar('请先绑定设备', '点击页面上的二维码进行绑定或联系管理员');
      return;
    }
    if (input.isEmpty) {
      Get.snackbar('提示', '请扫描或输入回收柜编号/运输单号/ID');
      return;
    }

    final resolved = await _locator.resolveShipmentByContainer(
      containerCode: input,
      limit: 1,
    );
    if (resolved == null) {
      Get.snackbar('未找到', '无法定位运输单，请核对编号/权限');
      return;
    }

    Get.toNamed('/orders', arguments: {'shipment': resolved});
  }

  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = theme.textTheme.titleLarge?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
    );
    final ec = Get.find<EquipmentController>();

    return Scaffold(
      appBar: AppBar(title: const Text('分拣入口')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child:  Obx(() {
            final isBound = ec.isBoundRx.value;

            return ListView(
              children: [
                // 绑定状态卡片
                Card(
                  color: isBound ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          isBound ? Icons.verified_user : Icons.link_off,
                          size: 32,
                          color: isBound ? const Color(0xFF2E7D32) : const Color(0xFFEF6C00),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _bindingBusy
                              ? const LinearProgressIndicator()
                              : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(isBound ? '设备已绑定' : '设备未绑定', style: headline),
                              const SizedBox(height: 4),
                              Text(
                                isBound
                                    ? '设备号：${ec.equipmentNumber}    操作员ID：${ec.userId}    角色：${_roleText(ec.userRole)}'
                                    : '请使用上方二维码绑定设备；未绑定无法进入分拣。',
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // 绑定二维码
                if (_qrPng != null) ...[
                  Card(
                    elevation: 1.5,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text('手机/终端扫码绑定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          Image.memory(_qrPng!, width: 240, height: 240),
                          const SizedBox(height: 8),
                          const Text('绑定成功后状态会在上方卡片显示。', style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // 输入框 + 大按钮
                Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _cabinetCtrl,
                          autofocus: true,
                          style: const TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            labelText: '回收柜编号 / 运输单号 / 运输单ID',
                            labelStyle: const TextStyle(fontSize: 16),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            prefixIcon: const Icon(Icons.qr_code_scanner),
                          ),
                          onSubmitted: (_) => _goSorting(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.login, size: 28),
                            label: const Text('进入分拣', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            onPressed: _goSorting,
                          ),
                        ),
                        if (!isBound)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('提示：未绑定设备无法进入分拣，请先完成绑定。', style: TextStyle(color: Colors.redAccent)),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

}

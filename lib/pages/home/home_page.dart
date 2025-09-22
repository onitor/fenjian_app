// lib/pages/home/home_scan_entry.dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _scanFocus = FocusNode();              //  供扫码按钮强制聚焦
  Timer? _scanSilenceTimer;                    //  静默定时器：用于“无结束符”的枪
  static const int _scanIdleMs = 120;          //  120ms 静默判定一次扫描完成（常用）
  static const bool _autoSubmitScan = true;    //  扫描完成后是否自动跳转

  Uint8List? _qrPng;
  bool _bindingBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _scanSilenceTimer?.cancel();
    _cabinetCtrl.dispose();
    _scanFocus.dispose();
    super.dispose();
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

  String _roleText(String code) {
    switch (code) {
      case '5': return '分拣员';
      case '3': return '员工';
      case '1': return '用户';
      case '2': return '管理员';
      default:  return '角色$code';
    }
  }

  // 扫码按钮（现阶段：聚焦输入框，便于扫码枪作为键盘输入；以后可对接摄像头扫码）
  void _onScan() {
    // 让输入框获取焦点，HID 键盘（扫码枪）直接把字符打进来
    FocusScope.of(context).requestFocus(_scanFocus);
    // 体验更好：隐藏软键盘，不挡视野
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    // 可选：清空旧值，避免串码
    // _cabinetCtrl.clear();
    Get.snackbar('扫码', '请对准扫码枪进行扫描', snackPosition: SnackPosition.BOTTOM);
  }
  void _onScanTextChanged(String text) {
    // 1) 如果扫码枪发送了结束符（常见：\n、\r 或 \t），立刻提交
    if (text.contains('\n') || text.contains('\r') || text.contains('\t')) {
      final cleaned = text.replaceAll(RegExp(r'[\r\n\t]'), '');
      _cabinetCtrl.text = cleaned;
      _cabinetCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _cabinetCtrl.text.length));
      _finishScanAndGo();
      return;
    }

    // 2) 没有结束符：用“静默窗口”判定一次扫描结束（例如 120ms 没有新字符）
    _scanSilenceTimer?.cancel();
    _scanSilenceTimer = Timer(const Duration(milliseconds: _scanIdleMs), () {
      if (_autoSubmitScan) {
        _finishScanAndGo();
      }
    });
  }

  void _finishScanAndGo() {
    _scanSilenceTimer?.cancel();
    final raw = _cabinetCtrl.text.trim();
    // 保险：如果你只想要纯数字柜号，这里也可再过滤一次
    // final code = raw.replaceAll(RegExp(r'[^0-9]'), '');
    final code = raw; // 同时兼容运单号/ID
    if (code.isEmpty) return;

    // 自动跳转进入分拣
    _goSorting();

    // 如果你不想清空，注释掉
    _cabinetCtrl.clear();
  }

  Future<void> _goSorting() async {
    final input = _cabinetCtrl.text.trim();
    final bound = Get.find<EquipmentController>().isBoundRx.value;

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

  // ✅ 解绑（退出登录）按钮
  Future<void> _onUnbind() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确认解绑当前设备用户？解绑后需重新扫码绑定。'),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Get.back(result: true), child: const Text('确认')),
        ],
      ),
    );
    if (sure != true) return;

    try {
      await eqCtl.unbindEquipmentUser();
      // 本地立即刷新 UI
      eqCtl.runtimeUserId = null;
      eqCtl.isBoundRx.value = false;
      eqCtl.update();
      Get.snackbar('已退出', '设备已解绑，请重新扫码绑定');
    } catch (e) {
      Get.snackbar('错误', '解绑失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headline = theme.textTheme.titleLarge?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
    );
    final ec = Get.find<EquipmentController>();

    // ✅ 统一的按钮风格：白字 + 浅蓝绿色背景（老年友好）
    const Color primaryMint = Color(0xFF26A69A); // 浅蓝绿色（Teal 400）
    final ButtonStyle bigPrimaryBtn = ElevatedButton.styleFrom(
      backgroundColor: primaryMint,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(56),
      textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1.5,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('分拣入口')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Obx(() {
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

              // 输入框 + 扫码/进入 + 解绑
              Card(
                elevation: 1.5,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _cabinetCtrl,
                        focusNode: _scanFocus,                     // ✅ 扫码按钮会把焦点给它
                        autofocus: true,
                        style: const TextStyle(fontSize: 18),
                        keyboardType: TextInputType.visiblePassword,
                        textInputAction: TextInputAction.done,
                        enableInteractiveSelection: true,          // 允许人工修正
                        inputFormatters: [
                          // 你要是只允许纯数字柜号，用下面这一行：
                          // FilteringTextInputFormatter.digitsOnly,
                          // 如果还想兼容运单号/柜号混合，就允许常见字母数字和 - _
                          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-_]')),
                        ],
                        decoration: InputDecoration(
                          labelText: '回收柜编号 / 运输单号 / 运输单ID',
                          labelStyle: const TextStyle(fontSize: 16),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.qr_code_scanner),
                        ),
                        // ✅ 情况1：扫码枪大多会发 Enter/Tab 作为结束；我们在 onChanged 里识别
                        onChanged: _onScanTextChanged,
                        // ✅ 情况2：如果确实发送了 “Enter”，这里也能兜住
                        onSubmitted: (_) => _finishScanAndGo(),
                      ),

                      const SizedBox(height: 12),

                      // ✅ 扫码 + 进入 分成左右两个大按钮
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: bigPrimaryBtn,
                              onPressed: _onScan,
                              icon: const Icon(Icons.qr_code_scanner, size: 24),
                              label: const Text('扫码', overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: bigPrimaryBtn,
                              onPressed: _goSorting,
                              icon: const Icon(Icons.login, size: 24),
                              label: const Text('进入分拣', overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                      ),

                      if (!isBound)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('提示：未绑定设备无法进入分拣，请先完成绑定。', style: TextStyle(color: Colors.redAccent)),
                        ),

                      const SizedBox(height: 12),

                      // ✅ 退出登录（解绑）按钮
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: bigPrimaryBtn,
                          onPressed: isBound ? _onUnbind : null, // 未绑定时不可点
                          icon: const Icon(Icons.logout),
                          label: const Text('退出登录（解绑）'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

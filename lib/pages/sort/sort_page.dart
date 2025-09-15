// lib/pages/sort/sort_page.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/sorting_work_controller.dart';
import 'package:video_player/video_player.dart';
import 'package:get_storage/get_storage.dart';
class SortingWorkPage extends StatefulWidget {
  const SortingWorkPage({Key? key}) : super(key: key);

  @override
  State<SortingWorkPage> createState() => _SortingWorkPageState();
}

class _SortingWorkPageState extends State<SortingWorkPage> {
  late final SortingWorkController c;
  final _w1 = TextEditingController();
  final _w2 = TextEditingController();
  final _abRemark = TextEditingController();
  final _abFiles = TextEditingController();

  @override
  void initState() {
    super.initState();
    c = Get.put(SortingWorkController());

    final orderIdStr = _extractOrderIdString();
    if (orderIdStr.isEmpty) {
      Get.snackbar('提示', '没有获取到订单ID');
      Get.back();
      return;
    }
    c.load(orderIdStr);
  }

  String _extractOrderIdString() {
    final args = Get.arguments;
    if (args is Map) {
      final v = (args['orderId'] ?? args['id'])?.toString();
      if (v != null && v.trim().isNotEmpty) return v;
    }
    if (Get.parameters.isNotEmpty) {
      final v = Get.parameters['orderId'] ?? Get.parameters['id'];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    final route = Get.currentRoute;
    if (route.isNotEmpty) {
      final parts = route.split('/');
      if (parts.isNotEmpty) {
        final last = parts.last.trim();
        if (int.tryParse(last) != null) return last;
      }
    }
    return '';
  }

  @override
  void dispose() {
    _w1.dispose();
    _w2.dispose();
    _abRemark.dispose();
    _abFiles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bigBtnStyle = ElevatedButton.styleFrom(
      minimumSize: const Size.fromHeight(60), // 更高
      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );

    return Obx(() {
      final d = c.detail.value;

      return Scaffold(
        appBar: AppBar(
          title: Text(d?.orderNumber ?? '分拣作业', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: '异常标记（本地开关）',
              icon: Icon(c.abnormal.value ? Icons.flag : Icons.outlined_flag),
              onPressed: c.toggleAbnormalFlagOnly,
            ),
          ],
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _headerCard(),
                const SizedBox(height: 12),
                _videoCard(),
                const SizedBox(height: 12),
                _scalesRow(), // 两台秤
                const SizedBox(height: 12),
                _recordsCard(),
                const SizedBox(height: 12),
                _summaryCard(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: bigBtnStyle,
                        onPressed: _openAbnormalDialog,
                        icon: const Icon(Icons.report_gmailerrorred),
                        label: const Text('异常订单', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: bigBtnStyle,
                        onPressed:  _goNext,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('下一条', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: bigBtnStyle,
                  onPressed: c.isPageBusy.value ? null : c.submitAllAndFinish,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('一键确认完成所有正常订单', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                const Text('完成后可回到入口页继续扫码其它柜号开始新流程。', style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 24),
              ],
            ),
            if (c.isPageBusy.value)
              Container(
                color: Colors.black.withOpacity(0.05),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      );
    });
  }

  // 顶部摘要
  Widget _headerCard() {
    final d = c.detail.value;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 8,
          children: [
            _kv('订单号', d?.orderNumber ?? '-'),
            _kv('状态', d?.orderState ?? '-'),
            _kv('设备', d == null ? '-' : '${d.equipmentName} (#${d.equipmentId})'),
            _kv('总重(后端)', d == null ? '-' : '${d.totalWeight} kg'),
            _kv('金额(后端)', d == null ? '-' : '${d.recTotalPrice}'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k：', style: const TextStyle(color: Colors.black54, fontSize: 16)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
      ],
    );
  }

  // 内嵌视频卡片（不跳转）
  Widget _videoCard() {
    final url = c.detail.value?.videos.isNotEmpty == true ? c.detail.value!.videos.first.url : '';
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('订单视频', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (url.isEmpty)
              const AspectRatio(
                aspectRatio: 16/9,
                child: Center(child: Text('暂无视频')),
              )
            else
              InlineVideo(url: url),
          ],
        ),
      ),
    );
  }

  // 两台秤卡片（适配老年用户：大下拉、大输入、大按钮）
  Widget _scalesRow() {
    final cats = c.categories;
    return LayoutBuilder(
      builder: (ctx, cons) {
        final isNarrow = cons.maxWidth < 700;
        final left = Expanded(child: _scaleCard(
          title: '秤 1',
          busy: c.isBusyScale1.value,
          selected: c.selected1.value,
          onCatChanged: (v) => c.selected1.value = v,
          cats: cats,
          weightCtrl: _w1,
          onAdd: () => _onAdd(1, _w1.text),
        ));
        final right = Expanded(child: _scaleCard(
          title: '秤 2',
          busy: c.isBusyScale2.value,
          selected: c.selected2.value,
          onCatChanged: (v) => c.selected2.value = v,
          cats: cats,
          weightCtrl: _w2,
          onAdd: () => _onAdd(2, _w2.text),
        ));
        return isNarrow
            ? Column(children: [left, const SizedBox(height: 12), right])
            : Row(children: [left, const SizedBox(width: 12), right]);
      },
    );
  }

  Widget _scaleCard({
    required String title,
    required bool busy,
    required CategoryVM? selected,
    required void Function(CategoryVM?) onCatChanged,
    required List<CategoryVM> cats,
    required TextEditingController weightCtrl,
    required VoidCallback onAdd,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CategoryVM>(
              decoration: InputDecoration(
                labelText: '选择分类（来自后端）',
                labelStyle: const TextStyle(fontSize: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              isExpanded: true,
              value: selected,
              style: const TextStyle(fontSize: 18, color: Colors.black87),
              items: cats
                  .map((e) => DropdownMenuItem(
                value: e,
                child: Text('${e.name}（#${e.productId}）'),
              ))
                  .toList(),
              onChanged: onCatChanged,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: weightCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 18),
              decoration: InputDecoration(
                labelText: '稳定重量 (kg)',
                labelStyle: const TextStyle(fontSize: 16),
                hintText: '例如：1.25',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.scale),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: busy ? null : onAdd,
                icon: const Icon(Icons.add, size: 28),
                label: const Text('加入', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onAdd(int scaleNo, String weightStr) {
    final w = double.tryParse(weightStr.trim());
    if (w == null || w <= 0) {
      Get.snackbar('提示', '请输入有效的稳定重量');
      return;
    }
    c.addFromScale(scaleNo: scaleNo, weight: _round2(w));
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100.0;

  // 订单行记录（简洁）
  Widget _recordsCard() {
    final lines = c.detail.value?.lines ?? [];
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('当前订单记录', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (lines.isEmpty)
              const Text('暂无记录', style: TextStyle(color: Colors.black54))
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('产品')),
                    DataColumn(label: Text('初始重')),
                    DataColumn(label: Text('已分拣重')),
                    DataColumn(label: Text('单位')),
                    DataColumn(label: Text('单价')),
                    DataColumn(label: Text('小计')),
                  ],
                  rows: [
                    for (final l in lines)
                      DataRow(cells: [
                        DataCell(Text('${l.productName} (#${l.productId})')),
                        DataCell(Text('${_round2(l.initWeight)} kg')),
                        DataCell(Text('${_round2(l.sortWeight)} kg')),
                        DataCell(Text(l.uomName)),
                        DataCell(Text('${_round2(l.recUnitPrice)}')),
                        DataCell(Text('${_round2(l.recTotalPrice)}')),
                      ]),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 汇总卡片
  Widget _summaryCard() {
    final cats = c.categories;
    final totals = c.totals;
    final lines = c.detail.value?.lines ?? [];

    double sumAll = 0;
    for (final v in totals.values) sumAll += v;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('分类累计（以后端为准）', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('产品')),
                  DataColumn(label: Text('累计分拣重')),
                  DataColumn(label: Text('初始重')),
                  DataColumn(label: Text('剩余可分配')),
                ],
                rows: [
                  for (final cat in cats)
                    DataRow(cells: [
                      DataCell(Text('${cat.name} (#${cat.productId})')),
                      DataCell(Text('${_round2(totals[cat.productId] ?? 0)} kg')),
                      DataCell(Text('${_round2(_initOf(lines, cat.productId))} kg')),
                      DataCell(Text('${_round2(max(0, _initOf(lines, cat.productId) - (totals[cat.productId] ?? 0)))} kg')),
                    ]),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text('当前订单总分拣重：${_round2(sumAll)} kg', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  double _initOf(List<OrderLineVM> lines, int pid) {
    final line = lines.where((e) => e.productId == pid);
    double s = 0;
    for (final l in line) s += l.initWeight;
    return s;
  }

  // 异常单弹窗
  void _openAbnormalDialog() {
    _abRemark.text = '';
    _abFiles.text = '';
    Get.dialog(
      AlertDialog(
        title: const Text('生成异常订单'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _abRemark,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '异常说明（必填）',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _abFiles,
                decoration: const InputDecoration(
                  labelText: '文件ID（逗号分隔，可选）',
                ),
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '说明：此处以“文件ID”方式提交；若你们是 Multipart 上传，请在 Controller 内将其改为 FormData',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              final remark = _abRemark.text.trim();
              final files = _abFiles.text.trim().isEmpty
                  ? null
                  : _abFiles.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              await c.submitAbnormal(remark: remark, files: files);
              if (Get.isDialogOpen == true) Get.back();
            },
            child: const Text('提交'),
          ),
        ],
      ),
    );
  }
  void _goNext() async {
    // 可选：先保存当前进度（建议把 c.saveProgressAndBack 拆成“保存”和“返回”两步）
    await c.saveProgress(); // 需要在 controller 里提供一个不 pop 的保存方法

    final args = Get.arguments as Map? ?? {};
    final List<dynamic> poIdsDyn = (args['poIds'] as List?) ?? const [];
    final poIds = poIdsDyn.map((e) => e.toString()).toList();
    final curIndex = (args['index'] as int?) ?? -1;

    if (poIds.isEmpty || curIndex < 0) {
      Get.snackbar('提示', '缺少订单序列信息，无法跳到下一条');
      return;
    }

    final nextIndex = curIndex + 1;
    if (nextIndex >= poIds.length) {
      Get.snackbar('完成', '已是最后一条订单');
      // 这里你可以选择：自动返回列表，或停在当前页
      Get.back(); // 返回列表
      return;
    }

    final nextId = poIds[nextIndex];

    // ✅ 持久化“上次处理到哪条”
    final shipmentId = (args['shipmentId'] ?? '').toString();
    if (shipmentId.isNotEmpty) {
      final box = GetStorage();
      box.write('progress_$shipmentId', nextId);
    }

    // 复用原始参数，只改 orderId / poNumber / index
    final newArgs = Map<String, dynamic>.from(args);
    newArgs['orderId'] = nextId;
    newArgs['index'] = nextIndex;
    // 如果你也想更新 poNumber，可在进入详情时把 {id:number} 的 map 也传过来做查表

    // ✅ 用 off 替换当前页，不回列表
    Get.offNamed('/work/$nextId', arguments: newArgs);
  }

}

// ============== 内嵌视频组件（video_player） ==============
class InlineVideo extends StatefulWidget {
  final String url;
  const InlineVideo({Key? key, required this.url}) : super(key: key);

  @override
  State<InlineVideo> createState() => _InlineVideoState();
}

class _InlineVideoState extends State<InlineVideo> {
  late final VideoPlayerController _controller;
  bool _initError = false;

  @override
  void initState() {
    super.initState();
    final cleaned = widget.url.trim().replaceAll(RegExp(r'[\\\s]+$'), '');
    _controller = VideoPlayerController.networkUrl(Uri.parse(cleaned))
      ..setLooping(false);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize();
      setState(() {});
    } catch (e) {
      _initError = true;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _controller.value.isInitialized && _controller.value.aspectRatio != 0
          ? _controller.value.aspectRatio
          : 16 / 9,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(color: Colors.black12),
          if (_initError)
            const Center(child: Text('视频初始化失败', style: TextStyle(color: Colors.red)))
          else if (!_controller.value.isInitialized)
            const Center(child: CircularProgressIndicator())
          else
            GestureDetector(
              onTap: () {
                if (_controller.value.isPlaying) {
                  _controller.pause();
                } else {
                  _controller.play();
                }
                setState(() {});
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VideoPlayer(_controller),
                  if (!_controller.value.isPlaying)
                    const Icon(Icons.play_circle_outline, size: 72, color: Colors.white70),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

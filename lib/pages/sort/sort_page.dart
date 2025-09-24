// lib/pages/sort/sort_page.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/scale_service.dart';
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
  late final ScaleService scale;
  late StreamSubscription<double> _sub1, _sub2;
  late String _containerCode;
  // 秤关联控件
  final _w1 = TextEditingController();
  final _w2 = TextEditingController();

  // 实时读数（仅显示用）
  double? _live1;
  double? _live2;

  // 异常弹窗
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
    final args = Get.arguments as Map? ?? {};
    _containerCode = (args['containerCode'] ?? '').toString();
    c.load(orderIdStr);

    scale = createScaleService();

    // 打印可见设备，便于确认
    scale.listDevices().then((list) {
      for (final d in list) {
        debugPrint('USB DEVICE => $d');
      }
    });

    // 启动串口（Prolific PL2303 = 0x067B:0x23A3）
    scale.start(
      baud: 9600,
      vid: 0x067B,
      pid: 0x23A3,
      factor1: 11.42, // 需要通过标定获得
      factor2: 11.80,
    );

    //  保留一次订阅就好
    _sub1 = scale.watchCurrentWeight(1).listen((w) {
      _live1 = w;
      _w1.text = w.toStringAsFixed(2);
      debugPrint('[Scale] #1 => $w kg');
      setState(() {});
    });
    _sub2 = scale.watchCurrentWeight(2).listen((w) {
      _live2 = w;
      _w2.text = w.toStringAsFixed(2);
      debugPrint('[Scale] #2 => $w kg');
      setState(() {});
    });
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
    try { _sub1.cancel(); } catch (_) {}
    try { _sub2.cancel(); } catch (_) {}
    // 不 stop，让端口常驻，下一页只需重新 listen 即可
    _w1.dispose();
    _w2.dispose();
    _abRemark.dispose();
    _abFiles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ========= 统一视觉：按钮 & 卡片 =========
    const Color primaryMint = Color(0xFF26A69A); // Teal 400
    final ButtonStyle bigPrimaryBtn = ElevatedButton.styleFrom(
      backgroundColor: primaryMint,
      foregroundColor: Colors.white,
      minimumSize: const Size.fromHeight(60),
      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1.5,
    );
    final ShapeBorder shapeWithBorder = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFF80CBC4), width: 1.2),
    );

    return Obx(() {
      final d = c.detail.value;

      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            d?.orderNumber ?? '分拣作业',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          actions: [
            PopupMenuButton<int>(
              tooltip: '去皮',
              icon: const Icon(Icons.scale),
              onSelected: (v) async {
                await scale.tare(id: v == 3 ? null : v); // 1/2 单秤；3 表示全部→传 null
                Get.snackbar('去皮', v == 1 ? '已去皮：秤1' : v == 2 ? '已去皮：秤2' : '已去皮：全部');
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 1, child: Text('只去皮：秤1')),
                PopupMenuItem(value: 2, child: Text('只去皮：秤2')),
                PopupMenuItem(value: 3, child: Text('全部去皮')),
              ],
            ),
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
                _headerCard(shapeWithBorder),
                const SizedBox(height: 12),
                _videoCard(shapeWithBorder),
                const SizedBox(height: 12),
                _scalesRow(shapeWithBorder, bigPrimaryBtn), // 两台秤
                const SizedBox(height: 12),
                _recordsCard(shapeWithBorder),
                const SizedBox(height: 12),
                _summaryCard(shapeWithBorder),
                const SizedBox(height: 16),

                // 底部操作区：异常 / 下一条
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: bigPrimaryBtn,
                        onPressed: _openAbnormalDialog,
                        icon: const Icon(Icons.report_gmailerrorred),
                        label: const Text('异常订单'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: bigPrimaryBtn,
                        onPressed: _goNext,
                        icon: const Icon(Icons.skip_next),
                        label: const Text('下一条'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 一键完成
                ElevatedButton.icon(
                  style: bigPrimaryBtn,
                  onPressed: c.isPageBusy.value ? null : _onFinishTap,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('一键确认完成所有正常订单'),
                ),

                const SizedBox(height: 8),
                const Text('完成后可回到入口页继续扫码其它柜号开始新流程。', style: TextStyle(color: Colors.black54, fontSize: 16)),
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
  Widget _headerCard(ShapeBorder shapeWithBorder) {
    final d = c.detail.value;
    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: shapeWithBorder,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 10,
          children: [
            _kv('订单号', d?.orderNumber ?? '-'),
            _kv('状态', d?.orderState ?? '-'),
            _kv('设备', d == null ? '-' : '${d.equipmentName} (#${d.equipmentId})'),
            _kv('总重', d == null ? '-' : '${d.totalWeight} kg'),
            _kv('金额', d == null ? '-' : '${d.recTotalPrice}'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$k：', style: const TextStyle(color: Colors.black54, fontSize: 18)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ],
    );
  }

  // 内嵌视频卡片
  Widget _videoCard(ShapeBorder shapeWithBorder) {
    final url = c.detail.value?.videos.isNotEmpty == true ? c.detail.value!.videos.first.url : '';
    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: shapeWithBorder,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('订单视频', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (url.isEmpty)
              const AspectRatio(
                aspectRatio: 16 / 9, // 固定 16:9，加载与否高度一致
                child: Center(child: Text('暂无视频', style: TextStyle(fontSize: 18))),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InlineVideo(url: url), // 内部已固定 16:9
              ),
          ],
        ),
      ),
    );
  }

  // 两台秤卡片
  Widget _scalesRow(ShapeBorder shapeWithBorder, ButtonStyle bigPrimaryBtn) {
    final cats = c.categories;
    return LayoutBuilder(
      builder: (ctx, cons) {
        final isNarrow = cons.maxWidth < 700;
        final left = Expanded(child: _scaleCard(
          shapeWithBorder: shapeWithBorder,
          title: '秤 1',
          busy: c.isBusyScale1.value,
          selected: c.selected1.value,
          onCatChanged: (v) => c.selected1.value = v,
          cats: cats,
          weightCtrl: _w1,
          live: _live1,
          onTare: () async => await scale.tare(id: 1),
          onAdd: () => _onAdd(1, _w1.text),
          btnStyle: bigPrimaryBtn,
        ));
        final right = Expanded(child: _scaleCard(
          shapeWithBorder: shapeWithBorder,
          title: '秤 2',
          busy: c.isBusyScale2.value,
          selected: c.selected2.value,
          onCatChanged: (v) => c.selected2.value = v,
          cats: cats,
          weightCtrl: _w2,
          live: _live2,
          onTare: () async => await scale.tare(id: 2),
          onAdd: () => _onAdd(2, _w2.text),
          btnStyle: bigPrimaryBtn,
        ));
        return isNarrow
            ? Column(children: [left, const SizedBox(height: 12), right])
            : Row(children: [left, const SizedBox(width: 12), right]);
      },
    );
  }

  Widget _scaleCard({
    required ShapeBorder shapeWithBorder,
    required String title,
    required bool busy,
    required CategoryVM? selected,
    required void Function(CategoryVM?) onCatChanged,
    required List<CategoryVM> cats,
    required TextEditingController weightCtrl,
    required double? live,
    required Future<void> Function() onTare,
    required VoidCallback onAdd,
    required ButtonStyle btnStyle,
  }) {
    const Color primaryMint = Color(0xFF26A69A);
    final tareBtnStyle = ElevatedButton.styleFrom(
      backgroundColor: primaryMint,
      foregroundColor: Colors.white,
      minimumSize: const Size(86, 48), // 更大的点击面积
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0.8,
    );

    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: shapeWithBorder,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: 10),

            // 实时读数
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '实时：${live?.toStringAsFixed(2) ?? '--'} kg',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black87),
              ),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<CategoryVM>(
              decoration: InputDecoration(
                labelText: '选择分类',
                labelStyle: const TextStyle(fontSize: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              isExpanded: true,
              value: selected,
              style: const TextStyle(fontSize: 18, color: Colors.black87),
              menuMaxHeight: 420,
              items: cats
                  .map((e) => DropdownMenuItem(
                value: e,
                child: Text('${e.name}（#${e.productId}）', style: const TextStyle(fontSize: 18)),
              ))
                  .toList(),
              onChanged: onCatChanged,
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: weightCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: '稳定重量 (kg)',
                      labelStyle: const TextStyle(fontSize: 18),
                      hintText: '输入重量',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.scale, size: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                //  只保留“去皮”，更明显
                ElevatedButton(
                  style: tareBtnStyle,
                  onPressed: onTare,
                  child: const Text('去皮'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                style: btnStyle,
                onPressed: busy ? null : onAdd,
                icon: const Icon(Icons.add, size: 30),
                label: const Text('加入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onAdd(int scaleNo, String weightStr) async {
    final w = double.tryParse(weightStr.trim());
    if (w == null || w <= 0) {
      Get.snackbar('提示', '请输入有效的稳定重量');
      return;
    }
    await c.addFromScale(scaleNo: scaleNo, weight: _round2(w));
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100.0;

  // 订单行记录
  Widget _recordsCard(ShapeBorder shapeWithBorder) {
    final lines = c.detail.value?.lines ?? [];
    final table = DataTable(
      //  去掉“已分拣重”和“小计”
      columns: const [
        DataColumn(label: Text('产品')),
        DataColumn(label: Text('初始重')),
        DataColumn(label: Text('单位')),
        DataColumn(label: Text('单价')),
      ],
      rows: [
        for (final l in lines)
          DataRow(cells: [
            DataCell(Text('${l.productName} (#${l.productId})')),
            DataCell(Text('${_round2(l.initWeight)} kg')),
            DataCell(Text(l.uomName)),
            DataCell(Text('${_round2(l.recUnitPrice)}')),
          ]),
      ],
    );

    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: shapeWithBorder,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('当前订单记录', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (lines.isEmpty)
              const Text('暂无记录', style: TextStyle(color: Colors.black54, fontSize: 16))
            else
              Theme(
                data: Theme.of(context).copyWith(
                  dataTableTheme: const DataTableThemeData(
                    headingTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    dataTextStyle: TextStyle(fontSize: 18),
                    headingRowHeight: 56,
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 64,
                    dividerThickness: 0.6,
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: table,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // 汇总卡片（分拣累计）
  Widget _summaryCard(ShapeBorder shapeWithBorder) {
    final lines = c.tmsLines; //  来自分拣订单的累计行
    final sumAll = lines.fold<double>(0.0, (s, e) => s + e.weight);

    final table = DataTable(
      columnSpacing: 56, //  列间距更大
      columns: const [
        DataColumn(label: Text('行ID')),
        DataColumn(label: Text('产品')),
        DataColumn(label: Text('累计分拣重(kg)')),
        DataColumn(label: Text('产品ID')),
      ],
      rows: [
        for (final l in lines)
          DataRow(cells: [
            DataCell(Text('${l.tmsOrderLineId}')),
            DataCell(Text(l.productName)),
            DataCell(Text(_round2(l.weight).toString())),
            DataCell(Text('${l.productId}')),
          ]),
      ],
    );

    return Card(
      elevation: 0.5,
      color: Colors.white,
      shape: shapeWithBorder,
      child: Padding(
        padding: const EdgeInsets.all(16), //  padding 略大
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('分拣累计', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)), //  字号更大
            const SizedBox(height: 12),
            Theme(
              data: Theme.of(context).copyWith(
                dataTableTheme: const DataTableThemeData(
                  headingTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800), //  大一号
                  dataTextStyle: TextStyle(fontSize: 20), //  大一号
                  headingRowHeight: 60,
                  dataRowMinHeight: 60,
                  dataRowMaxHeight: 72,
                  dividerThickness: 0.6,
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '分拣订单累计总重：${_round2(sumAll)} kg',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800), //  大一号
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 异常单弹窗
  void _openAbnormalDialog() {
    _abRemark.text = '';
    _abFiles.text = '';

    // ✅ 快捷短语（可按需增删）
    const suggestions = <String>[
      '该订单分类与视频不符合',
      '该订单分类有异物，重量不符',
      '视频不清晰，无法核验',
      '缺少关键画面，需复核',
      '称重异常，需复称',
    ];

    Get.dialog(
      AlertDialog(
        title: const Text('生成异常订单'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ 快捷选择区
              const Text('快捷说明（点一下即可填入）',
                  style: TextStyle(fontSize: 14, color: Colors.black54)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in suggestions)
                    ActionChip(
                      label: Text(s, style: const TextStyle(fontSize: 13)),
                      onPressed: () {
                        final cur = _abRemark.text.trim();
                        final next = cur.isEmpty ? s : '$cur；$s';
                        _abRemark.text = next;
                        _abRemark.selection = TextSelection.collapsed(
                          offset: _abRemark.text.length,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // 备注输入
              TextField(
                controller: _abRemark,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '异常说明（必填）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),

              // 附件ID（可选）
              TextField(
                controller: _abFiles,
                decoration: const InputDecoration(
                  labelText: '文件ID（逗号分隔，可选）',
                  border: OutlineInputBorder(),
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
              if (remark.isEmpty) {
                Get.snackbar('提示', '请填写异常说明');
                return;
              }
              final files = _abFiles.text.trim().isEmpty
                  ? null
                  : _abFiles.text
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();

              // 忙态
              Get.dialog(const Center(child: CircularProgressIndicator()),
                  barrierDismissible: false);

              try {
                final ok = await c.submitAbnormal(remark: remark, files: files);

                // 一次性关闭两个对话框（忙态 + 输入框）
                if (Get.isDialogOpen == true) {
                  Get.close(2);
                }

                // 在微任务中再弹提示，避免和路由动画冲突
                Future.microtask(() {
                  if (ok) {
                    Get.snackbar('成功', '异常订单已提交');
                  } else {
                    Get.snackbar('失败', '提交失败，请稍后再试');
                  }
                });
              } catch (e) {
                if (Get.isDialogOpen == true) {
                  Get.close(1); // 至少关掉忙态
                }
                Future.microtask(() {
                  Get.snackbar('错误', '提交异常失败：$e');
                });
              }
            },
            child: const Text('提交'),
          )
        ],
      ),
    );
  }
  Future<void> _onFinishTap() async {
    if (_containerCode.isEmpty) {
      Get.snackbar('提示', '缺少柜号（containerCode），无法统计总结');
    }
    c.isPageBusy.value = true;
    try {
      final res = await c.finishAndSummarizeForDialog(containerCode: _containerCode);
      _showFinishDialog(res);
    } finally {
      c.isPageBusy.value = false;
    }
  }

  void _showFinishDialog(FinishDialogData d) {
    final title = (d.step1Ok && d.step2Ok)
        ? (d.abnormalCount > 0 && !d.step3Ok ? '已完成（异常待审核）' : '已完成')
        : '未完成';

    Get.dialog(
      AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('无异常订单：', style: TextStyle(fontSize: 18)),
                Text('${d.normalCount}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('异常订单：', style: TextStyle(fontSize: 18)),
                Text('${d.abnormalCount}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            _stepLine('分拣完成', d.step1Ok, d.err1),
            _stepLine('称重完成', d.step2Ok, d.err2),
            _stepLine('管理员审核', d.step3Ok, d.err3,
                hintWhenFail: (d.step1Ok && d.step2Ok && d.abnormalCount > 0)
                    ? '存在异常订单，后台审核通过后自动完成'
                    : null),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('返回'),
          ),
          ElevatedButton(
            onPressed: () {
              if (d.canLeaveToHome) {
                // ✅ 前两步成功即可回扫码入口；第三步失败一般是异常待审核，不拦分拣员
                Get.offAllNamed('/'); // 按你的首页路由调整
              } else {
                // ❌ 第 1/2 步失败：提供重试链路
                Get.back();
                _onFinishTap();
              }
            },
            child: Text(d.canLeaveToHome ? '回到扫码入口' : '重试完成'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  Widget _stepLine(String name, bool ok, String? err, {String? hintWhenFail}) {
    final color = ok ? Colors.green : Colors.red;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ok ? Icons.check_circle : Icons.error, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$name：${ok ? '成功' : '失败'}', style: TextStyle(fontSize: 16, color: color)),
                if (!ok && (err?.isNotEmpty ?? false))
                  Text(err!, style: const TextStyle(fontSize: 14, color: Colors.black54)),
                if (!ok && hintWhenFail != null)
                  Text(hintWhenFail, style: const TextStyle(fontSize: 13, color: Colors.orange)),
              ],
            ),
          ),
        ],
      ),
    );
  }


  void _goNext() async {
    await c.saveProgress();

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
      Get.back();
      return;
    }

    final nextId = poIds[nextIndex];
    final shipmentId = (args['shipmentId'] ?? '').toString();
    if (shipmentId.isNotEmpty) {
      final box = GetStorage();
      box.write('progress_$shipmentId', nextId);
    }

    final newArgs = Map<String, dynamic>.from(args);
    newArgs['orderId'] = nextId;
    newArgs['index'] = nextIndex;

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
  double _speed = 1.0; //  倍速

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
      await _controller.setPlaybackSpeed(_speed);
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
    // 外层固定 16:9，高度一致
    return AspectRatio(
      aspectRatio: 16 / 9,
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
                  // 播放画面（内部自适应）
                  Positioned.fill(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _controller.value.size.width,
                        height: _controller.value.size.height,
                        child: VideoPlayer(_controller),
                      ),
                    ),
                  ),

                  if (!_controller.value.isPlaying)
                    const Icon(Icons.play_circle_outline, size: 88, color: Colors.white70),

                  // 更大的可拖动区域（高度 40）
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 10,
                    child: SizedBox(
                      height: 40,
                      child: Center(
                        child: VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ),

                  // 倍速按钮（右上角）
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: PopupMenuButton<double>(
                        tooltip: '播放速度',
                        initialValue: _speed,
                        onSelected: (v) async {
                          _speed = v;
                          try {
                            await _controller.setPlaybackSpeed(v);
                          } catch (_) {}
                          setState(() {});
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 0.5, child: Text('0.5x')),
                          PopupMenuItem(value: 1.0, child: Text('1.0x')),
                          PopupMenuItem(value: 1.5, child: Text('1.5x')),
                          PopupMenuItem(value: 2.0, child: Text('2.0x')),
                        ],
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            '${_speed.toStringAsFixed(_speed == _speed.roundToDouble() ? 0 : 1)}x',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/constants.dart';
import '../../models/models.dart';
import '../../services/api_client.dart';
import '../../state/app_state.dart';

class SortPage extends ConsumerStatefulWidget {
  const SortPage({super.key});
  @override
  ConsumerState<SortPage> createState() => _SortPageState();
}

class _SortPageState extends ConsumerState<SortPage> {
  OrderBrief? _order;
  List<OrderDetailLine> _lines = const [];
  bool _loading = false;
  final _videoUrlCtrl = TextEditingController();

  Future<void> _scanOrder() async {
    String? code;
    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('扫描订单二维码'),
        content: SizedBox(
          width: 480, height: 360,
          child: MobileScanner(onDetect: (cap){
            final raw = cap.barcodes.first.rawValue;
            if (raw != null) { code = raw; Navigator.pop(ctx); }
          }),
        ),
      );
    });
    if (code == null) return;
    final api = ref.read(apiProvider);
    setState(()=> _loading = true);
    try {
      final o = await api.fetchOrderByQr(code!);
      final brief = OrderBrief(
        id: o['id'] as int,
        orderNumber: o['orderNumber'] as String,
        userName: o['userName'] as String,
        totalWeight: (o['totalWeight'] as num).toDouble(),
      );
      final linesRaw = await api.fetchOrderDetails(brief.id);
      _lines = linesRaw.map((m){
        final p = Product.fromJson(m['product'] as Map<String,dynamic>);
        return OrderDetailLine(id: m['id'] as int, product: p, qtyInit: (m['qtyInit'] as num).toDouble(), sortWeight: (m['sortWeight'] as num).toDouble());
      }).toList();
      setState(()=> _order = brief);
      ref.read(currentOrderProvider.notifier).set(brief);
    } finally {
      setState(()=> _loading = false);
    }
  }
  // 2) 新增方法：手动输入订单号并拉单
  Future<void> _manualOrderInput() async {
    final ctrl = TextEditingController();
    final orderNo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入订单号'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '例如：ORD2025XXXX'),
        ),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: ()=> Navigator.pop(ctx, ctrl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (orderNo == null || orderNo.isEmpty) return;

    final api = ref.read(apiProvider);
    setState(()=> _loading = true);
    try {
      // 方案 A：如果你后端“扫码/订单号”走一个接口
      final o = await api.fetchOrderByQr(orderNo);

      // 方案 B：如果有专门按订单号查询
      // final o = await api.fetchOrderByNumber(orderNo);

      final brief = OrderBrief(
        id: o['id'] as int,
        orderNumber: o['orderNumber'] as String,
        userName: o['userName'] as String,
        totalWeight: (o['totalWeight'] as num).toDouble(),
      );
      final linesRaw = await api.fetchOrderDetails(brief.id);
      _lines = linesRaw.map((m){
        final p = Product.fromJson(m['product'] as Map<String,dynamic>);
        return OrderDetailLine(
            id: m['id'] as int,
            product: p,
            qtyInit: (m['qtyInit'] as num).toDouble(),
            sortWeight: (m['sortWeight'] as num).toDouble());
      }).toList();
      setState(()=> _order = brief);
      ref.read(currentOrderProvider.notifier).set(brief);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('查询失败：$e')));
    } finally {
      setState(()=> _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16, runSpacing: 12, children: [
            ElevatedButton.icon(onPressed: _scanOrder, icon: const Icon(Icons.qr_code_scanner), label: const Text('扫描订单')),
            ElevatedButton.icon(
                onPressed: _manualOrderInput,
                icon: const Icon(Icons.keyboard_alt_rounded),
                label: const Text('手动输入订单号')),
            ElevatedButton.icon(onPressed: _order==null? null: (){
              setState(()=> _order = null);
              _lines = const [];
              ref.read(currentOrderProvider.notifier).set(null);
            }, icon: const Icon(Icons.clear_all), label: const Text('清空')),
          ],
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
          if (_order!=null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('订单：${_order!.orderNumber}', style: K.bigText),
                  const SizedBox(height: 6),
                  Text('用户：${_order!.userName}', style: K.midText),
                ]),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: Card(
              child: Column(children: [
                const ListTile(title: Text('订单明细（可对照秤进行分拣）')),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: _lines.length,
                    separatorBuilder: (_, __)=> const Divider(height: 1),
                    itemBuilder: (_, i){
                      final ln = _lines[i];
                      return ListTile(
                        title: Text(ln.product.name, style: K.midText),
                        subtitle: Text('初始：${ln.qtyInit.toStringAsFixed(2)} ${ln.product.uom}'),
                        trailing: Text('分拣：${ln.sortWeight.toStringAsFixed(2)} ${ln.product.uom}', style: K.midText),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

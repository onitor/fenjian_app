import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/constants.dart';
import '../../services/api_client.dart';
import '../../state/app_state.dart';

class BindPage extends ConsumerStatefulWidget {
  const BindPage({super.key});
  @override
  ConsumerState<BindPage> createState() => _BindPageState();
}

class _BindPageState extends ConsumerState<BindPage> {
  bool _scanning = false;
  String? _lastCode;

  Future<void> _handleCode(String code) async {
    if (_scanning) return; // 防抖
    setState(() { _scanning = true; _lastCode = code; });
    final api = ref.read(apiProvider);
    try {
      await api.bindWorkerByQr(code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('绑定成功')));
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('绑定失败：$e')));
    } finally {
      if (mounted) setState(() { _scanning = false; });
    }
  }

  void _manualInput() async {
    final textCtrl = TextEditingController();
    final code = await showDialog<String>(context: context, builder: (ctx) {
      return AlertDialog(
        title: const Text('手动输入绑定码'),
        content: TextField(controller: textCtrl, decoration: const InputDecoration(hintText: '输入员工或设备二维码内容'), autofocus: true),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: ()=> Navigator.pop(ctx, textCtrl.text.trim()), child: const Text('确定')),
        ],
      );
    });
    if (code != null && code.isNotEmpty) _handleCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码绑定设备/分拣员')),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Text('请将员工卡或设备二维码对准摄像头，完成一次性绑定。', style: K.midText),
          ),
          Expanded(
            child: Card(
              margin: const EdgeInsets.all(12),
              child: Stack(
                children: [
                  if (!_scanning)
                    MobileScanner(onDetect: (capture){
                      final barcodes = capture.barcodes;
                      if (barcodes.isEmpty) return;
                      final raw = barcodes.first.rawValue;
                      if (raw != null && raw != _lastCode) _handleCode(raw);
                    }),
                  if (_scanning)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.icon(onPressed: _manualInput, icon: const Icon(Icons.keyboard), label: const Text('手动输入')),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

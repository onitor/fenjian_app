import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/api_client.dart';
import '../../state/app_state.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _baseCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final api = ref.read(apiProvider);
    _baseCtrl.text = api.baseUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        const ListTile(title: Text('后端地址设置')), const SizedBox(height: 6),
        TextField(controller: _baseCtrl, decoration: const InputDecoration(labelText: 'API Base URL', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton(onPressed: () async { await ref.read(apiProvider).setBaseUrl(_baseCtrl.text.trim()); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存'))); }, child: const Text('保存')),
        const Divider(height: 32),
        const ListTile(title: Text('分拣员/设备')),
        Consumer(builder: (context, ref, _) {
          final workerAsync = ref.watch(boundWorkerProvider);
          return workerAsync.when(
            data: (w)=> Row(children: [
              Expanded(child: Text(w==null? '未绑定' : '已绑定：${w.name}(${w.id})')),
              FilledButton(onPressed: () async { await ref.read(apiProvider).unbindWorker(); if (!mounted) return; ref.refresh(boundWorkerProvider); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消绑定'))); }, child: const Text('取消绑定')),
            ]),
            loading: ()=> const LinearProgressIndicator(minHeight: 2),
            error: (e,_)=> Text('加载失败：$e'),
          );
        }),
        const SizedBox(height: 20),
        const Text('秤连接：当前使用模拟秤（可在后续迭代接入USB/蓝牙）。'),
      ]),
    );
  }
}
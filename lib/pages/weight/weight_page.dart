import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../state/app_state.dart';
import '../../services/scale/scale_service.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';

class WeightPage extends ConsumerStatefulWidget {
  const WeightPage({super.key});
  @override
  ConsumerState<WeightPage> createState() => _WeightPageState();
}


class _WeightPageState extends ConsumerState<WeightPage> {
  late final ScaleService _scale;
  StreamSubscription<double>? _sub;
  double _w = 0;
  VideoPlayerController? _v;
  final _videoUrlCtrl = TextEditingController();
  double _acc() => _scale.getAccumulatedWeight(1);

  @override
  void initState() {
    super.initState();
    _scale = ref.read(scaleProvider);
    _sub = _scale.watchCurrentWeight(1).listen((v)=> setState(()=> _w = v));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _v?.dispose();
    super.dispose();
  }

  Future<void> _pickLocalVideo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.single.path == null) return;
    await _playVideo(res.files.single.path!);
  }

  Future<void> _playVideo(String source) async {
    try {
      _v?.dispose();
      if (source.startsWith('http')) {
        _v = VideoPlayerController.networkUrl(Uri.parse(source));
      } else {
        _v = VideoPlayerController.file(File(source));
      }
      await _v!.initialize();
      _v!
        ..setLooping(true)
        ..setVolume(0.0); // 默认静音，环境更安静
      if (mounted) setState((){});
      await _v!.play();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('视频加载失败：$e')));
    }
  }

  Future<void> _submitTotal() async {
    final order = ref.read(currentOrderProvider);
    if (order == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先在“分拣”页面选择订单')));
      return;
    }

    final locs = await ref.read(locationsProvider.future);
    if (!mounted || locs.isEmpty) return;
    int selId = locs.first.locationId;

    await showDialog(context: context, builder: (ctx){
      return AlertDialog(
        title: const Text('选择目标库位'),
        content: DropdownButtonFormField<int>(
          value: selId, isExpanded: true,
          items: [for (final l in locs) DropdownMenuItem(value: l.locationId, child: Text(l.locationName))],
          onChanged: (v)=> selId = v ?? selId,
        ),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: ()=> Navigator.pop(ctx), child: const Text('确定')),
        ],
      );
    });

    final total = _w + _acc();
    final api = ref.read(apiProvider);
    try {
      await api.submitTotalWeight(
        orderId: order.id,
        weight: double.parse(total.toStringAsFixed(2)),
        locationId: selId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('总重量已提交')));
    } catch (e) {
      if (!mounted) return;
      // 按“成功已落地但后续失败不误导”的原则，这里不覆盖已成功操作（你的上一条问题里我们已讨论过）
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('提交失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final acc = _acc();
    final total = _w + acc;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16).copyWith(
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部：一个秤
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('称重台', style: K.bigText),
                  const SizedBox(height: 8),
                  Text('当前重量：${_w.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('累计重量：${acc.toStringAsFixed(2)} kg', style: K.midText),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    ElevatedButton(onPressed: ()=> setState(()=> _scale.accumulate(1, _w)), child: const Text('累计')),
                    ElevatedButton(onPressed: ()=> setState(()=> _scale.tare(1)), child: const Text('去皮')),
                    ElevatedButton(onPressed: ()=> setState(()=> _scale.clear(1)), child: const Text('清零累计')),
                    FilledButton(onPressed: ()=> _scale.sendWeight(1, _w), child: const Text('发送')),
                  ]),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // 总重量 + 提交
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('总重量：${total.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  FilledButton.icon(onPressed: _submitTotal, icon: const Icon(Icons.send), label: const Text('发送总重量')),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // 订单详情视频（URL 或 本地）
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('订单详情视频', style: K.bigText),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _videoUrlCtrl,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '输入视频URL，例如：https://.../xxx.mp4',
                          labelText: '视频URL',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(onPressed: ()=> _playVideo(_videoUrlCtrl.text.trim()), child: const Text('播放URL')),
                    const SizedBox(width: 12),
                    OutlinedButton(onPressed: _pickLocalVideo, child: const Text('选择本地文件')),
                  ]),
                  const SizedBox(height: 12),
                  AspectRatio(
                    aspectRatio: _v?.value.isInitialized == true ? _v!.value.aspectRatio : 16/9,
                    child: _v?.value.isInitialized == true
                        ? VideoPlayer(_v!)
                        : const DecoratedBox(
                      decoration: BoxDecoration(color: Color(0x11000000)),
                      child: Center(child: Text('未选择视频')),
                    ),
                  ),
                  if (_v?.value.isInitialized == true) ...[
                    const SizedBox(height: 8),
                    Row(children: [
                      FilledButton(onPressed: ()=> _v!.play(), child: const Text('播放')),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: ()=> _v!.pause(), child: const Text('暂停')),
                    ]),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../settings/settings_page.dart';
import '../sort/sort_page.dart';
import '../weight/weight_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _index = 0; // 0:分拣 1:称重 2:设置

  @override
  Widget build(BuildContext context) {
    final workerAsync = ref.watch(boundWorkerProvider);
    return Scaffold(
      appBar: AppBar(
        title: workerAsync.when(
          data: (w) => Text(w==null? '未绑定' : '当前分拣员：${w.name}'),
          loading: ()=> const Text('加载中...'),
          error: (e,_)=> const Text('分拣员错误'),
        ),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          SortPage(),
          WeightPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i)=> setState(()=> _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: '分拣'),
          NavigationDestination(icon: Icon(Icons.monitor_weight), label: '称重'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}

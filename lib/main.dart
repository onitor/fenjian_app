
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'services/api_client.dart';
import 'state/app_state.dart';
import 'pages/bind/bind_page.dart';
import 'pages/home/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await ApiClient.create();
  runApp(ProviderScope(overrides: [apiProvider.overrideWithValue(api)], child: const App()));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      builder: (context, child) {
        // 全局把文字放大 1.1 倍（安全，不触发断言）
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: const TextScaler.linear(1.1)),
          child: child!,
        );
      },
      title: K.appTitle,
      initialRoute: '/',
      routes: {
        '/': (ctx)=> const _Gate(),
        '/bind': (ctx)=> const BindPage(),
        '/home': (ctx)=> const HomePage(),
      },
    );
  }
}

class _Gate extends ConsumerWidget {
  const _Gate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 获取绑定的分拣员信息
    final workerAsync = ref.watch(boundWorkerProvider);

    // 使用 `workerAsync.when` 来根据异步结果显示不同的页面
    return workerAsync.when(
      data: (worker) {
        // 使用 WidgetsBinding 来确保在 widget 构建完成后执行导航操作
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.of(context).pushReplacementNamed(worker == null ? '/bind' : '/home');
        });
        // 由于导航操作在构建后执行，因此这里可以返回一个加载中的界面
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
      loading: () {
        // 加载中时显示一个加载指示器
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
      error: (error, stack) {
        // 出现错误时显示错误信息
        return Scaffold(body: Center(child: Text('错误：$error')));
      },
    );
  }
}




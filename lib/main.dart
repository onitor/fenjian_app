import 'package:fenjian_app/pages/home/home_page.dart';
import 'package:fenjian_app/pages/sort/orders_list_page.dart';
import 'package:fenjian_app/pages/sort/sort_page.dart';
import 'package:fenjian_app/services/api_client.dart';
import 'package:fenjian_app/services/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get/get.dart';
import 'dio/mqtt_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final api = await ApiClient.create();

  runApp(
    ProviderScope(
      overrides: [apiProvider.overrideWithValue(api)],
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      title: '分拣App',
      // 关键：在任何页面 build 前注册依赖
      initialBinding: BindingsBuilder(() {
        if (!Get.isRegistered<MqttService>()) {
          Get.put<MqttService>(MqttService(logEnabled: true), permanent: true);
        }
        if (!Get.isRegistered<EquipmentController>()) {
          Get.put<EquipmentController>(EquipmentController(), permanent: true);
        }
        // 其它用到的控制器也一起在这儿注册（可懒加载）
        Get.lazyPut<QrCodeController>(() => QrCodeController(), fenix: true);
      }),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: const TextScaler.linear(1.1)),
          child: child!,
        );
      },
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const HomeScanEntryPage()),
        GetPage(name: '/orders', page: () => const OrdersListPage()),
        GetPage(name: '/work/:orderId', page: () => const SortingWorkPage()),
      ],
    );
  }
}
// import 'package:fenjian_app/pages/home/home_page.dart';
// import 'package:fenjian_app/state/app_state.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:get/get.dart';
// import 'package:get_storage/get_storage.dart';
//
// import 'package:fenjian_app/services/api_client.dart';
// import 'package:fenjian_app/services/controller.dart';
// import 'dio/mqtt_service.dart';
//
// import 'package:fenjian_app/pages/sort/orders_list_page.dart';
// import 'package:fenjian_app/pages/sort/sort_page.dart';
//
// const String DEBUG_ORDER_ID = '116'; // ← 改成你后端存在的订单ID
//
// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // ✅ GetStorage 必须先 init；Web 下对应 localStorage
//   await GetStorage.init();
//
//   final api = await ApiClient.create();
//
//   runApp(
//     ProviderScope(
//       overrides: [apiProvider.overrideWithValue(api)],
//       child: const App(),
//     ),
//   );
// }
//
// class App extends StatelessWidget {
//   const App({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return GetMaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: '分拣App',
//
//       // ✅ 在任何页面 build 前注册依赖
//       initialBinding: BindingsBuilder(() {
//         if (!Get.isRegistered<MqttService>()) {
//           Get.put<MqttService>(MqttService(logEnabled: true), permanent: true);
//         }
//         if (!Get.isRegistered<EquipmentController>()) {
//           Get.put<EquipmentController>(EquipmentController(), permanent: true);
//         }
//         // 其它控制器
//         Get.lazyPut<QrCodeController>(() => QrCodeController(), fenix: true);
//       }),
//
//       // ✅ 直接进详情页：给出真实的ID
//       initialRoute: '/work/$DEBUG_ORDER_ID',
//
//       builder: (context, child) {
//         final mq = MediaQuery.of(context);
//         return MediaQuery(
//           data: mq.copyWith(textScaler: const TextScaler.linear(1.1)),
//           child: child!,
//         );
//       },
//
//       getPages: [
//         GetPage(name: '/', page: () => const HomeScanEntryPage()),
//         GetPage(name: '/orders', page: () => const OrdersListPage()),
//         GetPage(name: '/work/:orderId', page: () => const SortingWorkPage()),
//       ],
//     );
//   }
// }

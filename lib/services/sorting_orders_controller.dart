// lib/get/sorting_orders_controller.dart
import 'package:get/get.dart';
import '../models/models.dart';
import '../models/sorting_models.dart';
import 'api.dart';
import 'controller.dart'; // EquipmentController

class SortingOrdersController extends GetxController {
  final api = SortingApi();
  final RxBool loading = false.obs;
  final RxList<TmsPickOrder> orders = <TmsPickOrder>[].obs;
  final Rx<PickState> stateFilter = PickState.all.obs;

  Future<void> fetch({required String pickUserId}) async {
    loading.value = true;
    try {
      final eqId = Get.find<EquipmentController>().equipmentId ?? '';
      final list = await api.getAllPickOrders(
        pickUserId: pickUserId,
        equipmentId: eqId,
        pickState: pickStateParam(stateFilter.value),
      );
      orders.assignAll(list.map(TmsPickOrder.fromJson).toList());
    } finally {
      loading.value = false;
    }
  }
}

class EquipmentInfo {
  final String eqId;
  final String equipmentNumber;
  final String name;
  late final String? userRole;
  final String address;
  final double capacity;
  final double useCapacity;
  final String description;
  final String location;
  final String operatePhone;   // 管理员电话（优先）
  final String complainPhone;  // 投诉电话
  final String equipmentPwd;   // 管理员入口密码
  final String mobilePhone;
  final String state;
  final double totalAmount;
  final String capacityState;
  final String currentCapacityState;
  final String equipmentUserId;


  EquipmentInfo({
    required this.eqId,
    required this.equipmentNumber,
    required this.name,
    required this.userRole,
    required this.address,
    required this.capacity,
    required this.useCapacity,
    required this.description,
    required this.location,
    required this.mobilePhone,
    required this.operatePhone,
    required this.complainPhone,
    required this.equipmentPwd,
    required this.state,
    required this.totalAmount,
    required this.capacityState,
    required this.currentCapacityState,
    required this.equipmentUserId,
  });

  factory EquipmentInfo.fromJson(Map<String, dynamic> json) {

    return EquipmentInfo(
      eqId: json['eqId']?.toString() ?? '',
      equipmentNumber: json['equipmentNumber']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      userRole: json['userRole']?.toString()??'',
      address: json['address']?.toString() ?? '',
      capacity: _toDouble(json['capacity']),
      useCapacity: _toDouble(json['useCapacity']),
      description: json['description']?.toString() ?? '',
      location: json['location']?.toString() ?? '',
      mobilePhone: json['mobilePhone']?.toString() ?? '',
      operatePhone: json['operatePhone']?.toString() ?? '',
      complainPhone: json['complainPhone']?.toString() ?? '',
      equipmentPwd: json['equipmentPwd']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      totalAmount: _toDouble(json['totalAmount']),
      capacityState: json['capacityState']?.toString() ?? '',
      currentCapacityState: json['currentCapacityState']?.toString() ?? '',
      equipmentUserId: json['equipmentUserId']?.toString() ?? '',
    );
  }

  static double _toDouble(dynamic value) {
    try {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
    } catch (_) {}
    return 0.0;
  }
}

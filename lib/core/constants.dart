import 'package:flutter/material.dart';

class K {
  static const defaultApiBase = 'http://175.178.82.123:8070/';
  static const appTitle = '分拣作业';
  static const bigText = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
  static const midText = TextStyle(fontSize: 18, fontWeight: FontWeight.w600);
  static const lightText = TextStyle(fontSize: 16);
}
// lib/config/constants.dart
const String kUserRoleSorter = '5';

// 仅供“发送用”的占位主题（和后端对齐后替换）：
String topicSorterOnline(String eq) => 'recycle/$eq/sorter/online';  // 可选心跳/上线


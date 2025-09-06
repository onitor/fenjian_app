import 'package:flutter/material.dart';
import '../core/constants.dart';

class BigIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;
  const BigIconButton({super.key, required this.icon, required this.label, required this.onPressed, this.color});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 120,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 36),
        onPressed: onPressed,
        label: Text(label, style: K.bigText),
      ),
    );
  }
}

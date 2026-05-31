import 'package:flutter/material.dart';
import '../design/app_constants.dart';

class SquareButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;
  final Widget child;

  const SquareButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final style = ElevatedButton.styleFrom(
      backgroundColor: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusSM),
      ),
    );

    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingMD),
        child: child,
      ),
    );
  }
}

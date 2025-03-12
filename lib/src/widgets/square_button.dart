import 'package:flutter/material.dart';

class SquareButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Color? color;
  final Widget child;

  SquareButton(
      {super.key, required this.onPressed, required this.child, this.color});

  @override
  Widget build(BuildContext context) {
    ButtonStyle style = ElevatedButton.styleFrom(
        backgroundColor: this.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4.0),
        ));

    return ElevatedButton(
      onPressed: onPressed,
      child: Padding(
        child: child,
        padding: EdgeInsets.symmetric(vertical: 16),
      ),
      style: style,
    );
  }
}

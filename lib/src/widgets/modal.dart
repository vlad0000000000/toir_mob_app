import 'package:flutter/material.dart';

class Modal extends StatelessWidget {
  final Widget child;

  const Modal({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final height = mediaQuery.size.height * 0.9;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 10),
      height: height,
      child: Column(
        children: [
          SizedBox(
            height: 10,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                child: Icon(
                  Icons.close,
                  size: 32,
                ),
                onTap: () => Navigator.of(context).pop(),
              ),
              SizedBox(width: 20)
            ],
          ),
          SizedBox(
            height: 10,
          ),
          Expanded(child: child)
        ],
      ),
      margin: EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 5,
          )
        ],
      ),
    );
  }
}

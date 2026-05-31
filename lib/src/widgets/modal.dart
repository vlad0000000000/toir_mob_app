import 'package:flutter/material.dart';
import '../design/app_constants.dart';

class Modal extends StatelessWidget {
  final Widget child;

  const Modal({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final height = MediaQuery.of(context).size.height * 0.9;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingSM),
      height: height,
      margin: const EdgeInsets.all(AppConstants.spacingLG),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 5,
          )
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: AppConstants.spacingSM),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(Icons.close, size: 32),
              ),
              const SizedBox(width: AppConstants.spacingLG),
            ],
          ),
          const SizedBox(height: AppConstants.spacingSM),
          Expanded(child: child),
        ],
      ),
    );
  }
}

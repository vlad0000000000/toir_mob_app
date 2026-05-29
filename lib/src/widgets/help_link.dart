import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

/// Серая подчёркнутая ссылка "Помощь" → /knowledge_base.
/// Используется и на экране логина, и в AppBar главного экрана.
class HelpLink extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const HelpLink({super.key, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/knowledge_base'),
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/ix_user-manual.svg',
              width: 20,
              height: 20,
              colorFilter: ColorFilter.mode(
                Colors.grey.shade700,
                BlendMode.srcIn,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Помощь',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 16,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

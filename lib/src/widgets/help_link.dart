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
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push('/knowledge_base'),
      child: Padding(
        padding: padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/ix_user-manual.svg',
              width: 18,
              height: 18,
              colorFilter: ColorFilter.mode(cs.primary, BlendMode.srcIn),
            ),
            const SizedBox(width: 6),
            // В шапке главной под ссылку отведена фиксированная ширина
            // (`leadingWidth`), а подпись растёт с системным шрифтом: при
            // 150% она вылезала за край на несколько пикселей. Не хватает
            // места — подпись чуть ужимается; хватает — остаётся как есть.
            // На экране входа ширина не ограничена (`Positioned` без правого
            // края) — там `Flexible` ничего не ужимает.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Помощь',
                  maxLines: 1,
                  style: tt.labelLarge?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

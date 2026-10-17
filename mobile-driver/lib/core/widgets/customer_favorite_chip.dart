import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';

/// Badge « Client préféré » (DR-02/DR-03, maquettes 02, 12, 13) : affiché
/// uniquement quand le backend confirme une relation réelle
/// (customer_favorite_drivers) entre le créateur de la demande et ce
/// chauffeur -- jamais déduit côté app.
class CustomerFavoriteChip extends StatelessWidget {
  const CustomerFavoriteChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocale.t('Ce client vous a ajouté à ses chauffeurs préférés.'),
      child: Chip(
        avatar: const Icon(Icons.star_rounded, size: 16, color: VeyraColors.warning),
        backgroundColor: VeyraColors.warningBackground,
        side: BorderSide.none,
        label: Text(
          AppLocale.t('Client préféré'),
          style: const TextStyle(color: VeyraColors.warning, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

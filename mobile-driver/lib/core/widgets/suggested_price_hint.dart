import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';
import '../formatters/money_formatter.dart';

/// « Prix conseillé : 59 € – 74 € » (DEC-18, maquettes 12–14), en prix net
/// chauffeur. Purement indicatif : rien n'est affiché si la grille n'est
/// pas renseignée pour la catégorie ou si l'itinéraire est indisponible.
class SuggestedPriceHint extends StatefulWidget {
  final Future<Map<String, dynamic>> Function() load;

  const SuggestedPriceHint({required this.load, super.key});

  static String label(Map<String, dynamic> s) {
    String whole(dynamic minor) => VeyraMoneyFormatter.fromMinor(minor).replaceAll(',00', '');
    return '${AppLocale.t('Prix conseillé (net)')} : ${whole(s['netLowMinor'])} – ${whole(s['netHighMinor'])}';
  }

  @override
  State<SuggestedPriceHint> createState() => _SuggestedPriceHintState();
}

class _SuggestedPriceHintState extends State<SuggestedPriceHint> {
  late final Future<Map<String, dynamic>> future = widget.load();

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, s) {
          final data = s.data;
          if (s.hasError || data == null || data['available'] != true) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.info_outline, size: 16, color: VeyraColors.textSecondary),
              const SizedBox(width: 6),
              Flexible(child: Text(SuggestedPriceHint.label(data), style: const TextStyle(color: VeyraColors.textSecondary))),
            ]),
          );
        },
      );
}

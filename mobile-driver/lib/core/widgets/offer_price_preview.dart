import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';
import '../formatters/money_formatter.dart';

/// Aperçu DR-04 (DEC-01 méthode A, maquette 14) : le chauffeur saisit son
/// prix net, l'app affiche le prix payé par le client et la commission
/// VEYRA, calculés par le serveur avec la règle qui sera figée sur l'offre.
/// Le montant n'est jamais calculé côté app.
class OfferPricePreview extends StatefulWidget {
  final String amountText;
  final Future<Map<String, dynamic>> Function(int amountMinor) fetchQuote;

  const OfferPricePreview({required this.amountText, required this.fetchQuote, super.key});

  /// Parses "48", "48,5" or "48.50" into minor units; null when invalid.
  static int? parseMinor(String text) {
    final euros = double.tryParse(text.trim().replaceAll(',', '.'));
    if (euros == null || !euros.isFinite || euros <= 0) return null;
    return (euros * 100).round();
  }

  @override
  State<OfferPricePreview> createState() => _OfferPricePreviewState();
}

class _OfferPricePreviewState extends State<OfferPricePreview> {
  Timer? _debounce;
  Map<String, dynamic>? _quote;
  int? _quotedMinor;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _schedule(initial: true);
  }

  @override
  void didUpdateWidget(covariant OfferPricePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amountText != widget.amountText) _schedule();
  }

  void _schedule({bool initial = false}) {
    _debounce?.cancel();
    final minor = OfferPricePreview.parseMinor(widget.amountText);
    if (minor == null) {
      // setState is not allowed during initState; state is already empty then.
      if (!initial) setState(() { _quote = null; _quotedMinor = null; _failed = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final q = await widget.fetchQuote(minor);
        if (!mounted) return;
        setState(() { _quote = q; _quotedMinor = minor; _failed = false; });
      } catch (_) {
        if (mounted) setState(() { _quote = null; _failed = true; });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(AppLocale.t('Aperçu du prix client indisponible.'), style: const TextStyle(color: VeyraColors.textSecondary)),
      );
    }
    final q = _quote;
    if (q == null || _quotedMinor != OfferPricePreview.parseMinor(widget.amountText)) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: VeyraColors.infoBackground, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(AppLocale.t('Prix total pour le client'), style: const TextStyle(color: VeyraColors.textSecondary)),
        const SizedBox(height: 2),
        Text(VeyraMoneyFormatter.fromMinor(q['customerTotalMinor']),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: VeyraColors.primaryDark)),
        const SizedBox(height: 4),
        Text('${AppLocale.t('Commission VEYRA incluse')} : ${VeyraMoneyFormatter.fromMinor(q['commissionMinor'])}',
            style: const TextStyle(color: VeyraColors.textSecondary)),
        Text('${AppLocale.t('Vous recevez')} : ${VeyraMoneyFormatter.fromMinor(q['driverNetMinor'])}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

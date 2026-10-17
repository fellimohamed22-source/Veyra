import 'package:flutter/material.dart';
import '../../app_locale.dart';
import '../formatters/error_messages.dart';
import 'state_views.dart';

/// « Mes moyens de paiement » (CL-17, maquettes 03 et 15 ; DEC-04) : cartes
/// enregistrées lors des réservations précédentes. Seuls la marque, les 4
/// derniers chiffres et l'échéance sont affichés : le numéro complet reste
/// chez Stripe. Une carte est ajoutée en payant une réservation.
class SavedCardsScreen extends StatefulWidget {
  final Future<List<dynamic>> Function() load;
  final Future<void> Function(String paymentMethodId) remove;

  const SavedCardsScreen({required this.load, required this.remove, super.key});

  @override
  State<SavedCardsScreen> createState() => _SavedCardsScreenState();
}

class _SavedCardsScreenState extends State<SavedCardsScreen> {
  late Future<List<dynamic>> cards = widget.load();

  // Block body: a setState callback must not return the Future it assigns.
  void reload() => setState(() { cards = widget.load(); });

  Future<void> confirmRemove(Map card) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocale.t('Supprimer cette carte ?')),
        content: Text('${card['brand'] ?? ''} •••• ${card['last4'] ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocale.t('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppLocale.t('Supprimer'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.remove(card['id'].toString());
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(VeyraErrorMessages.forException(e))));
    }
  }

  static String expiry(Map card) {
    final m = card['expMonth'], y = card['expYear'];
    if (m == null || y == null) return '';
    return '${m.toString().padLeft(2, '0')}/${y.toString().substring(y.toString().length - 2)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppLocale.t('Mes moyens de paiement'))),
        body: FutureBuilder<List<dynamic>>(
          future: cards,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) return VeyraErrorView(customMessage: VeyraErrorMessages.forException(s.error!), onRetry: reload);
            final list = (s.data ?? []).whereType<Map>().toList();
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text(AppLocale.t('Aucune carte enregistrée. Votre carte sera proposée à l\'enregistrement lors de votre prochain paiement.')),
              );
            }
            return ListView(padding: const EdgeInsets.all(16), children: [
              for (final card in list)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.credit_card),
                    title: Text('${(card['brand'] ?? '').toString().toUpperCase()} •••• ${card['last4'] ?? ''}'),
                    subtitle: Text('${AppLocale.t('Expire fin')} ${expiry(card)}'),
                    trailing: IconButton(
                      tooltip: AppLocale.t('Supprimer'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => confirmRemove(card),
                    ),
                  ),
                ),
            ]);
          },
        ),
      );
}

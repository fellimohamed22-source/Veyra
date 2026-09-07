/// Tous les montants viennent du serveur en unités mineures (centimes),
/// jamais calculés côté Flutter (CLAUDE_GUARDRAILS.md — "Flutter ne
/// devient jamais la source de vérité métier"). Ce formatter fait
/// uniquement de l'AFFICHAGE, aucun calcul financier.
class VeyraMoneyFormatter {
  VeyraMoneyFormatter._();

  /// [minor] en centimes, ex: 19500 -> "195,00 €". Retourne un texte
  /// neutre plutôt qu'un montant halluciné si la valeur serveur est
  /// absente.
  static String fromMinor(dynamic minor, {String currency = 'EUR'}) {
    if (minor == null) return '—';
    final n = minor is num ? minor : num.tryParse(minor.toString());
    if (n == null) return '—';
    final euros = n / 100;
    final symbol = currency == 'EUR' ? '€' : currency;
    final formatted = euros.toStringAsFixed(2).replaceAll('.', ',');
    return '$formatted $symbol';
  }
}

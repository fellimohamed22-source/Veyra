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

  /// [meters] -> "12,4 km" (format cible imposé, section 41 du prompt
  /// maître). Sous 1 km, affiche en mètres pour rester lisible.
  static String distance(dynamic meters) {
    if (meters == null) return '—';
    final n = meters is num ? meters : num.tryParse(meters.toString());
    if (n == null) return '—';
    if (n < 1000) return '${n.round()} m';
    final km = (n / 1000).toStringAsFixed(1).replaceAll('.', ',');
    return '$km km';
  }

  /// [seconds] -> "24 min" (format cible imposé, section 41).
  static String duration(dynamic seconds) {
    if (seconds == null) return '—';
    final n = seconds is num ? seconds : num.tryParse(seconds.toString());
    if (n == null) return '—';
    final minutes = (n / 60).ceil();
    return '$minutes min';
  }
}

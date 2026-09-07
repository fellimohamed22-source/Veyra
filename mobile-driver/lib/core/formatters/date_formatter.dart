import '../../app_locale.dart';

/// Aucune date brute ISO ne doit jamais apparaître à l'écran
/// (SOURCE_OF_TRUTH_MVP.md, section formatage). Toutes les dates
/// affichées doivent passer par ce formatter.
///
/// Pas de dépendance `intl` ajoutée : elle n'était pas déclarée dans
/// pubspec.yaml avant ce lot, et une nouvelle dépendance ne peut pas être
/// vérifiée dans cet environnement (pas d'accès réseau à pub.dev). Les
/// abréviations FR/EN sont donc écrites à la main ci-dessous.
class VeyraDateFormatter {
  VeyraDateFormatter._();

  static const _weekdaysFr = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
  static const _monthsFr = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];
  static const _weekdaysEn = ['Mon.', 'Tue.', 'Wed.', 'Thu.', 'Fri.', 'Sat.', 'Sun.'];
  static const _monthsEn = [
    'Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'Jun.',
    'Jul.', 'Aug.', 'Sep.', 'Oct.', 'Nov.', 'Dec.'
  ];

  static bool get _isEnglish => AppLocale.code.value == 'en';

  /// Tente de parser une date ISO brute (venant du backend). Retourne
  /// null si absente/invalide plutôt que de laisser passer une chaîne
  /// brute non formatée.
  static DateTime? _parse(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  static String _time(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Ex FR : "Mer. 23 sept. • 21:36" — Ex EN : "Wed. Sep. 23 • 21:36"
  static String dateTime(dynamic raw) {
    final dt = _parse(raw);
    if (dt == null) return '—';
    final weekday = (_isEnglish ? _weekdaysEn : _weekdaysFr)[dt.weekday - 1];
    final month = (_isEnglish ? _monthsEn : _monthsFr)[dt.month - 1];
    return _isEnglish
        ? '$weekday $month ${dt.day} • ${_time(dt)}'
        : '$weekday ${dt.day} $month • ${_time(dt)}';
  }

  /// Ex : "23 sept." — sans heure, pour les listes compactes.
  static String dateOnly(dynamic raw) {
    final dt = _parse(raw);
    if (dt == null) return '—';
    final month = (_isEnglish ? _monthsEn : _monthsFr)[dt.month - 1];
    return _isEnglish ? '$month ${dt.day}' : '${dt.day} $month';
  }

  /// Ex : "21:36" seul.
  static String timeOnly(dynamic raw) {
    final dt = _parse(raw);
    if (dt == null) return '—';
    return _time(dt);
  }

  /// Relatif court pour les listes ("Aujourd'hui", "Demain", ou date).
  static String relativeDay(dynamic raw) {
    final dt = _parse(raw);
    if (dt == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return _isEnglish ? 'Today • ${_time(dt)}' : "Aujourd'hui • ${_time(dt)}";
    if (diff == 1) return _isEnglish ? 'Tomorrow • ${_time(dt)}' : 'Demain • ${_time(dt)}';
    return dateTime(raw);
  }
}

import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../app_locale.dart';
import '../core/formatters/money_formatter.dart';
import '../core/widgets/notifications_view.dart';
import '../core/widgets/veyra_ui.dart';

String _t(String s) => AppLocale.t(s);

/// « Aujourd'hui · 15:30 », « Demain · 09:00 », « Sam. 18 oct. · 08:30 »
/// (planches 02, 12, 13).
String driverWhen(dynamic raw, {DateTime? now}) {
  final d = DateTime.tryParse((raw ?? '').toString())?.toLocal();
  if (d == null) return '';
  final today = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(DateTime(today.year, today.month, today.day)).inDays;
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  if (diff == 0) return '${_t('Aujourd’hui')} · $hm';
  if (diff == 1) return '${_t('Demain')} · $hm';
  const days = ['Lun.', 'Mar.', 'Mer.', 'Jeu.', 'Ven.', 'Sam.', 'Dim.'];
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${_t(days[d.weekday - 1])} ${d.day} ${_t(months[d.month - 1])} · $hm';
}

/// « Dans 2 h », « Dans 25 min », « Dans 3 j » before a ride.
String driverStartsIn(dynamic raw, {DateTime? now}) {
  final d = DateTime.tryParse((raw ?? '').toString())?.toLocal();
  if (d == null) return '';
  final left = d.difference(now ?? DateTime.now());
  if (left.isNegative) return _t('Maintenant');
  if (left.inDays >= 1) return '${_t('Dans')} ${left.inDays} ${_t('j')}';
  if (left.inHours >= 1) return '${_t('Dans')} ${left.inHours} h';
  return '${_t('Dans')} ${left.inMinutes} min';
}

/// En-tête des écrans chauffeur : mot-symbole VEYRA centré, cloche.
class DriverTopBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onNotifications;
  final int unread;
  final bool back;
  const DriverTopBar({this.onNotifications, this.unread = 0, this.back = false, super.key});
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Stack(alignment: Alignment.center, children: [
            const VeyraWordmark(),
            if (back)
              Positioned(
                left: 4,
                child: IconButton(
                  tooltip: _t('Retour'),
                  icon: const Icon(Icons.chevron_left, size: 30, color: VeyraColors.textPrimary),
                  onPressed: () => Navigator.maybePop(context),
                ),
              ),
            if (onNotifications != null)
              Positioned(
                right: 4,
                child: IconButton(
                  tooltip: _t('Notifications'),
                  onPressed: onNotifications,
                  // Board 16 P1: unread count on the bell.
                  icon: ValueListenableBuilder<int>(
                    valueListenable: veyraUnreadNotifications,
                    builder: (context, count, _) {
                      final n = unread > 0 ? unread : count;
                      return Badge(
                        isLabelVisible: n > 0,
                        label: Text(n > 9 ? '9+' : '$n'),
                        child: const Icon(Icons.notifications_none_rounded, size: 28, color: VeyraColors.textPrimary),
                      );
                    },
                  ),
                ),
              ),
          ]),
        ),
      );
}

/// Pastille d'état arrondie (« Client préféré », « En attente »…).
class DriverPill extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  final IconData? icon;
  const DriverPill(this.text, {required this.fg, required this.bg, this.icon, super.key});
  const DriverPill.favorite({super.key})
      : text = 'Client préféré',
        fg = const Color(0xFF9A5B00),
        bg = const Color(0xFFFFF1D6),
        icon = Icons.verified_user;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(VeyraRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Flexible(child: Text(_t(text), style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
      );
}

/// Départ (point bleu) et destination (épingle rouge), une ligne chacun.
class DriverMiniRoute extends StatelessWidget {
  final String pickup;
  final String dropoff;
  const DriverMiniRoute(this.pickup, this.dropoff, {super.key});
  Widget _line(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
        ]),
      );
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _line(Icons.location_on, VeyraColors.accent, pickup),
        _line(Icons.location_on, VeyraColors.pinRed, dropoff),
      ]);
}

/// « 3 passagers · 2 bagages ».
class DriverPaxBags extends StatelessWidget {
  final dynamic passengers;
  final dynamic baggage;
  final bool labels;
  const DriverPaxBags(this.passengers, this.baggage, {this.labels = true, super.key});
  @override
  Widget build(BuildContext context) {
    final p = (passengers as num?)?.toInt() ?? 1;
    final b = (baggage as num?)?.toInt() ?? 0;
    String label(int n, String one, String many) => labels ? '$n ${n > 1 ? _t(many) : _t(one)}' : '$n';
    return Wrap(spacing: 16, runSpacing: 4, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.person_outline, size: 18, color: VeyraColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(child: Text(label(p, 'passager', 'passagers'), style: const TextStyle(color: VeyraColors.textSecondary))),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.luggage_outlined, size: 18, color: VeyraColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(child: Text(label(b, 'bagage', 'bagages'), style: const TextStyle(color: VeyraColors.textSecondary))),
      ]),
    ]);
  }
}

/// Carte blanche à ombre douce.
class DriverCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const DriverCard({required this.child, this.onTap, this.padding = const EdgeInsets.all(16), super.key});
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(VeyraRadius.card),
          boxShadow: VeyraShadows.card,
          border: Border.all(color: VeyraColors.border.withValues(alpha: .6)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(borderRadius: BorderRadius.circular(VeyraRadius.card), onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      );
}

/// Titre de section avec lien (« Prochaine course · Voir tout »).
class DriverSectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const DriverSectionTitle(this.title, {this.action, this.onAction, super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Row(children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          if (action != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!, style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600)),
            ),
        ]),
      );
}

/// Carte « demande disponible » (planche 13 P2).
class DriverRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onTap;
  final Widget? footer;
  const DriverRequestCard({required this.request, required this.onTap, this.footer, super.key});
  @override
  Widget build(BuildContext context) {
    final x = request;
    final best = x['best_other_offer_minor'];
    final own = x['own_offer_amount_minor'] ?? x['ownOfferAmountMinor'];
    return Semantics(
      button: true,
      label: '${driverWhen(x['scheduled_at'])}, ${x['pickup_address'] ?? ''} → ${x['dropoff_address'] ?? ''}',
      child: DriverCard(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
            Text(driverWhen(x['scheduled_at']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (x['customer_favorite'] == true) const DriverPill.favorite(),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DriverMiniRoute((x['pickup_address'] ?? '').toString(), (x['dropoff_address'] ?? '').toString())),
            const Icon(Icons.chevron_right, color: VeyraColors.textSecondary),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DriverPaxBags(x['passenger_count'], x['baggage_count'], labels: false),
              if (x['category_name'] != null) ...[
                const SizedBox(height: 6),
                Text(x['category_name'].toString(), style: const TextStyle(color: VeyraColors.accent, fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ])),
            // Flexible: shares the width with the route details instead of
            // squeezing them with enlarged text.
            if (best != null)
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(_t('Offre la plus basse'), textAlign: TextAlign.end, style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 12)),
                  Text(VeyraMoneyFormatter.fromMinor(best), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ]),
              ),
            const SizedBox(width: 10),
            const VeyraVehicleThumb(width: 72),
          ]),
          if (own != null) ...[
            const SizedBox(height: 10),
            VeyraBanner(tone: VeyraTone.success, text: '${_t('Votre offre active')} : ${VeyraMoneyFormatter.fromMinor(own)}'),
          ],
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../api.dart';
import '../app/theme.dart';
import '../app_locale.dart';
import '../core/formatters/error_messages.dart';
import '../core/widgets/state_views.dart';
import '../core/widgets/notifications_view.dart';
import 'driver_ui.dart';

String _t(String s) => AppLocale.t(s);

/// Accueil chauffeur (planches 02 / 12 / 13 P1, DR-01) : bouton
/// « Disponible », compteurs, prochaine course et demandes récentes.
class DriverHomeScreen extends StatefulWidget {
  final Api api;
  final ValueNotifier<int>? refresh;
  final void Function(String route) go;
  final void Function(String route) push;
  const DriverHomeScreen({required this.api, required this.go, required this.push, this.refresh, super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late Future<Map<String, dynamic>> dashboard;
  late Future<List<dynamic>> recent;
  bool? accepting;
  bool switching = false;
  String? switchError;

  @override
  void initState() {
    super.initState();
    load();
    widget.refresh?.addListener(reload);
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(reload);
    super.dispose();
  }

  void load() {
    dashboard = widget.api.dashboard().then((d) {
      if (mounted && !switching) setState(() => accepting = d['acceptingRequests'] != false);
      return d;
    });
    widget.api.unreadNotifications().then((n) => veyraUnreadNotifications.value = n).catchError((_) => veyraUnreadNotifications.value);
    recent = widget.api.opportunities(sort: 'newest');
    recent.ignore();
  }

  void reload() => setState(load);

  Future<void> toggle(bool value) async {
    if (switching) return;
    setState(() { switching = true; accepting = value; switchError = null; });
    try {
      final saved = await widget.api.setAvailability(value);
      if (mounted) setState(() { accepting = saved; load(); });
    } catch (e) {
      if (mounted) setState(() { accepting = !value; switchError = VeyraErrorMessages.forException(e); });
    } finally {
      if (mounted) setState(() => switching = false);
    }
  }

  Widget availabilityCard() {
    final on = accepting ?? true;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: on ? VeyraColors.successBackground : VeyraColors.neutralBackground, borderRadius: BorderRadius.circular(VeyraRadius.card)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(on ? Icons.check_circle : Icons.pause_circle_filled, color: on ? VeyraColors.success : VeyraColors.neutral, size: 28),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(on ? _t('Disponible pour recevoir des demandes') : _t('Hors ligne'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            on
                ? _t('Vous recevez les nouvelles demandes de trajet. Vous pouvez désactiver ce statut à tout moment.')
                : _t('Vous ne recevez plus de nouvelles demandes, mais vos courses restent accessibles.'),
            style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 13),
          ),
          if (switchError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(switchError!, style: const TextStyle(color: VeyraColors.danger, fontSize: 13))),
        ])),
        Semantics(
          label: _t('Disponible'),
          child: Switch(value: on, onChanged: switching ? null : toggle, activeThumbColor: Colors.white, activeTrackColor: VeyraColors.success),
        ),
      ]),
    );
  }

  Widget counters(Map<String, dynamic> d) {
    Widget cell(dynamic n, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                Text('${n ?? 0}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(label, textAlign: TextAlign.center, style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 13)),
              ]),
            ),
          ),
        );
    const divider = SizedBox(height: 44, child: VerticalDivider(width: 1));
    return DriverCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: IntrinsicHeight(
        child: Row(children: [
          cell(d['availableRequests'], _t('Demandes disponibles'), () => widget.go('/requests')),
          divider,
          cell(d['pendingOffers'], _t('Offres en attente'), () => widget.push('/driver/offers')),
          divider,
          cell(d['upcomingRides'], _t('Course à venir'), () => widget.go('/agenda')),
        ]),
      ),
    );
  }

  Widget nextRide(Map<String, dynamic>? ride) {
    if (ride == null) {
      return DriverCard(child: Row(children: [
        const Icon(Icons.event_available_outlined, color: VeyraColors.textSecondary),
        const SizedBox(width: 12),
        Expanded(child: Text(_t('Aucune course à venir pour le moment.'), style: const TextStyle(color: VeyraColors.textSecondary))),
      ]));
    }
    return DriverCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(driverWhen(ride['scheduled_at']), style: const TextStyle(fontWeight: FontWeight.w700))),
          DriverPill(driverStartsIn(ride['scheduled_at']), fg: VeyraColors.accent, bg: VeyraColors.infoBackground),
        ]),
        const SizedBox(height: 10),
        DriverMiniRoute((ride['pickup_address'] ?? '').toString(), (ride['dropoff_address'] ?? '').toString()),
        const SizedBox(height: 8),
        DriverPaxBags(ride['passenger_count'], ride['baggage_count']),
        const SizedBox(height: 14),
        FilledButton(onPressed: () => widget.push('/ride/${ride['id']}'), child: Text(_t('Voir les détails'))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: DriverTopBar(onNotifications: () => widget.push('/notifications')),
        body: RefreshIndicator(
          onRefresh: () async {
            reload();
            try { await dashboard; } catch (_) {}
          },
          child: FutureBuilder<Map<String, dynamic>>(
            future: dashboard,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) return const VeyraLoadingView();
              if (s.hasError) {
                return VeyraErrorMessages.isOffline(s.error!)
                    ? VeyraOfflineBanner(onRetry: reload)
                    : VeyraErrorView(customMessage: VeyraErrorMessages.forException(s.error!), onRetry: reload);
              }
              final d = s.data ?? {};
              final ride = d['nextRide'] is Map ? Map<String, dynamic>.from(d['nextRide'] as Map) : null;
              return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                availabilityCard(),
                counters(d),
                DriverSectionTitle(_t('Prochaine course'), action: _t('Voir tout'), onAction: () => widget.go('/agenda')),
                nextRide(ride),
                DriverSectionTitle(_t('Demandes récentes'), action: _t('Voir toutes'), onAction: () => widget.go('/requests')),
                FutureBuilder<List<dynamic>>(
                  future: recent,
                  builder: (context, r) {
                    if (r.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                    final items = (r.data ?? const []).whereType<Map>().take(2).map((m) => Map<String, dynamic>.from(m)).toList();
                    if (r.hasError || items.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          accepting == false ? _t('Passez en ligne pour recevoir de nouvelles demandes.') : _t('Aucune demande ouverte pour le moment.'),
                          style: const TextStyle(color: VeyraColors.textSecondary),
                        ),
                      );
                    }
                    return Column(children: [
                      for (final x in items) DriverRequestCard(request: x, onTap: () => widget.push('/request/${x['id']}')),
                    ]);
                  },
                ),
              ]);
            },
          ),
        ),
      );
}

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';
import '../formatters/date_formatter.dart';
import '../formatters/error_messages.dart';
import '../formatters/status_labels.dart';
import 'state_views.dart';

String _t(String s) => AppLocale.t(s);

/// Badge count of the bell (board 16 P1). Screens refresh it on load and
/// after reading notifications.
final ValueNotifier<int> veyraUnreadNotifications = ValueNotifier<int>(0);

/// Parsed notification row.
class VeyraNotification {
  final Map<String, dynamic> raw;
  final Map<String, dynamic> data;
  VeyraNotification(this.raw) : data = _data(raw['data']);
  static Map<String, dynamic> _data(dynamic d) {
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String && d.isNotEmpty) {
      try { return Map<String, dynamic>.from(jsonDecode(d) as Map); } catch (_) {}
    }
    return {};
  }
  String get id => (raw['id'] ?? '').toString();
  String get template => (raw['template_code'] ?? '').toString();
  String? get bookingId => data['bookingId']?.toString();
  bool get unread => raw['unread'] == true || (raw.containsKey('read_at') && raw['read_at'] == null && raw['unread'] != false);
  DateTime? get createdAt => DateTime.tryParse((raw['created_at'] ?? '').toString())?.toLocal();
  String get event => (data['event'] ?? '').toString();

  String get title {
    if (template == 'BOOKING_STATUS') {
      if (event.endsWith('.cancelled') || event.contains('cancel')) return _t('Demande annulée');
      if (event.endsWith('.driver_arrived')) return _t('Votre chauffeur est arrivé');
      if (event.endsWith('.in_progress') || event.endsWith('.started')) return _t('La course a démarré');
      if (event.endsWith('.completed')) return _t('Course terminée');
    }
    return VeyraStatusLabels.notificationTemplate(template);
  }

  String get body {
    final pickup = (raw['pickup_address'] ?? '').toString(), dropoff = (raw['dropoff_address'] ?? '').toString();
    final parts = <String>[
      if (pickup.isNotEmpty && dropoff.isNotEmpty) '$pickup → $dropoff',
      if (raw['scheduled_at'] != null) VeyraDateFormatter.dateTime(raw['scheduled_at']),
    ];
    return parts.join(' · ');
  }

  (IconData, Color, Color) get look => switch (template) {
        'NEW_BOOKING' => (Icons.description_outlined, VeyraColors.accent, VeyraColors.infoBackground),
        'NEW_OFFER' => (Icons.local_offer_outlined, VeyraColors.accent, VeyraColors.infoBackground),
        'OFFER_ACCEPTED' => (Icons.check_rounded, Colors.white, VeyraColors.success),
        _ when title == _t('Demande annulée') => (Icons.remove, Colors.white, VeyraColors.neutral),
        _ => (Icons.navigation_outlined, Colors.white, VeyraColors.accent),
      };
}

/// Liste des notifications (planche 16 P2) : regroupées par jour, point
/// rouge sur les non lues, « Tout marquer comme lu ».
class VeyraNotificationsScreen extends StatefulWidget {
  final Future<List<dynamic>> Function() load;
  final Future<int> Function(String id) markRead;
  final Future<int> Function() markAllRead;
  final void Function(VeyraNotification n) open;
  const VeyraNotificationsScreen({required this.load, required this.markRead, required this.markAllRead, required this.open, super.key});
  @override
  State<VeyraNotificationsScreen> createState() => _VeyraNotificationsScreenState();
}

class _VeyraNotificationsScreenState extends State<VeyraNotificationsScreen> {
  late Future<List<dynamic>> future = widget.load();
  final read = <String>{};
  bool markingAll = false;

  void reload() => setState(() { future = widget.load(); read.clear(); });

  static String group(DateTime? d) {
    if (d == null) return _t('Plus anciennes');
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days == 0) return _t('Aujourd’hui');
    if (days == 1) return _t('Hier');
    return _t('Plus anciennes');
  }

  static String time(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day || now.difference(d).inDays < 2) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return VeyraDateFormatter.dateTime(d.toUtc().toIso8601String()).split(' ').take(3).join(' ');
  }

  Future<void> tap(VeyraNotification n) async {
    if (n.unread && !read.contains(n.id)) {
      setState(() => read.add(n.id));
      try { veyraUnreadNotifications.value = await widget.markRead(n.id); } catch (_) {}
    }
    if (!mounted) return;
    // Linked to a request or a ride: straight to that screen (back returns
    // here). Otherwise the full information (board 16 P3).
    if (n.bookingId != null) {
      widget.open(n);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => VeyraNotificationDetailScreen(notification: n, open: widget.open)));
  }

  Future<void> markAll() async {
    setState(() => markingAll = true);
    try {
      veyraUnreadNotifications.value = await widget.markAllRead();
      reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(VeyraErrorMessages.forException(e))));
    } finally {
      if (mounted) setState(() => markingAll = false);
    }
  }

  Widget row(VeyraNotification n) {
    final (icon, fg, bg) = n.look;
    final unread = n.unread && !read.contains(n.id);
    return Material(
      color: unread ? VeyraColors.infoBackground.withValues(alpha: .45) : Colors.white,
      child: InkWell(
        onTap: () => tap(n),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 22, backgroundColor: bg, child: Icon(icon, color: fg)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
              if (n.body.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(n.body, style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 13)),
              ],
            ])),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(time(n.createdAt), style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 12)),
                if (unread) ...[
                  const SizedBox(width: 6),
                  Semantics(label: _t('Non lue'), child: Container(key: const ValueKey('unread-dot'), width: 9, height: 9, decoration: const BoxDecoration(color: VeyraColors.pinRed, shape: BoxShape.circle))),
                ],
              ]),
              if (n.bookingId != null) const Padding(padding: EdgeInsets.only(top: 8), child: Icon(Icons.chevron_right, color: VeyraColors.textSecondary)),
            ]),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text(_t('Notifications')), actions: [
          // Capped width: wraps on two lines with enlarged text.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: TextButton(onPressed: markingAll ? null : markAll, child: Text(_t('Tout marquer comme lu'), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: const TextStyle(decoration: TextDecoration.underline, fontSize: 13))),
          ),
        ]),
        body: RefreshIndicator(
          onRefresh: () async { reload(); try { await future; } catch (_) {} },
          child: FutureBuilder<List<dynamic>>(
            future: future,
            builder: (context, s) {
              if (s.connectionState != ConnectionState.done) {
                return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SizedBox(height: 220), Center(child: CircularProgressIndicator())]);
              }
              if (s.hasError) {
                return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                  const SizedBox(height: 160),
                  VeyraErrorMessages.isOffline(s.error!) ? VeyraOfflineBanner(onRetry: reload) : VeyraErrorView(customMessage: VeyraErrorMessages.forException(s.error!), onRetry: reload),
                ]);
              }
              final items = (s.data ?? const []).whereType<Map>().map((m) => VeyraNotification(Map<String, dynamic>.from(m))).toList();
              if (items.isEmpty) {
                return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                  const SizedBox(height: 160),
                  const Icon(Icons.notifications_none, size: 56, color: VeyraColors.textSecondary),
                  Center(child: Text(_t('Aucune notification pour le moment.'))),
                ]);
              }
              final children = <Widget>[];
              String? current;
              for (final n in items) {
                final g = group(n.createdAt);
                if (g != current) {
                  current = g;
                  children.add(Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                    child: Text(g, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ));
                }
                children.add(row(n));
                children.add(const Divider(height: 1, indent: 72));
              }
              return ListView(physics: const AlwaysScrollableScrollPhysics(), children: children);
            },
          ),
        ),
      );
}

/// Détail d'une notification (planche 16 P3) : information complète et
/// lien vers l'écran concerné.
class VeyraNotificationDetailScreen extends StatelessWidget {
  final VeyraNotification notification;
  final void Function(VeyraNotification n) open;
  const VeyraNotificationDetailScreen({required this.notification, required this.open, super.key});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final (icon, fg, bg) = n.look;
    final raw = n.raw;
    final pickup = (raw['pickup_address'] ?? '').toString(), dropoff = (raw['dropoff_address'] ?? '').toString();
    final when = n.createdAt;
    final pax = (raw['passenger_count'] as num?)?.toInt();
    final bags = (raw['baggage_count'] as num?)?.toInt();
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(_t('Notification'))),
      body: ListView(children: [
        Container(
          color: VeyraColors.warningBackground.withValues(alpha: .6),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(radius: 24, backgroundColor: bg, child: Icon(icon, color: fg)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(n.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                if (when != null) Text(VeyraDateFormatter.dateTime(when.toUtc().toIso8601String()), style: const TextStyle(color: VeyraColors.textSecondary)),
              ])),
            ]),
            if (n.body.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(n.body, style: const TextStyle(fontSize: 15, height: 1.4)),
            ],
          ]),
        ),
        if (pickup.isNotEmpty || dropoff.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t('Détail de la demande'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(VeyraRadius.card), border: Border.all(color: VeyraColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (raw['scheduled_at'] != null) Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(VeyraDateFormatter.dateTime(raw['scheduled_at']))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [const Icon(Icons.location_on, size: 18, color: VeyraColors.accent), const SizedBox(width: 8), Expanded(child: Text(pickup))]),
                  const SizedBox(height: 6),
                  Row(children: [const Icon(Icons.location_on, size: 18, color: VeyraColors.pinRed), const SizedBox(width: 8), Expanded(child: Text(dropoff))]),
                  if (pax != null || bags != null) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 18, children: [
                      if (pax != null) Text('$pax ${pax > 1 ? _t('passagers') : _t('passager')}', style: const TextStyle(color: VeyraColors.textSecondary)),
                      if (bags != null) Text('$bags ${bags > 1 ? _t('bagages') : _t('bagage')}', style: const TextStyle(color: VeyraColors.textSecondary)),
                    ]),
                  ],
                ]),
              ),
            ]),
          ),
      ]),
      bottomNavigationBar: n.bookingId == null
          ? null
          : SafeArea(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton(
                onPressed: () => open(n),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Text(_t('Voir la demande')), const SizedBox(width: 8), const Icon(Icons.arrow_forward)]),
              ),
            )),
    );
  }
}

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../api.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';
import '../../chat_socket.dart';
import '../formatters/date_formatter.dart';
import 'state_views.dart';
import 'status_badge.dart';

String _t(String fr) => AppLocale.t(fr);

/// Conversation of a ride, same visual language as the other screens:
/// counterpart header, newest messages always visible (reversed list, so the
/// keyboard never hides them), day separators, navy / white bubbles and a
/// white composer bar. Real time via STOMP, with a 5 s polling fallback.
class VeyraChatView extends StatefulWidget {
  final Api api;
  final String bookingId;
  /// Name of the other person, read from the booking (driver or customer).
  final String Function(Map<String, dynamic> booking) counterpartName;
  const VeyraChatView({required this.api, required this.bookingId, required this.counterpartName, super.key});
  @override
  State<VeyraChatView> createState() => _VeyraChatViewState();
}

class _VeyraChatViewState extends State<VeyraChatView> {
  final input = TextEditingController();
  final messages = <Map<String, dynamic>>[];
  Map<String, dynamic>? booking;
  String? myUserId;
  bool loading = true, loadError = false, sending = false;
  String? sendError;
  ChatSocket? socket;
  Timer? poller;

  Api get api => widget.api;

  @override
  void initState() {
    super.initState();
    _load();
    _loadBooking();
    poller = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
  }

  @override
  void dispose() {
    poller?.cancel();
    socket?.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> _loadBooking() async {
    try {
      final b = await api.bookingDetail(widget.bookingId);
      if (mounted) setState(() => booking = b);
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() { loading = true; loadError = false; });
    try {
      final me = await api.me();
      final history = await api.chatMessages(widget.bookingId);
      if (!mounted) return;
      setState(() {
        myUserId = (me['id'] ?? '').toString();
        messages
          ..clear()
          ..addAll(history.map((e) => Map<String, dynamic>.from(e as Map)));
        loading = false;
      });
      socket?.dispose();
      socket = ChatSocket(api: api, bookingId: widget.bookingId, onMessage: _incoming)..connect();
    } catch (_) {
      if (mounted) setState(() { loading = false; loadError = true; });
    }
  }

  Future<void> _poll() async {
    if (!mounted || loading) return;
    _loadBooking();
    try {
      final history = await api.chatMessages(widget.bookingId);
      if (!mounted) return;
      final fresh = history.map((e) => Map<String, dynamic>.from(e as Map)).where((m) => !_known(m['id'])).toList();
      if (fresh.isNotEmpty) setState(() => messages.addAll(fresh));
    } catch (_) {}
  }

  bool _known(Object? id) => id != null && messages.any((m) => m['id']?.toString() == id.toString());

  void _incoming(Map<String, dynamic> m) {
    if (!mounted || _known(m['id'])) return;
    setState(() => messages.add(m));
  }

  Future<void> send() async {
    final draft = input.text, body = draft.trim();
    if (sending || body.isEmpty) return;
    setState(() { sending = true; sendError = null; });
    try {
      final sent = await api.sendMessage(widget.bookingId, body);
      if (!mounted) return;
      if (input.text == draft) input.clear();
      if (!_known(sent['id'])) setState(() => messages.add(sent));
    } on DioException catch (e) {
      final code = e.response?.data is Map ? (e.response!.data as Map)['code']?.toString() : null;
      if (mounted) {
        setState(() => sendError = code != null && code.startsWith('CHAT_')
            ? _t('La messagerie est ouverte 30 minutes avant le départ et jusqu’à 1 heure après la course.')
            : _t('Message non envoyé, réessayez.'));
      }
    } catch (_) {
      if (mounted) setState(() => sendError = _t('Message non envoyé, réessayez.'));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  DateTime? _at(Map<String, dynamic> m) => DateTime.tryParse((m['sentAt'] ?? m['sent_at'] ?? '').toString())?.toLocal();
  static String _two(int n) => n.toString().padLeft(2, '0');

  String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return _t('Aujourd’hui');
    if (diff == 1) return _t('Hier');
    return VeyraDateFormatter.dateTime(d.toUtc().toIso8601String()).split(' ').take(3).join(' ');
  }

  static String _short(String address) => address.split(',').first.trim();

  Widget _header() {
    final b = booking;
    if (b == null) return const SizedBox.shrink();
    final name = widget.counterpartName(b).trim();
    final initials = name.isEmpty ? '?' : name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: VeyraColors.border))),
      child: Row(children: [
        CircleAvatar(radius: 22, backgroundColor: VeyraColors.surfaceMuted,
            child: Text(initials, style: const TextStyle(fontWeight: FontWeight.w800, color: VeyraColors.primary))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name.isEmpty ? _t('Votre interlocuteur') : name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          Text('${_short((b['pickup_address'] ?? '').toString())} → ${_short((b['dropoff_address'] ?? '').toString())}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 13)),
        ])),
        const SizedBox(width: 8),
        Flexible(child: VeyraStatusBadge(status: b['status']?.toString() ?? '')),
      ]),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = myUserId != null && (m['senderUserId'] ?? m['sender_user_id'])?.toString() == myUserId;
    final at = _at(m);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .76),
        decoration: BoxDecoration(
          color: mine ? VeyraColors.primary : Colors.white,
          border: mine ? null : Border.all(color: VeyraColors.border),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Text((m['body'] ?? '').toString(), style: TextStyle(color: mine ? Colors.white : VeyraColors.textPrimary, fontSize: 15, height: 1.3)),
          if (at != null) ...[
            const SizedBox(height: 3),
            Text('${_two(at.hour)}:${_two(at.minute)}', style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : VeyraColors.textTertiary)),
          ],
        ]),
      ),
    );
  }

  Widget _daySeparator(String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: VeyraColors.surfaceMuted, borderRadius: BorderRadius.circular(VeyraRadius.pill)),
          child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: VeyraColors.textSecondary)),
        )),
      );

  Widget _list() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (loadError) return VeyraErrorView(customMessage: _t('Impossible de charger la conversation.'), onRetry: _load);
    if (messages.isEmpty) {
      return VeyraEmptyView(icon: Icons.chat_bubble_outline, message: _t('Aucun message pour le moment. Écrivez le premier !'));
    }
    final sorted = [...messages]..sort((a, b) => (_at(a) ?? DateTime(0)).compareTo(_at(b) ?? DateTime(0)));
    // Reversed: index 0 is the newest message, kept at the bottom above the
    // composer even while the keyboard is open.
    final items = <Widget>[];
    for (var i = sorted.length - 1; i >= 0; i--) {
      items.add(_bubble(sorted[i]));
      final at = _at(sorted[i]), before = i > 0 ? _at(sorted[i - 1]) : null;
      final newDay = at != null && (before == null || before.year != at.year || before.month != at.month || before.day != at.day);
      if (newDay) items.add(_daySeparator(_day(at)));
    }
    return ListView(
      key: const ValueKey('chat-list'),
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: items,
    );
  }

  Widget _composer() => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: VeyraColors.border))),
        child: SafeArea(top: false, child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (sendError != null) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(sendError!, style: const TextStyle(color: VeyraColors.danger, fontSize: 13))),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: TextField(
                key: const ValueKey('chat-input'),
                controller: input,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => send(),
                decoration: InputDecoration(
                  hintText: _t('Votre message'),
                  counterText: '',
                  filled: true,
                  fillColor: VeyraColors.surfaceMuted,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: const BorderSide(color: VeyraColors.accent)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              )),
              const SizedBox(width: 8),
              SizedBox(width: 48, height: 48, child: Material(
                color: VeyraColors.primary,
                shape: const CircleBorder(),
                child: IconButton(
                  key: const ValueKey('chat-send'),
                  tooltip: _t('Envoyer'),
                  onPressed: sending ? null : send,
                  icon: sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              )),
            ]),
          ]),
        )),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFFF6F7FA),
        appBar: AppBar(title: Text(_t('Messages'))),
        body: Column(children: [
          _header(),
          Expanded(child: _list()),
          _composer(),
        ]),
      );
}

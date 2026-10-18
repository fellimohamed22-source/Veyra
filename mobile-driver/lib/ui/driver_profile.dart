import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../api.dart';
import '../app/theme.dart';
import '../app_locale.dart';
import '../core/formatters/error_messages.dart';
import '../core/formatters/money_formatter.dart';
import '../core/widgets/state_views.dart';
import '../core/widgets/veyra_ui.dart';
import 'driver_ui.dart';

String _t(String s) => AppLocale.t(s);

/// Profil chauffeur (planche 12 P10) : identité, puis accès aux véhicules,
/// documents, préférences, portefeuille et paramètres.
class DriverProfileScreen extends StatefulWidget {
  final Api api;
  final void Function(String route) go;
  final void Function(String route) push;
  final Future<void> Function() logout;
  const DriverProfileScreen({required this.api, required this.go, required this.push, required this.logout, super.key});
  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  late Future<Map<String, dynamic>> me;
  late Future<Map<String, dynamic>> dossier;
  late Future<Map<String, dynamic>> wallet;
  Uint8List? avatar;
  bool loggingOut = false;

  @override
  void initState() {
    super.initState();
    load();
    widget.api.avatarBytes().then((v) { if (mounted) setState(() => avatar = v); }).catchError((_) {});
  }

  void load() {
    me = widget.api.me();
    dossier = widget.api.onboardingStatus();
    wallet = widget.api.wallet();
    dossier.ignore();
    wallet.ignore();
  }

  Future<void> preferences() async {
    bool? accepting;
    try { accepting = await widget.api.availability(); } catch (_) {}
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(builder: (sheet, setSheet) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(_t('Mes préférences'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: accepting ?? true,
                title: Text(_t('Disponible pour recevoir des demandes')),
                subtitle: Text(_t('Hors ligne, vous ne recevez plus de nouvelles demandes ; vos courses restent accessibles.')),
                onChanged: (v) async {
                  setSheet(() => accepting = v);
                  try {
                    final saved = await widget.api.setAvailability(v);
                    setSheet(() => accepting = saved);
                  } catch (e) {
                    setSheet(() => accepting = !v);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(VeyraErrorMessages.forException(e))));
                  }
                },
              ),
            ]),
          )),
    );
  }

  Widget item(IconData icon, String title, String subtitle, VoidCallback onTap, {Key? key}) => ListTile(
        key: key,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: Icon(icon, color: VeyraColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle, style: const TextStyle(color: VeyraColors.textSecondary)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: DriverTopBar(onNotifications: () => widget.push('/notifications')),
        body: FutureBuilder<Map<String, dynamic>>(
          future: me,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const VeyraLoadingView();
            if (s.hasError) return VeyraErrorView(customMessage: VeyraErrorMessages.forException(s.error!), onRetry: () => setState(load));
            final m = s.data ?? {};
            final name = '${m['first_name'] ?? ''} ${m['last_name'] ?? ''}'.trim();
            final rating = double.tryParse((m['rating_average'] ?? 0).toString()) ?? 0;
            final count = m['rating_count'] ?? 0;
            return RefreshIndicator(
              onRefresh: () async { setState(load); try { await me; } catch (_) {} },
              child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                DriverCard(
                  onTap: () => widget.push('/settings'),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: VeyraColors.surfaceMuted,
                      backgroundImage: avatar == null ? null : MemoryImage(avatar!),
                      child: avatar == null ? const Icon(Icons.person, size: 34, color: VeyraColors.textSecondary) : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name.isEmpty ? _t('Chauffeur Veyra') : name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Row(children: [
                        const Icon(Icons.star_rounded, size: 18, color: Color(0xFFF5A623)),
                        const SizedBox(width: 2),
                        Flexible(child: Text(rating == 0 ? _t('Nouveau') : '${rating.toStringAsFixed(1).replaceAll('.', ',')} ($count)')),
                      ]),
                      FutureBuilder<Map<String, dynamic>>(future: dossier, builder: (context, d) {
                        final approved = d.data?['kyc_status'] == 'APPROVED';
                        return Row(children: [
                          Icon(approved ? Icons.verified : Icons.pending_outlined, size: 16, color: approved ? VeyraColors.success : VeyraColors.warning),
                          const SizedBox(width: 4),
                          Flexible(child: Text(approved ? _t('Chauffeur vérifié') : _t('Dossier en cours de vérification'),
                              style: TextStyle(color: approved ? VeyraColors.success : VeyraColors.warning, fontWeight: FontWeight.w600, fontSize: 13))),
                        ]);
                      }),
                    ])),
                    const Icon(Icons.chevron_right),
                  ]),
                ),
                DriverCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Column(children: [
                    FutureBuilder<Map<String, dynamic>>(future: dossier, builder: (context, d) {
                      final n = (d.data?['vehicles'] as List? ?? const []).length;
                      return item(Icons.directions_car_outlined, _t('Mes véhicules'), n == 0 ? _t('Aucun véhicule enregistré') : '$n ${n > 1 ? _t('véhicules enregistrés') : _t('véhicule enregistré')}', () => widget.push('/vehicles'), key: const ValueKey('menu-vehicles'));
                    }),
                    const Divider(height: 1),
                    item(Icons.description_outlined, _t('Mes documents'), _t('Permis, assurance, etc.'), () => widget.push('/kyc')),
                    const Divider(height: 1),
                    item(Icons.tune, _t('Mes préférences'), _t('Disponibilité'), preferences),
                    const Divider(height: 1),
                    FutureBuilder<Map<String, dynamic>>(future: wallet, builder: (context, w) {
                      final balance = w.data?['onlinePayableMinor'];
                      return item(Icons.account_balance_wallet_outlined, _t('Mon portefeuille'), balance == null ? _t('Revenus et versements') : '${_t('Solde')} : ${VeyraMoneyFormatter.fromMinor(balance)}', () => widget.go('/wallet'));
                    }),
                    const Divider(height: 1),
                    item(Icons.settings_outlined, _t('Paramètres'), _t('Profil, mot de passe, langue'), () => widget.push('/settings')),
                  ]),
                ),
                TextButton.icon(
                  onPressed: loggingOut ? null : () async {
                    setState(() => loggingOut = true);
                    try { await widget.logout(); } finally { if (mounted) setState(() => loggingOut = false); }
                  },
                  style: TextButton.styleFrom(foregroundColor: VeyraColors.danger),
                  icon: const Icon(Icons.logout),
                  label: Text(_t('Se déconnecter')),
                ),
              ]),
            );
          },
        ),
      );
}

/// Mes véhicules (planche 12 P11) : véhicules autorisés pour les offres.
class DriverVehiclesScreen extends StatefulWidget {
  final Api api;
  final void Function(String route) push;
  const DriverVehiclesScreen({required this.api, required this.push, super.key});
  @override
  State<DriverVehiclesScreen> createState() => _DriverVehiclesScreenState();
}

class _DriverVehiclesScreenState extends State<DriverVehiclesScreen> {
  late Future<Map<String, dynamic>> dossier = widget.api.onboardingStatus();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text(_t('Mes véhicules'))),
        body: FutureBuilder<Map<String, dynamic>>(
          future: dossier,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const VeyraLoadingView();
            if (s.hasError) return VeyraErrorView(customMessage: VeyraErrorMessages.forException(s.error!), onRetry: () => setState(() => dossier = widget.api.onboardingStatus()));
            final vehicles = (s.data?['vehicles'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
              if (vehicles.isEmpty)
                DriverCard(child: Text(_t('Aucun véhicule enregistré.'), style: const TextStyle(color: VeyraColors.textSecondary))),
              for (final v in vehicles)
                DriverCard(child: Row(children: [
                  const VeyraVehicleThumb(width: 88),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${v['brand'] ?? ''} ${v['model'] ?? ''}'.trim(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (v['category_name'] != null) Text(v['category_name'].toString(), style: const TextStyle(color: VeyraColors.accent, fontSize: 13)),
                    if (v['plate_number'] != null) Text(v['plate_number'].toString(), style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 13)),
                    const SizedBox(height: 4),
                    DriverPaxBags(v['seats'], v['baggage_capacity'], labels: false),
                  ])),
                  switch (v['status']?.toString()) {
                    'APPROVED' => DriverPill(_t('Actif'), fg: VeyraColors.success, bg: VeyraColors.successBackground),
                    'REJECTED' => DriverPill(_t('Refusé'), fg: VeyraColors.danger, bg: VeyraColors.dangerBackground),
                    _ => DriverPill(_t('En attente'), fg: VeyraColors.warning, bg: VeyraColors.warningBackground),
                  },
                ])),
              const SizedBox(height: 4),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddVehicleScreen(api: widget.api)));
                  if (mounted) setState(() => dossier = widget.api.onboardingStatus());
                },
                icon: const Icon(Icons.add),
                label: Text(_t('Ajouter un véhicule')),
              ),
              const SizedBox(height: 14),
              VeyraBanner(tone: VeyraTone.info, text: _t('Seuls les types de véhicules enregistrés et validés sont disponibles lors de la création d’une offre.')),
            ]);
          },
        ),
      );
}

/// Ajout d'un véhicule (soumis à validation par l'équipe VEYRA).
class AddVehicleScreen extends StatefulWidget {
  final Api api;
  const AddVehicleScreen({required this.api, super.key});
  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  late Future<List<dynamic>> categories = widget.api.vehicleCategories();
  final brand = TextEditingController();
  final model = TextEditingController();
  final plate = TextEditingController();
  String? categoryId;
  int? year;
  int seats = 4;
  int baggage = 3;
  bool saving = false;
  String? error;

  @override
  void dispose() {
    brand.dispose();
    model.dispose();
    plate.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (categoryId == null || brand.text.trim().isEmpty || model.text.trim().isEmpty || plate.text.trim().isEmpty || year == null) {
      return setState(() => error = _t('Catégorie, marque, modèle, année et immatriculation requis.'));
    }
    setState(() { saving = true; error = null; });
    try {
      await widget.api.addVehicle(categoryId: categoryId!, brand: brand.text.trim(), model: model.text.trim(), year: year!, plateNumber: plate.text.trim().toUpperCase(), seats: seats, baggageCapacity: baggage);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => error = VeyraErrorMessages.forException(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (var y = DateTime.now().year + 1; y >= DateTime.now().year - 15; y--) y];
    return Scaffold(
      appBar: AppBar(title: Text(_t('Ajouter un véhicule'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        FutureBuilder<List<dynamic>>(future: categories, builder: (context, s) {
          if (!s.hasData) return const LinearProgressIndicator();
          return DropdownButtonFormField<String>(
            initialValue: categoryId,
            isExpanded: true,
            decoration: InputDecoration(labelText: _t('Catégorie')),
            items: [for (final c in s.data!.whereType<Map>()) DropdownMenuItem(value: c['id'].toString(), child: Text((c['display_name'] ?? c['code']).toString()))],
            onChanged: (v) => setState(() => categoryId = v),
          );
        }),
        const SizedBox(height: 12),
        TextField(controller: brand, decoration: InputDecoration(labelText: _t('Marque'))),
        const SizedBox(height: 12),
        TextField(controller: model, decoration: InputDecoration(labelText: _t('Modèle'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: year,
          decoration: InputDecoration(labelText: _t('Année')),
          items: [for (final y in years) DropdownMenuItem(value: y, child: Text('$y'))],
          onChanged: (v) => setState(() => year = v),
        ),
        const SizedBox(height: 12),
        TextField(controller: plate, decoration: InputDecoration(labelText: _t('Immatriculation'))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: DropdownButtonFormField<int>(
            initialValue: seats,
            decoration: InputDecoration(labelText: _t('Nombre de places')),
            items: [for (var i = 1; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i'))],
            onChanged: (v) => setState(() => seats = v ?? seats),
          )),
          const SizedBox(width: 12),
          Expanded(child: DropdownButtonFormField<int>(
            initialValue: baggage,
            decoration: InputDecoration(labelText: _t('Capacité bagages')),
            items: [for (var i = 0; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))],
            onChanged: (v) => setState(() => baggage = v ?? baggage),
          )),
        ]),
        const SizedBox(height: 12),
        VeyraBanner(tone: VeyraTone.info, text: _t('Le véhicule sera disponible pour vos offres après validation par l’équipe VEYRA. Ajoutez sa carte grise depuis Mes documents.')),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: VeyraBanner(tone: VeyraTone.danger, text: error!)),
      ]),
      bottomNavigationBar: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: FilledButton(onPressed: saving ? null : save, child: Text(saving ? _t('Enregistrement…') : _t('Enregistrer le véhicule'))),
      )),
    );
  }
}

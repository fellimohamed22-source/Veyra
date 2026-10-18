import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../app/theme.dart';
import '../app_locale.dart';
import '../core/formatters/error_messages.dart';
import '../core/widgets/auth_ui.dart';
import '../core/widgets/veyra_ui.dart' show VeyraStepTitle;
import '../core/widgets/signup_consents.dart';

String _t(String s) => AppLocale.t(s);

/// Picks a document or photo and returns its local path (null: cancelled).
typedef PickFile = Future<String?> Function({bool imageOnly});

enum DriverKind { independent, affiliated }

/// Inscription chauffeur indépendant (planche 08 B2-B9, DR-AUTH-01..09).
///
/// Type de chauffeur, puis 7 étapes : informations, pièce d'identité,
/// carte VTC, permis, entreprise (+ assurance), véhicule (+ carte grise),
/// récapitulatif et envoi. Le compte est créé à l'étape 1 (les envois de
/// documents exigent d'être connecté) ; chaque étape enregistre ses
/// données, si bien que le parcours reprend là où il s'est arrêté.
class DriverSignupFlow extends StatefulWidget {
  final Api api;
  final PickFile pickFile;
  /// Called once the account exists (push registration…).
  final Future<void> Function() onAccountCreated;
  final VoidCallback onSubmitted;
  final VoidCallback onExit;
  /// Opens on an existing draft (signed-in driver) instead of the type choice.
  final bool resume;
  const DriverSignupFlow({
    required this.api,
    required this.pickFile,
    required this.onAccountCreated,
    required this.onSubmitted,
    required this.onExit,
    this.resume = false,
    super.key,
  });
  @override
  State<DriverSignupFlow> createState() => DriverSignupFlowState();
}

/// Upload state of one document page.
class _Page {
  bool sent = false;
  bool busy = false;
  String? error;
}

class DriverSignupFlowState extends State<DriverSignupFlow> {
  static const independentSteps = 7;

  DriverKind? kind;
  /// 0 = driver type (B2), 1..7 = steps, 8 = sent.
  int step = 0;
  bool accountCreated = false;
  bool busy = false;
  String? error;

  // Step 1: personal information.
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  DateTime? birthDate;
  String? avatarPath;
  bool acceptTerms = false, acceptPrivacy = false, marketingOptIn = false, consentErrors = false;

  // Step 2: identity document.
  String idType = 'ID_CARD';

  // Step 3: VTC card.
  final vtcCard = TextEditingController();
  DateTime? vtcExpiry;

  // Step 4: driving licence.
  final licenseNumber = TextEditingController();
  String licenseCategory = 'B';
  DateTime? licenseExpiry;

  // Step 5: company.
  String legalForm = 'AUTO_ENTREPRENEUR';
  final legalName = TextEditingController();
  final sirenSiret = TextEditingController();
  final address = TextEditingController();
  final revtc = TextEditingController();

  // Step 6: vehicle.
  List<Map<String, dynamic>> categories = [];
  String? categoryId;
  final brand = TextEditingController();
  final model = TextEditingController();
  final plate = TextEditingController();
  int? vehicleYear;
  int seats = 4;
  int baggage = 3;
  bool hasVehicle = false;

  // Step 7: summary.
  bool acceptCharter = false;
  List<String> missing = [];

  final pages = <String, _Page>{};
  _Page page(String type, [String? side]) => pages.putIfAbsent('$type/${side ?? ''}', _Page.new);

  static const legalForms = {
    'AUTO_ENTREPRENEUR': 'Auto-entrepreneur',
    'EI': 'Entreprise individuelle (EI)',
    'EURL': 'EURL',
    'SASU': 'SASU',
    'SARL': 'SARL',
    'SAS': 'SAS',
  };

  @override
  void initState() {
    super.initState();
    if (widget.resume) {
      kind = DriverKind.independent;
      accountCreated = true;
      step = 1;
      _loadDraft();
    }
  }

  @override
  void dispose() {
    for (final c in [firstName, lastName, phone, email, password, vtcCard, licenseNumber, legalName, sirenSiret, address, revtc, brand, model, plate]) {
      c.dispose();
    }
    super.dispose();
  }

  static String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static String display(DateTime? d) => d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String get e164 {
    final raw = phone.text.replaceAll(RegExp(r'[\s.\-()]'), '');
    if (raw.startsWith('+')) return raw;
    return '+33${raw.startsWith('0') ? raw.substring(1) : raw}';
  }

  /// Prefills every step from the saved draft and opens the first
  /// incomplete one.
  Future<void> _loadDraft() async {
    setState(() => busy = true);
    try {
      final s = await widget.api.onboardingStatus();
      final me = await widget.api.me();
      firstName.text = (me['first_name'] ?? '').toString();
      lastName.text = (me['last_name'] ?? '').toString();
      email.text = (me['email'] ?? '').toString();
      phone.text = (me['phone'] ?? '').toString();
      birthDate = DateTime.tryParse((s['birth_date'] ?? '').toString());
      for (final d in (s['documents'] as List? ?? const []).whereType<Map>()) {
        final type = d['type'].toString();
        page(type, d['side']?.toString()).sent = true;
        if (type == 'IDENTITY' && d['subtype'] != null) idType = d['subtype'].toString();
      }
      final reg = (s['registration'] as List? ?? const []).whereType<Map>();
      if (reg.isNotEmpty) {
        vtcCard.text = (reg.first['card_number'] ?? '').toString();
        revtc.text = (reg.first['registration_number'] ?? '').toString();
        vtcExpiry = DateTime.tryParse((reg.first['expires_at'] ?? '').toString());
      }
      final lic = (s['license'] as List? ?? const []).whereType<Map>();
      if (lic.isNotEmpty) {
        licenseNumber.text = (lic.first['license_number'] ?? '').toString();
        licenseCategory = (lic.first['category'] ?? 'B').toString();
        licenseExpiry = DateTime.tryParse((lic.first['expires_at'] ?? '').toString());
      }
      final co = (s['company'] as List? ?? const []).whereType<Map>();
      if (co.isNotEmpty) {
        final c = co.first;
        legalForm = legalForms.containsKey(c['legal_form']) ? c['legal_form'].toString() : legalForm;
        legalName.text = (c['legal_name'] ?? '').toString();
        sirenSiret.text = (c['siret'] ?? c['siren'] ?? '').toString();
        address.text = (c['address'] ?? '').toString();
      }
      final v = (s['vehicles'] as List? ?? const []).whereType<Map>();
      if (v.isNotEmpty) {
        final x = v.first;
        hasVehicle = true;
        categoryId = x['category_id']?.toString();
        brand.text = (x['brand'] ?? '').toString();
        model.text = (x['model'] ?? '').toString();
        plate.text = (x['plate_number'] ?? '').toString();
        vehicleYear = (x['year'] as num?)?.toInt();
        seats = (x['seats'] as num?)?.toInt() ?? seats;
        baggage = (x['baggage_capacity'] as num?)?.toInt() ?? baggage;
      }
      missing = (s['missing'] as List? ?? const []).map((e) => e.toString()).toList();
      step = _firstIncompleteStep();
    } catch (e) {
      error = VeyraErrorMessages.forException(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  int _firstIncompleteStep() {
    if (missing.contains('BIRTH_DATE')) return 1;
    if (missing.contains('IDENTITY')) return 2;
    if (missing.contains('VTC_CARD') || missing.contains('VTC')) return 3;
    if (missing.contains('DRIVING_LICENSE') || missing.contains('LICENSE')) return 4;
    if (missing.contains('COMPANY') || missing.contains('INSURANCE')) return 5;
    if (missing.contains('VEHICLE') || missing.contains('VEHICLE_REGISTRATION')) return 6;
    return 7;
  }

  Future<void> _loadCategories() async {
    if (categories.isNotEmpty) return;
    try {
      final items = await widget.api.vehicleCategories();
      if (mounted) setState(() => categories = items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
    } catch (_) {}
  }

  Future<void> upload(String type, {String? side, String? subtype, DateTime? expiresAt, bool imageOnly = false}) async {
    final p = page(type, side);
    if (p.busy) return;
    final path = await widget.pickFile(imageOnly: imageOnly);
    if (path == null) return;
    setState(() { p.busy = true; p.error = null; });
    try {
      await widget.api.uploadDocument(type, path, side: side, subtype: subtype, expiresAt: expiresAt == null ? null : iso(expiresAt));
      if (mounted) setState(() => p.sent = true);
    } catch (e) {
      if (mounted) setState(() => p.error = VeyraErrorMessages.forException(e));
    } finally {
      if (mounted) setState(() => p.busy = false);
    }
  }

  Future<DateTime?> pickDate(DateTime? current, {required DateTime first, required DateTime last, DateTime? initial}) => showDatePicker(
        context: context,
        initialDate: current ?? initial ?? last,
        firstDate: first,
        lastDate: last,
      );

  // ---------------------------------------------------------------- steps

  /// Validates and saves the current step; true when the flow may move on.
  Future<bool> saveStep() async {
    switch (step) {
      case 1:
        if (firstName.text.trim().isEmpty || lastName.text.trim().isEmpty) return _fail(_t('Prénom et nom requis.'));
        if (birthDate == null) return _fail(_t('Date de naissance requise.'));
        if (!RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(e164)) return _fail(_t('Téléphone incomplet'));
        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.text.trim())) return _fail(_t('E-mail invalide'));
        if (!accountCreated) {
          if (password.text.length < 10) return _fail(_t('Mot de passe : 10 caractères minimum.'));
          if (!SignupConsents.mandatoryAccepted(acceptTerms, acceptPrivacy)) {
            setState(() => consentErrors = true);
            return _fail(_t('Acceptez les CGU et la politique de confidentialité pour continuer.'));
          }
          await widget.api.register(
            email: email.text.trim(), password: password.text, firstName: firstName.text.trim(), lastName: lastName.text.trim(),
            phone: e164, acceptTerms: acceptTerms, acceptPrivacy: acceptPrivacy, marketingOptIn: marketingOptIn,
          );
          accountCreated = true;
          await widget.onAccountCreated();
          if (avatarPath != null) {
            try { await widget.api.uploadAvatar(avatarPath!); } catch (_) {}
          }
        }
        await widget.api.saveDriverProfile(birthDate: iso(birthDate!), driverType: 'INDEPENDENT');
        return true;
      case 2:
        if (!page('IDENTITY', 'FRONT').sent) return _fail(_t('Ajoutez le recto de votre pièce d’identité.'));
        if (idType != 'PASSPORT' && !page('IDENTITY', 'BACK').sent) return _fail(_t('Ajoutez le verso de votre pièce d’identité.'));
        return true;
      case 3:
        if (vtcCard.text.trim().isEmpty) return _fail(_t('Numéro de carte VTC requis.'));
        if (vtcExpiry == null) return _fail(_t('Date de validité requise.'));
        if (!page('VTC_CARD', 'FRONT').sent || !page('VTC_CARD', 'BACK').sent) return _fail(_t('Ajoutez le recto et le verso de la carte VTC.'));
        await widget.api.saveVtc(registrationNumber: revtc.text.trim().isEmpty ? null : revtc.text.trim(), cardNumber: vtcCard.text.trim(), expiresAt: iso(vtcExpiry!));
        return true;
      case 4:
        if (licenseNumber.text.trim().isEmpty) return _fail(_t('Numéro de permis requis.'));
        if (licenseExpiry == null) return _fail(_t('Date de validité requise.'));
        if (!page('DRIVING_LICENSE', 'FRONT').sent) return _fail(_t('Ajoutez une photo de votre permis.'));
        await widget.api.saveLicense(licenseNumber: licenseNumber.text.trim(), category: licenseCategory, expiresAt: iso(licenseExpiry!));
        return true;
      case 5:
        final digits = sirenSiret.text.replaceAll(RegExp(r'\s'), '');
        if (!RegExp(r'^(\d{9}|\d{14})$').hasMatch(digits)) return _fail(_t('SIREN (9 chiffres) ou SIRET (14 chiffres) requis.'));
        if (address.text.trim().isEmpty) return _fail(_t('Adresse requise.'));
        if (_needsLegalName && legalName.text.trim().isEmpty) return _fail(_t('Raison sociale requise.'));
        if (!page('INSURANCE').sent) return _fail(_t('Ajoutez votre attestation d’assurance.'));
        await widget.api.saveCompany(
          siren: digits.substring(0, 9),
          siret: digits.length == 14 ? digits : null,
          legalName: _needsLegalName ? legalName.text.trim() : '${firstName.text.trim()} ${lastName.text.trim()}'.trim(),
          legalForm: legalForm,
          address: address.text.trim(),
        );
        if (revtc.text.trim().isNotEmpty && vtcCard.text.trim().isNotEmpty) {
          await widget.api.saveVtc(registrationNumber: revtc.text.trim(), cardNumber: vtcCard.text.trim(), expiresAt: vtcExpiry == null ? null : iso(vtcExpiry!));
        }
        return true;
      case 6:
        if (!hasVehicle) {
          if (categoryId == null) return _fail(_t('Choisissez la catégorie du véhicule.'));
          if (brand.text.trim().isEmpty || model.text.trim().isEmpty || plate.text.trim().isEmpty || vehicleYear == null) {
            return _fail(_t('Marque, modèle, année et immatriculation requis.'));
          }
        }
        if (!page('VEHICLE_REGISTRATION').sent) return _fail(_t('Ajoutez la carte grise du véhicule.'));
        if (!hasVehicle) {
          await widget.api.addVehicle(
            categoryId: categoryId!, brand: brand.text.trim(), model: model.text.trim(), year: vehicleYear!,
            plateNumber: plate.text.trim().toUpperCase(), seats: seats, baggageCapacity: baggage,
          );
          hasVehicle = true;
        }
        return true;
      default:
        return true;
    }
  }

  bool get _needsLegalName => !{'AUTO_ENTREPRENEUR', 'EI'}.contains(legalForm);

  bool _fail(String message) {
    setState(() => error = message);
    return false;
  }

  Future<void> next() async {
    if (busy) return;
    if (step == 0) {
      if (kind == null) return;
      setState(() { step = 1; error = null; });
      return;
    }
    if (step == independentSteps) return submit();
    setState(() { busy = true; error = null; });
    try {
      if (await saveStep() && mounted) {
        setState(() => step++);
        if (step == 6) _loadCategories();
      }
    } catch (e) {
      if (mounted) setState(() => error = VeyraErrorMessages.forException(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void back() {
    if (busy) return;
    if (step == 0 || (step == 1 && widget.resume)) return widget.onExit();
    setState(() { step--; error = null; });
  }

  Future<void> submit() async {
    if (!acceptCharter) return setState(() => error = _t('Acceptez les conditions d’utilisation et la charte chauffeur.'));
    setState(() { busy = true; error = null; });
    try {
      await widget.api.submitDossier();
      if (mounted) setState(() => step = independentSteps + 1);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['code'] == 'DOSSIER_INCOMPLETE') {
        setState(() {
          missing = (body['missing'] as List? ?? const []).map((x) => x.toString()).toList();
          error = _t('Votre dossier est incomplet :') + ' ' + missing.map(missingLabel).join(', ') + '.';
        });
      } else if (mounted) {
        setState(() => error = VeyraErrorMessages.forException(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static String missingLabel(String code) => _t(switch (code) {
        'BIRTH_DATE' => 'date de naissance',
        'IDENTITY' => 'pièce d’identité',
        'VTC_CARD' => 'carte VTC (photo)',
        'VTC' => 'numéro de carte VTC',
        'DRIVING_LICENSE' => 'permis (photo)',
        'LICENSE' => 'numéro de permis',
        'INSURANCE' => 'attestation d’assurance',
        'COMPANY' => 'entreprise',
        'VEHICLE' => 'véhicule',
        'VEHICLE_REGISTRATION' => 'carte grise',
        _ => code,
      });

  // ------------------------------------------------------------- widgets

  Widget field(String label, TextEditingController c, {String? hint, TextInputType? keyboard, bool required = true, bool enabled = true, Key? key, Widget? prefix, bool obscure = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        VeyraFieldLabel(label, required: required),
        TextField(key: key, controller: c, enabled: enabled, keyboardType: keyboard, obscureText: obscure,
            decoration: InputDecoration(hintText: hint, prefixIcon: prefix, prefixIconConstraints: const BoxConstraints())),
        const SizedBox(height: 14),
      ]);

  Widget dateField(String label, DateTime? value, VoidCallback onTap, {Key? key}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        VeyraFieldLabel(label, required: true),
        InkWell(
          key: key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(VeyraRadius.md),
          child: InputDecorator(
            decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_today_outlined, size: 20)),
            child: Text(value == null ? 'jj/mm/aaaa' : display(value), style: TextStyle(color: value == null ? VeyraColors.textTertiary : VeyraColors.textPrimary)),
          ),
        ),
        const SizedBox(height: 14),
      ]);

  Widget dropdown<T>(String label, T? value, Map<T, String> items, ValueChanged<T?>? onChanged, {Key? key}) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        VeyraFieldLabel(label, required: true),
        DropdownButtonFormField<T>(
          key: key,
          initialValue: items.containsKey(value) ? value : null,
          isExpanded: true,
          items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: onChanged,
        ),
        const SizedBox(height: 14),
      ]);

  /// Recto / verso tile (boards B4-B6): tap to pick, check once sent.
  Widget uploadTile(String label, String type, {String? side, String? subtype, DateTime? expiresAt, Key? key}) {
    final p = page(type, side);
    final color = p.error != null ? VeyraColors.danger : p.sent ? VeyraColors.success : VeyraColors.accent;
    return InkWell(
      key: key,
      onTap: p.busy ? null : () => upload(type, side: side, subtype: subtype, expiresAt: expiresAt),
      borderRadius: BorderRadius.circular(VeyraRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        decoration: BoxDecoration(
          color: p.sent ? VeyraColors.successBackground : VeyraColors.surfaceMuted,
          borderRadius: BorderRadius.circular(VeyraRadius.md),
          border: Border.all(color: p.sent ? VeyraColors.success : VeyraColors.border),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          p.busy
              ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4))
              : Icon(p.sent ? Icons.check_circle : Icons.add_a_photo_outlined, color: color, size: 28),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: .4)),
          Text(p.sent ? _t('Envoyé') : _t('Ajouter'), style: TextStyle(color: color, fontSize: 12)),
          if (p.error != null) Text(p.error!, textAlign: TextAlign.center, style: const TextStyle(color: VeyraColors.danger, fontSize: 11)),
        ]),
      ),
    );
  }

  Widget rectoVerso(String type, {String? subtype, DateTime? expiresAt, bool verso = true}) => Row(children: [
        Expanded(child: uploadTile(_t('RECTO'), type, side: 'FRONT', subtype: subtype, expiresAt: expiresAt, key: ValueKey('$type-front'))),
        if (verso) ...[
          const SizedBox(width: 12),
          Expanded(child: uploadTile(_t('VERSO'), type, side: 'BACK', subtype: subtype, expiresAt: expiresAt, key: ValueKey('$type-back'))),
        ],
      ]);

  Widget choice({required bool selected, required IconData icon, required String title, String? text, required VoidCallback onTap, Key? key}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: selected ? VeyraColors.infoBackground : Colors.white,
          borderRadius: BorderRadius.circular(VeyraRadius.md),
          child: InkWell(
            key: key,
            onTap: onTap,
            borderRadius: BorderRadius.circular(VeyraRadius.md),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(VeyraRadius.md), border: Border.all(color: selected ? VeyraColors.accent : VeyraColors.border, width: selected ? 1.6 : 1)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: selected ? VeyraColors.accent : VeyraColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (text != null) ...[const SizedBox(height: 4), Text(text, style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 13))],
                ])),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? VeyraColors.accent : VeyraColors.textTertiary),
              ]),
            ),
          ),
        ),
      );

  Widget summaryRow(IconData icon, String title, String detail, int target, bool done) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: VeyraColors.primary),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(done ? Icons.check_circle : Icons.error_outline, size: 18, color: done ? VeyraColors.success : VeyraColors.warning),
            TextButton(onPressed: busy ? null : () => setState(() { step = target; error = null; if (target == 6) _loadCategories(); }), child: Text(_t('Modifier'))),
          ]),
        ),
      );

  List<Widget> body() {
    switch (step) {
      case 0:
        return [
          VeyraStepTitle(_t('Quel est votre statut ?')),
          const SizedBox(height: 20),
          choice(
            key: const ValueKey('kind-independent'),
            selected: kind == DriverKind.independent,
            icon: Icons.person_outline,
            title: _t('Chauffeur indépendant'),
            text: _t('Je suis propriétaire de mon véhicule et j’exerce en mon nom.'),
            onTap: () => setState(() => kind = DriverKind.independent),
          ),
          choice(
            key: const ValueKey('kind-affiliated'),
            selected: kind == DriverKind.affiliated,
            icon: Icons.business_outlined,
            title: _t('Chauffeur rattaché à une société'),
            text: _t('Je suis rattaché à une société VTC.'),
            onTap: () => setState(() => kind = DriverKind.affiliated),
          ),
          if (kind == DriverKind.affiliated)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _t('Le rattachement à une société se fait avec le code d’invitation de votre société. Cette inscription ouvrira avec les espaces société.'),
                style: const TextStyle(color: VeyraColors.textSecondary),
              ),
            ),
        ];
      case 1:
        return [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: VeyraStepTitle(_t('Vos informations'))),
            InkWell(
              onTap: accountCreated ? null : () async {
                final path = await widget.pickFile(imageOnly: true);
                if (path != null) setState(() => avatarPath = path);
              },
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 30,
                backgroundColor: VeyraColors.surfaceMuted,
                child: Icon(avatarPath == null ? Icons.add_a_photo_outlined : Icons.check, color: avatarPath == null ? VeyraColors.textSecondary : VeyraColors.success),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          field(_t('Prénom'), firstName, enabled: !accountCreated, key: const ValueKey('first-name')),
          field(_t('Nom'), lastName, enabled: !accountCreated, key: const ValueKey('last-name')),
          dateField(_t('Date de naissance'), birthDate, () async {
            final now = DateTime.now();
            final d = await pickDate(birthDate, first: DateTime(1900), last: DateTime(now.year - 18, now.month, now.day), initial: DateTime(now.year - 35));
            if (d != null) setState(() => birthDate = d);
          }, key: const ValueKey('birth-date')),
          field(_t('Téléphone'), phone, hint: '6 12 34 56 78', keyboard: TextInputType.phone, enabled: !accountCreated, prefix: const VeyraPhonePrefix(), key: const ValueKey('phone')),
          field(_t('E-mail'), email, hint: 'nom@exemple.fr', keyboard: TextInputType.emailAddress, enabled: !accountCreated, key: const ValueKey('email')),
          if (!accountCreated) ...[
            field(_t('Mot de passe'), password, obscure: true, key: const ValueKey('password')),
            SignupConsents(
              acceptTerms: acceptTerms, acceptPrivacy: acceptPrivacy, marketingOptIn: marketingOptIn, showErrors: consentErrors,
              onTerms: (v) => setState(() => acceptTerms = v),
              onPrivacy: (v) => setState(() => acceptPrivacy = v),
              onMarketing: (v) => setState(() => marketingOptIn = v),
            ),
          ],
        ];
      case 2:
        return [
          VeyraStepTitle(_t('Pièce d’identité')),
          const SizedBox(height: 16),
          for (final (code, label, icon) in const [
            ('ID_CARD', 'Carte nationale d’identité', Icons.badge_outlined),
            ('PASSPORT', 'Passeport', Icons.menu_book_outlined),
            ('RESIDENCE_PERMIT', 'Titre de séjour', Icons.credit_card_outlined),
          ])
            choice(key: ValueKey('id-$code'), selected: idType == code, icon: icon, title: _t(label), onTap: () => setState(() => idType = code)),
          const SizedBox(height: 8),
          rectoVerso('IDENTITY', subtype: idType, verso: idType != 'PASSPORT'),
        ];
      case 3:
        return [
          VeyraStepTitle(_t('Carte professionnelle VTC')),
          const SizedBox(height: 16),
          field(_t('Numéro de carte'), vtcCard, key: const ValueKey('vtc-card')),
          dateField(_t('Date de validité'), vtcExpiry, () async {
            final now = DateTime.now();
            final d = await pickDate(vtcExpiry, first: now, last: DateTime(now.year + 10), initial: DateTime(now.year + 1));
            if (d != null) setState(() => vtcExpiry = d);
          }, key: const ValueKey('vtc-expiry')),
          rectoVerso('VTC_CARD', expiresAt: vtcExpiry),
        ];
      case 4:
        return [
          VeyraStepTitle(_t('Permis de conduire')),
          const SizedBox(height: 16),
          field(_t('Numéro de permis'), licenseNumber, key: const ValueKey('license-number')),
          dropdown<String>(_t('Catégorie'), licenseCategory, const {'B': 'B', 'BE': 'BE', 'C1': 'C1', 'D1': 'D1', 'D': 'D'}, (v) => setState(() => licenseCategory = v ?? 'B')),
          dateField(_t('Date de validité'), licenseExpiry, () async {
            final now = DateTime.now();
            final d = await pickDate(licenseExpiry, first: now, last: DateTime(now.year + 20), initial: DateTime(now.year + 5));
            if (d != null) setState(() => licenseExpiry = d);
          }, key: const ValueKey('license-expiry')),
          uploadTile(_t('PERMIS'), 'DRIVING_LICENSE', side: 'FRONT', expiresAt: licenseExpiry, key: const ValueKey('DRIVING_LICENSE-front')),
        ];
      case 5:
        return [
          VeyraStepTitle(_t('Votre entreprise')),
          const SizedBox(height: 16),
          dropdown<String>(_t('Statut juridique'), legalForm, {for (final e in legalForms.entries) e.key: _t(e.value)}, (v) => setState(() => legalForm = v ?? legalForm)),
          if (_needsLegalName) field(_t('Raison sociale'), legalName, key: const ValueKey('legal-name')),
          field(_t('SIREN/SIRET'), sirenSiret, keyboard: TextInputType.number, key: const ValueKey('siren')),
          field(_t('Adresse'), address, key: const ValueKey('address')),
          field(_t('Inscription au registre VTC (si applicable)'), revtc, required: false, key: const ValueKey('revtc')),
          VeyraFieldLabel(_t('Attestation d’assurance (RC professionnelle / véhicule)'), required: true),
          uploadTile(_t('ASSURANCE'), 'INSURANCE', key: const ValueKey('INSURANCE')),
        ];
      case 6:
        final years = {for (var y = DateTime.now().year + 1; y >= DateTime.now().year - 15; y--) y: '$y'};
        return [
          VeyraStepTitle(_t('Votre véhicule')),
          const SizedBox(height: 16),
          if (hasVehicle)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_t('Véhicule enregistré. Contactez le support pour modifier un véhicule soumis à validation.'), style: const TextStyle(color: VeyraColors.textSecondary)),
            ),
          dropdown<String>(_t('Catégorie'), categoryId, {for (final c in categories) c['id'].toString(): (c['display_name'] ?? c['code']).toString()}, hasVehicle ? null : (v) => setState(() => categoryId = v), key: const ValueKey('category')),
          field(_t('Marque'), brand, enabled: !hasVehicle, key: const ValueKey('brand')),
          field(_t('Modèle'), model, enabled: !hasVehicle, key: const ValueKey('model')),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: dropdown<int>(_t('Année'), vehicleYear, years, hasVehicle ? null : (v) => setState(() => vehicleYear = v), key: const ValueKey('year'))),
            const SizedBox(width: 12),
            Expanded(child: field(_t('Immatriculation'), plate, enabled: !hasVehicle, key: const ValueKey('plate'))),
          ]),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: dropdown<int>(_t('Nombre de places'), seats, {for (var i = 1; i <= 8; i++) i: '$i'}, hasVehicle ? null : (v) => setState(() => seats = v ?? seats))),
            const SizedBox(width: 12),
            Expanded(child: dropdown<int>(_t('Capacité bagages'), baggage, {for (var i = 0; i <= 10; i++) i: '$i'}, hasVehicle ? null : (v) => setState(() => baggage = v ?? baggage))),
          ]),
          VeyraFieldLabel(_t('Carte grise'), required: true),
          uploadTile(_t('CARTE GRISE'), 'VEHICLE_REGISTRATION', key: const ValueKey('VEHICLE_REGISTRATION')),
        ];
      default:
        final docsDone = page('IDENTITY', 'FRONT').sent && page('VTC_CARD', 'FRONT').sent && page('DRIVING_LICENSE', 'FRONT').sent;
        return [
          VeyraStepTitle(_t('Vérifiez vos informations')),
          const SizedBox(height: 12),
          summaryRow(Icons.person_outline, _t('Informations personnelles'), '${firstName.text} ${lastName.text} · ${display(birthDate)}', 1, birthDate != null),
          summaryRow(Icons.badge_outlined, _t('Documents'), _t('Identité, carte VTC, permis'), 2, docsDone),
          summaryRow(Icons.business_outlined, _t('Entreprise'), '${_t(legalForms[legalForm]!)} · ${sirenSiret.text}', 5, sirenSiret.text.isNotEmpty && page('INSURANCE').sent),
          summaryRow(Icons.directions_car_outlined, _t('Véhicule'), '${brand.text} ${model.text} · ${plate.text}', 6, hasVehicle && page('VEHICLE_REGISTRATION').sent),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey('charter'),
            value: acceptCharter,
            onChanged: (v) => setState(() => acceptCharter = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(_t('J’accepte les conditions d’utilisation et la charte chauffeur.'), style: const TextStyle(fontSize: 14)),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (step > independentSteps) {
      return Scaffold(
        body: VeyraSuccessView(
          icon: Icons.hourglass_top_rounded,
          confetti: false,
          title: _t('Dossier envoyé !'),
          text: _t('Votre dossier est en cours de vérification. Nous vous informerons par e-mail et par notification dès qu’il sera validé.'),
          actionLabel: _t('Voir mon statut'),
          onAction: widget.onSubmitted,
        ),
      );
    }
    final label = step == 0
        ? _t('Continuer')
        : step == independentSteps
            ? _t('Envoyer mon dossier')
            : _t('Continuer');
    final blocked = step == 0 && kind != DriverKind.independent;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) back(); },
      child: Scaffold(
        appBar: step == 0
            ? AppBar(leading: IconButton(tooltip: _t('Retour'), icon: const Icon(Icons.chevron_left, size: 30), onPressed: back))
            : VeyraStepProgress(step: step, total: independentSteps, onBack: back),
        body: busy && step == 1 && widget.resume && firstName.text.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 24), children: [
                ...body(),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: VeyraColors.danger))),
              ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: FilledButton(
              onPressed: busy || blocked ? null : next,
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                  : Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

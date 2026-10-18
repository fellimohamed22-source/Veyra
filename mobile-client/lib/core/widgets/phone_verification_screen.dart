import 'package:flutter/material.dart';
import '../../app_locale.dart';
import 'dart:async';
import '../../app/theme.dart';
import '../formatters/error_messages.dart';
import 'auth_ui.dart';

/// « Vérifiez votre numéro » (CL-AUTH-05, maquette 08-A panneau 5 ; DEC-07).
/// Le code est envoyé et vérifié par Firebase Phone Auth ; le serveur ne
/// fait confiance qu'au jeton Firebase obtenu après saisie du bon code.
/// Les appels Firebase et API sont injectés pour pouvoir tester l'écran.
class PhoneVerificationScreen extends StatefulWidget {
  final String initialPhone;
  /// Sends the SMS; returns the verification id, or null when the device
  /// verified the number by itself (Android auto-retrieval).
  final Future<String?> Function(String e164) sendCode;
  /// Confirms the 6-digit code and returns a Firebase ID token.
  final Future<String> Function(String? verificationId, String code) confirm;
  /// Sends the ID token to VEYRA.
  final Future<void> Function(String idToken) submit;
  final VoidCallback onDone;
  final VoidCallback onLater;

  const PhoneVerificationScreen({
    required this.initialPhone,
    required this.sendCode,
    required this.confirm,
    required this.submit,
    required this.onDone,
    required this.onLater,
    super.key,
  });

  /// French numbers typed as 06… become +336… (service in France first,
  /// DEC-06); numbers already in international format are kept.
  static String? toE164(String input) {
    final digits = input.replaceAll(RegExp(r'[\s.\-()]'), '');
    if (RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(digits)) return digits;
    if (RegExp(r'^0[1-9]\d{8}$').hasMatch(digits)) return '+33${digits.substring(1)}';
    return null;
  }

  @override
  State<PhoneVerificationScreen> createState() => _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  late final phone = TextEditingController(text: widget.initialPhone);
  final code = TextEditingController();
  String? verificationId;
  bool codeSent = false;
  bool busy = false;
  String? error;
  int resendIn = 0;
  Timer? resendTimer;

  @override
  void initState() {
    super.initState();
    // Board 08 A5: the code is sent as soon as the screen opens when the
    // number given at signup is valid.
    if (PhoneVerificationScreen.toE164(widget.initialPhone) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) send(); });
    }
  }

  @override
  void dispose() {
    resendTimer?.cancel();
    phone.dispose();
    code.dispose();
    super.dispose();
  }

  void startResendCountdown() {
    resendTimer?.cancel();
    setState(() => resendIn = 60);
    resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => resendIn--);
      if (resendIn <= 0) timer.cancel();
    });
  }

  Future<void> send() async {
    final e164 = PhoneVerificationScreen.toE164(phone.text);
    if (e164 == null) {
      setState(() => error = AppLocale.t('Numéro invalide. Exemple : 06 12 34 56 78 ou +33 6 12 34 56 78.'));
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      verificationId = await widget.sendCode(e164);
      if (verificationId == null) {
        // Android verified the number by itself: no code to type.
        await widget.submit(await widget.confirm(null, ''));
        if (mounted) widget.onDone();
        return;
      }
      if (mounted) {
        setState(() => codeSent = true);
        startResendCountdown();
      }
    } catch (e) {
      if (mounted) setState(() => error = AppLocale.t('Envoi du code impossible. Vérifiez le numéro puis réessayez.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (code.text.trim().length != 6) {
      setState(() => error = AppLocale.t('Le code contient 6 chiffres.'));
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final token = await widget.confirm(verificationId, code.text.trim());
      await widget.submit(token);
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) setState(() => error = VeyraErrorMessages.isOffline(e) ? AppLocale.t('Connexion indisponible. Réessayez.') : AppLocale.t('Code incorrect ou expiré.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// "+33612345678" -> "+33 6 12 34 56 78" as on the board.
  static String display(String e164) {
    final m = RegExp(r'^\+33(\d)(\d{2})(\d{2})(\d{2})(\d{2})$').firstMatch(e164);
    return m == null ? e164 : '+33 ${m[1]} ${m[2]} ${m[3]} ${m[4]} ${m[5]}';
  }

  @override
  Widget build(BuildContext context) {
    final e164 = PhoneVerificationScreen.toE164(phone.text) ?? phone.text;
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), children: [
          const Icon(Icons.mobile_friendly_outlined, size: 56, color: VeyraColors.accent),
          const SizedBox(height: 16),
          Text(AppLocale.t('Vérifiez votre numéro de téléphone'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (codeSent) ...[
            Text(AppLocale.t('Nous avons envoyé un code à'), textAlign: TextAlign.center, style: const TextStyle(color: VeyraColors.textSecondary)),
            const SizedBox(height: 4),
            Text(display(e164), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 24),
            VeyraCodeBoxes(controller: code, enabled: !busy),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: busy || resendIn > 0 ? null : send,
                child: Text(resendIn > 0 ? '${AppLocale.t('Renvoyer le code')} (${resendIn}s)' : AppLocale.t('Renvoyer le code')),
              ),
            ),
          ] else ...[
            Text(AppLocale.t('Nous allons vous envoyer un code par SMS pour confirmer votre numéro.'), textAlign: TextAlign.center, style: const TextStyle(color: VeyraColors.textSecondary)),
            const SizedBox(height: 20),
            VeyraFieldLabel(AppLocale.t('Téléphone'), required: true),
            TextField(
              key: const ValueKey('phone-field'),
              controller: phone,
              enabled: !busy,
              keyboardType: TextInputType.phone,
            ),
          ],
          if (error != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: VeyraColors.danger))),
          const SizedBox(height: 8),
          Center(child: TextButton(onPressed: busy ? null : widget.onLater, child: Text(AppLocale.t('Vérifier plus tard')))),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: FilledButton(
            onPressed: busy ? null : (codeSent ? verify : send),
            child: Text(codeSent ? AppLocale.t('Valider') : AppLocale.t('Envoyer le code')),
          ),
        ),
      ),
    );
  }
}

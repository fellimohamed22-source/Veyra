import 'package:flutter/material.dart';
import '../../app_locale.dart';
import '../formatters/error_messages.dart';

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

  @override
  void dispose() {
    phone.dispose();
    code.dispose();
    super.dispose();
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
      if (mounted) setState(() => codeSent = true);
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppLocale.t('Vérifiez votre numéro'))),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.sms_outlined, size: 48),
            const SizedBox(height: 12),
            Text(
              codeSent
                  ? AppLocale.t('Nous avons envoyé un code à 6 chiffres par SMS.')
                  : AppLocale.t('Nous allons vous envoyer un code par SMS pour confirmer votre numéro.'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              key: const ValueKey('phone-field'),
              controller: phone,
              enabled: !codeSent && !busy,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: AppLocale.t('Téléphone')),
            ),
            if (codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('code-field'),
                controller: code,
                enabled: !busy,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(labelText: AppLocale.t('Code reçu')),
              ),
            ],
            if (error != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : (codeSent ? verify : send),
              child: Text(codeSent ? AppLocale.t('Valider') : AppLocale.t('Envoyer le code')),
            ),
            if (codeSent)
              TextButton(onPressed: busy ? null : send, child: Text(AppLocale.t('Renvoyer le code'))),
            TextButton(onPressed: busy ? null : widget.onLater, child: Text(AppLocale.t('Vérifier plus tard'))),
          ]),
        ),
      );
}

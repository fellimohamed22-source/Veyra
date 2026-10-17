import 'package:flutter/material.dart';
import '../../app_locale.dart';

/// Consentements d'inscription (CL-AUTH / RGPD) : CGU et politique de
/// confidentialité obligatoires, communications marketing facultatives,
/// distinctes et jamais pré-cochées. Le serveur refuse l'inscription sans
/// les deux acceptations obligatoires (CONSENT_REQUIRED).
class SignupConsents extends StatelessWidget {
  final bool acceptTerms;
  final bool acceptPrivacy;
  final bool marketingOptIn;
  final bool showErrors;
  final ValueChanged<bool> onTerms;
  final ValueChanged<bool> onPrivacy;
  final ValueChanged<bool> onMarketing;

  const SignupConsents({
    required this.acceptTerms,
    required this.acceptPrivacy,
    required this.marketingOptIn,
    required this.showErrors,
    required this.onTerms,
    required this.onPrivacy,
    required this.onMarketing,
    super.key,
  });

  static bool mandatoryAccepted(bool terms, bool privacy) => terms && privacy;

  Widget _tile(BuildContext context, {required bool value, required String label, required ValueChanged<bool> onChanged, bool required = false}) {
    final missing = required && showErrors && !value;
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: missing
          ? Text(AppLocale.t('Acceptation obligatoire'), style: TextStyle(color: Theme.of(context).colorScheme.error))
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _tile(context, value: acceptTerms, label: AppLocale.t("J'accepte les conditions générales d'utilisation"), onChanged: onTerms, required: true),
      _tile(context, value: acceptPrivacy, label: AppLocale.t("J'accepte la politique de confidentialité"), onChanged: onPrivacy, required: true),
      _tile(context, value: marketingOptIn, label: AppLocale.t('Je souhaite recevoir les communications de VEYRA (facultatif)'), onChanged: onMarketing),
    ]);
  }
}

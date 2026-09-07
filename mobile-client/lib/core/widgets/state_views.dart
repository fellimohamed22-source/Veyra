import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';
import '../formatters/error_messages.dart';

/// États obligatoires par écran selon le kit (section "États
/// obligatoires" de chaque fiche) : LOADING, EMPTY, ERROR, OFFLINE,
/// DISABLED. Ce fichier centralise les 4 premiers ; DISABLED se gère au
/// niveau de chaque widget interactif (ex: VeyraPrimaryButton.onPressed
/// = null).

class VeyraLoadingView extends StatelessWidget {
  final String? label;
  const VeyraLoadingView({this.label, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: VeyraColors.primary),
          if (label != null) ...[
            const SizedBox(height: VeyraSpacing.lg),
            Text(label!, style: const TextStyle(color: VeyraColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

class VeyraEmptyView extends StatelessWidget {
  final String message;
  final IconData icon;
  const VeyraEmptyView({required this.message, this.icon = Icons.inbox_outlined, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VeyraSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: VeyraColors.textTertiary),
            const SizedBox(height: VeyraSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

/// [errorCode] : le code backend si connu (jamais affiché tel quel —
/// passé à VeyraErrorMessages.forCode pour traduction). [onRetry] :
/// jamais null en pratique pour un écran ERROR selon le kit
/// ("action Réessayer" obligatoire).
class VeyraErrorView extends StatelessWidget {
  final String? errorCode;
  final String? customMessage;
  final VoidCallback? onRetry;

  const VeyraErrorView({this.errorCode, this.customMessage, this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    final message = customMessage ?? VeyraErrorMessages.forCode(errorCode);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VeyraSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: VeyraColors.danger),
            const SizedBox(height: VeyraSpacing.lg),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: VeyraColors.textPrimary)),
            if (onRetry != null) ...[
              const SizedBox(height: VeyraSpacing.lg),
              OutlinedButton(onPressed: onRetry, child: Text(AppLocale.t('Réessayer'))),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bannière offline persistante — "conserver les données déjà chargées"
/// (kit) : ce widget n'efface jamais le contenu, il s'affiche par-dessus
/// ou au-dessus, jamais à sa place.
class VeyraOfflineBanner extends StatelessWidget {
  final VoidCallback? onRetry;
  const VeyraOfflineBanner({this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: VeyraColors.neutralBackground,
      padding: const EdgeInsets.symmetric(horizontal: VeyraSpacing.lg, vertical: VeyraSpacing.sm),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, size: 18, color: VeyraColors.textSecondary),
          const SizedBox(width: VeyraSpacing.sm),
          Expanded(
            child: Text(VeyraErrorMessages.offline, style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 13)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text(AppLocale.t('Réessayer'))),
        ],
      ),
    );
  }
}

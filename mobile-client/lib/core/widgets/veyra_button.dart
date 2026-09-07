import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Bouton primaire avec état de chargement intégré. Le double-submit est
/// empêché structurellement : tant que [loading] est vrai, onPressed est
/// forcé à null, quel que soit ce que l'écran appelant transmet.
class VeyraPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const VeyraPrimaryButton({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: VeyraSpacing.sm)],
                Text(label),
              ],
            ),
    );
  }
}

class VeyraSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const VeyraSecondaryButton({required this.label, required this.onPressed, this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: icon != null ? Icon(icon, size: 20) : const SizedBox.shrink(),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: VeyraColors.primary),
        foregroundColor: VeyraColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(VeyraRadius.pill)),
      ),
    );
  }
}

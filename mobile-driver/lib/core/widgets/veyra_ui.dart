import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:latlong2/latlong.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';
import '../maps/veyra_map_marks.dart';
import '../maps/veyra_tiles.dart';

/// Composants visuels communs reproduisant les planches de maquettes
/// (en-tête « VEYRA », pied « Retour / Suivant », cartes, compteurs,
/// encarts). Tous les écrans du parcours les réutilisent pour garder la
/// même géométrie partout.

String _t(String fr) => AppLocale.t(fr);

/// Logotype « VEYRA » vectoriel (planches 01, 09, 11, 17), fichier SVG du
/// pack d'assets ; [size] garde l'encombrement de l'ancien logotype texte.
/// Indépendant de la taille de texte choisie par l'utilisateur.
class VeyraWordmark extends StatelessWidget {
  final double size;
  final Color color;
  const VeyraWordmark({this.size = 22, this.color = VeyraColors.primary, super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Veyra',
        image: true,
        child: SvgPicture.asset('assets/branding/veyra_wordmark_navy.svg',
            height: size * 0.78, colorFilter: ColorFilter.mode(color, BlendMode.srcIn), excludeFromSemantics: true),
      );
}

/// En-tête des parcours : retour à gauche, logotype centré.
class VeyraFlowHeader extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback? onBack;
  final Widget? trailing;
  const VeyraFlowHeader({this.onBack, this.trailing, super.key});
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Stack(alignment: Alignment.center, children: [
            const VeyraWordmark(),
            Positioned(
              left: 4,
              child: IconButton(
                tooltip: _t('Retour'),
                icon: const Icon(Icons.chevron_left, size: 30, color: VeyraColors.textPrimary),
                onPressed: onBack ?? () => Navigator.maybePop(context),
              ),
            ),
            if (trailing != null) Positioned(right: 4, child: trailing!),
          ]),
        ),
      );
}

/// Pied de parcours : « ← Retour » (contour) + action principale marine.
class VeyraFlowFooter extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final String? nextLabel;
  final IconData? nextIcon;
  final bool trailingArrow;
  final bool loading;
  const VeyraFlowFooter({this.onBack, required this.onNext, this.nextLabel, this.nextIcon, this.trailingArrow = true, this.loading = false, super.key});
  @override
  Widget build(BuildContext context) {
    final next = FilledButton(
      onPressed: loading ? null : onNext,
      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
      child: loading
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
          // One line as on the boards; shrinks rather than wraps.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (nextIcon != null) ...[Icon(nextIcon, size: 20), const SizedBox(width: 8)],
                Text(nextLabel ?? _t('Suivant')),
                if (trailingArrow && nextIcon == null) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward, size: 20)],
              ]),
            ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: onBack == null
            ? next
            : Row(children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: loading ? null : onBack,
                    icon: const Icon(Icons.arrow_back, size: 20),
                    label: Text(_t('Retour')),
                    style: OutlinedButton.styleFrom(foregroundColor: VeyraColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: next),
              ]),
      ),
    );
  }
}

enum VeyraTone { info, warning, danger, success }

/// Encart coloré (info bleue, avertissement ambré, erreur rouge).
class VeyraBanner extends StatelessWidget {
  final String? title;
  final String text;
  final VeyraTone tone;
  const VeyraBanner({this.title, required this.text, this.tone = VeyraTone.info, super.key});
  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (tone) {
      VeyraTone.info => (VeyraColors.infoBackground, VeyraColors.accent, Icons.info_outline),
      VeyraTone.warning => (VeyraColors.warningBackground, VeyraColors.warning, Icons.info_outline),
      VeyraTone.danger => (VeyraColors.dangerBackground, VeyraColors.danger, Icons.error),
      VeyraTone.success => (VeyraColors.successBackground, VeyraColors.success, Icons.check_circle_outline),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(VeyraRadius.md)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (title != null) Text(title!, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
            if (title != null) const SizedBox(height: 2),
            Text(text, style: TextStyle(color: tone == VeyraTone.danger ? VeyraColors.textPrimary : fg, fontSize: 13, height: 1.35, fontWeight: FontWeight.w500)),
          ]),
        ),
      ]),
    );
  }
}

/// Grand titre d'étape (« Où partez-vous ? »).
class VeyraStepTitle extends StatelessWidget {
  final String text;
  final String? suffix;
  final String? subtitle;
  const VeyraStepTitle(this.text, {this.suffix, this.subtitle, super.key});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          TextSpan(text: text, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: VeyraColors.textPrimary, letterSpacing: -0.3)),
          if (suffix != null) TextSpan(text: ' $suffix', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: VeyraColors.textSecondary)),
        ])),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: const TextStyle(fontSize: 14, color: VeyraColors.textSecondary, height: 1.4)),
        ],
      ]);
}

class VeyraSectionLabel extends StatelessWidget {
  final String text;
  final Widget? action;
  const VeyraSectionLabel(this.text, {this.action, super.key});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: VeyraColors.textPrimary))),
        if (action != null) action!,
      ]);
}

/// Lien « Modifier » bleu des récapitulatifs.
class VeyraEditLink extends StatelessWidget {
  final VoidCallback onTap;
  const VeyraEditLink({required this.onTap, super.key});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(_t('Modifier'),
              style: const TextStyle(color: VeyraColors.accent, fontWeight: FontWeight.w600, fontSize: 14, decoration: TextDecoration.underline, decorationColor: VeyraColors.accent)),
        ),
      );
}

/// Ligne cliquable grise (« Utiliser ma position actuelle ») ou blanche
/// avec valeur et chevron (« Date — Sam. 18 oct. 2025 »).
class VeyraTapRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool muted;
  final bool chevron;
  final Widget? trailing;
  const VeyraTapRow({required this.icon, required this.label, this.value, this.onTap, this.muted = false, this.chevron = false, this.trailing, super.key});
  @override
  Widget build(BuildContext context) => Material(
        color: muted ? VeyraColors.surfaceMuted : Colors.white,
        borderRadius: BorderRadius.circular(VeyraRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(VeyraRadius.md),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: muted ? null : BoxDecoration(borderRadius: BorderRadius.circular(VeyraRadius.md), border: Border.all(color: VeyraColors.border)),
            child: Row(children: [
              Icon(icon, size: 22, color: VeyraColors.textPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: value == null
                    ? Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: VeyraColors.textPrimary))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(label, style: const TextStyle(fontSize: 12, color: VeyraColors.textSecondary, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(value!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: VeyraColors.textPrimary)),
                      ]),
              ),
              if (trailing != null) trailing!,
              if (chevron) const Icon(Icons.chevron_right, color: VeyraColors.textPrimary),
            ]),
          ),
        ),
      );
}

/// Compteur « 👤  2   (−) (+) » (planches 01, 09).
class VeyraCounterRow extends StatelessWidget {
  final IconData icon;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final String? semanticLabel;
  const VeyraCounterRow({required this.icon, required this.value, required this.min, required this.max, required this.onChanged, this.semanticLabel, super.key});
  Widget _btn(IconData i, VoidCallback? onTap, String tooltip) => Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 26,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: VeyraColors.surfaceMuted, border: Border.all(color: VeyraColors.border)),
            child: Icon(i, size: 20, color: onTap == null ? VeyraColors.textTertiary : VeyraColors.textPrimary),
          ),
        ),
      );
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(VeyraRadius.md), border: Border.all(color: VeyraColors.border)),
        child: Row(children: [
          Icon(icon, size: 24, color: VeyraColors.textPrimary),
          const SizedBox(width: 14),
          Expanded(child: Text('$value', semanticsLabel: semanticLabel == null ? null : '$semanticLabel : $value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          _btn(Icons.remove, value > min ? () => onChanged(value - 1) : null, _t('Diminuer')),
          const SizedBox(width: 14),
          _btn(Icons.add, value < max ? () => onChanged(value + 1) : null, _t('Augmenter')),
        ]),
      );
}

/// Carte sélectionnable (catégorie de véhicule, mode de paiement).
class VeyraSelectableCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  const VeyraSelectableCard({required this.selected, required this.onTap, required this.child, super.key});
  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? VeyraColors.infoBackground : Colors.white,
          borderRadius: BorderRadius.circular(VeyraRadius.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(VeyraRadius.lg),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VeyraRadius.lg),
                border: Border.all(color: selected ? VeyraColors.accent : VeyraColors.border, width: selected ? 1.6 : 1),
              ),
              child: Row(children: [
                Expanded(child: child),
                const SizedBox(width: 8),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? VeyraColors.accent : VeyraColors.textTertiary),
              ]),
            ),
          ),
        ),
      );
}

/// Ligne de suggestion d'adresse (icône, titre, sous-titre).
class VeyraPlaceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool highlighted;
  const VeyraPlaceTile({required this.icon, required this.title, this.subtitle, required this.onTap, this.highlighted = false, super.key});
  @override
  Widget build(BuildContext context) => Material(
        color: highlighted ? VeyraColors.infoBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(VeyraRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(VeyraRadius.sm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(children: [
              Icon(icon, size: 22, color: highlighted ? VeyraColors.accent : VeyraColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: VeyraColors.textPrimary)),
                  if (subtitle != null && subtitle!.isNotEmpty) Text(subtitle!, style: const TextStyle(fontSize: 13, color: VeyraColors.textSecondary)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// Départ (point bleu) relié en pointillé à l'arrivée (épingle rouge).
class VeyraRoutePoints extends StatelessWidget {
  final String pickupTitle;
  final String? pickupSubtitle;
  final String dropoffTitle;
  final String? dropoffSubtitle;
  const VeyraRoutePoints({required this.pickupTitle, this.pickupSubtitle, required this.dropoffTitle, this.dropoffSubtitle, super.key});
  Widget _line(String title, String? sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: VeyraColors.textPrimary)),
        if (sub != null && sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 13, color: VeyraColors.textSecondary)),
      ]);
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 22,
            child: Column(children: [
              const SizedBox(height: 3),
              const Icon(Icons.location_on, size: 18, color: VeyraColors.accent),
              Expanded(child: CustomPaint(painter: _DashPainter(), child: const SizedBox(width: 2))),
              const Icon(Icons.location_on, size: 18, color: VeyraColors.pinRed),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _line(pickupTitle, pickupSubtitle),
              const SizedBox(height: 14),
              _line(dropoffTitle, dropoffSubtitle),
            ]),
          ),
        ]),
      );
}

class _DashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = VeyraColors.accent
      ..strokeWidth = 1.6;
    for (double y = 2; y < size.height - 2; y += 6) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, y + 3), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Tiles are fetched from the network: disabled under `flutter test`
/// (where HTTP is refused) so widget tests and screenshots stay offline.
final bool veyraMapTilesEnabled = !Platform.environment.containsKey('FLUTTER_TEST');

/// Carte d'aperçu arrondie : départ, arrivée et tracé si connus.
class VeyraRouteMap extends StatelessWidget {
  final LatLng? pickup;
  final LatLng? dropoff;
  final List<LatLng> route;
  final double height;
  final bool interactive;
  final void Function(LatLng point)? onTap;
  /// Place names written next to the marks (boards 01 P5, 04, 12 P3).
  final String? pickupLabel;
  final String? dropoffLabel;
  /// Car on the route (board 01 P5 recap) and duration bubble.
  final LatLng? car;
  final double carHeading;
  final String? etaText;
  final double radius;
  const VeyraRouteMap({this.pickup, this.dropoff, this.route = const [], this.height = 180, this.interactive = false, this.onTap,
      this.pickupLabel, this.dropoffLabel, this.car, this.carHeading = 0, this.etaText, this.radius = VeyraRadius.lg, super.key});
  @override
  Widget build(BuildContext context) {
    final points = [if (pickup != null) pickup!, if (dropoff != null) dropoff!, ...route];
    final center = points.isEmpty ? const LatLng(48.8566, 2.3522) : points.first;
    final fit = points.length >= 2 ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.fromLTRB(40, 48, 96, 28)) : null;
    final bubble = etaText == null ? null : VeyraMapMarks.midpoint(route.length >= 2 ? route : [if (pickup != null) pickup!, if (dropoff != null) dropoff!]);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Positioned.fill(child: Container(color: const Color(0xFFE9EEF3))),
          FlutterMap(
            options: MapOptions(
              initialCenter: center,
              initialZoom: points.isEmpty ? 11 : 14,
              initialCameraFit: fit,
              interactionOptions: InteractionOptions(flags: interactive ? InteractiveFlag.all & ~InteractiveFlag.rotate : InteractiveFlag.none),
              onTap: onTap == null ? null : (_, p) => onTap!(p),
            ),
            children: [
              VeyraTiles.layer('com.veyra.driver'),
              if (route.length >= 2) VeyraMapMarks.route(route),
              MarkerLayer(markers: [
                if (pickup != null) VeyraMapMarks.origin(pickup!, label: pickupLabel),
                if (dropoff != null) VeyraMapMarks.destination(dropoff!, label: dropoffLabel),
                if (bubble != null) VeyraMapMarks.eta(bubble, etaText!),
                if (car != null) VeyraMapMarks.car(car!, heading: carHeading),
              ]),
            ],
          ),
          VeyraTiles.attribution(),
        ]),
      ),
    );
  }
}

/// Bouton or des actions décisives (« Confirmer la réservation », M03).
class VeyraGoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const VeyraGoldButton({required this.label, required this.onPressed, this.icon, super.key});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null ? 0.55 : 1,
        child: Material(
          borderRadius: BorderRadius.circular(VeyraRadius.md),
          child: Ink(
            decoration: BoxDecoration(gradient: VeyraColors.goldGradient, borderRadius: BorderRadius.circular(VeyraRadius.md)),
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(VeyraRadius.md),
              child: SizedBox(
                height: 54,
                child: Center(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                    Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                    if (icon == null) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward, color: Colors.white, size: 20)],
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Vignette véhicule (planches 03, 05, 10, 12) : illustration vectorielle
/// d.une berline ou d.un van noir, en attendant des photos réelles validées.
class VeyraVehicleThumb extends StatelessWidget {
  final double width;
  final bool van;
  const VeyraVehicleThumb({this.width = 92, this.van = false, super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: width * 0.6,
        alignment: Alignment.center,
        child: SvgPicture.asset(van ? 'assets/images/vehicles/van.svg' : 'assets/images/vehicles/sedan.svg', width: width, fit: BoxFit.contain, excludeFromSemantics: true),
      );
}

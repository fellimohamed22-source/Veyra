import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app/theme.dart';
import 'veyra_ui.dart' show VeyraWordmark;

/// Chemins centralisés des images d'accueil (planche 08 A1 / B1).
///
/// Les fichiers attendus sont les photos ORIGINALES (Paris / tour Eiffel /
/// berline noire pour le client, chauffeur en costume près d'une berline
/// pour le chauffeur), sans texte ni élément d'interface incrusté : voir
/// assets/images/onboarding/README.md. Les recadrages de la planche de
/// maquettes ne conviennent pas (barre d'état, logo et textes incrustés,
/// 232 × 156 px). Sans photo, l'illustration vectorielle de la même scène
/// (même chemin en .svg) est affichée ; sans les deux, fond marine.
class VeyraAssets {
  static const welcomeClient = 'assets/images/onboarding/welcome_client.jpg';
  static const welcomeDriver = 'assets/images/onboarding/welcome_driver.jpg';

  static Set<String>? _bundled;

  /// True when [path] is packaged with the app.
  static Future<bool> available(String path) async {
    try {
      _bundled ??= (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets().toSet();
      return _bundled!.contains(path);
    } catch (_) {
      return false;
    }
  }
}

/// Bandeau photo d'accueil : mot-symbole VEYRA bleu nuit en haut, titre,
/// sélecteur de langue. Sans photo, fond marine et textes blancs.
class VeyraWelcomeHero extends StatefulWidget {
  final String asset;
  final String title;
  final String? subtitle;
  /// B1 places the title at the bottom of the photo, in white.
  final bool titleAtBottom;
  /// Focal point of the photo (Eiffel tower right, driver right…).
  final Alignment focal;
  final Widget Function(bool onPhoto) languages;
  const VeyraWelcomeHero({
    required this.asset,
    required this.title,
    this.subtitle,
    this.titleAtBottom = false,
    this.focal = Alignment.center,
    required this.languages,
    super.key,
  });
  @override
  State<VeyraWelcomeHero> createState() => _VeyraWelcomeHeroState();
}

class _VeyraWelcomeHeroState extends State<VeyraWelcomeHero> {
  /// Original photo when bundled, otherwise the vector illustration of the
  /// same scene (same path, .svg).
  late final Future<String?> source = () async {
    if (await VeyraAssets.available(widget.asset)) return widget.asset;
    final svg = widget.asset.replaceFirst(RegExp(r'.(jpg|jpeg|png|webp)$'), '.svg');
    return await VeyraAssets.available(svg) ? svg : null;
  }();
  // Text colours follow the photo only once its first frame is painted,
  // so the navy wordmark never sits on the navy fallback while decoding.
  bool painted = false;

  Widget _wordmark(Color color) => VeyraWordmark(size: 40, color: color);

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: source,
        builder: (context, s) {
          final path = s.data;
          final available = path != null;
          final vector = path?.endsWith('.svg') ?? false;
          if (vector && !painted) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => painted = true); });
          final photo = available && painted;
          // On the photo: navy wordmark over the sky (A1/B1); without it,
          // everything is white on the navy background.
          final top = photo ? VeyraColors.primary : Colors.white;
          final titleColor = photo && !widget.titleAtBottom ? VeyraColors.primary : Colors.white;
          final title = Column(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.title, textAlign: TextAlign.center, style: TextStyle(color: titleColor, fontSize: 22, fontWeight: FontWeight.w700)),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 4),
              Text(widget.subtitle!, textAlign: TextAlign.center, style: TextStyle(color: titleColor.withValues(alpha: .85), fontSize: 15)),
            ],
          ]);
          return Stack(fit: StackFit.expand, children: [
            const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0A2E57), VeyraColors.primary]))),
            if (vector)
              SvgPicture.asset(path!, fit: BoxFit.cover, alignment: widget.focal, excludeFromSemantics: true)
            else if (available)
              Image.asset(
                path,
                fit: BoxFit.cover,
                alignment: widget.focal,
                excludeFromSemantics: true,
                frameBuilder: (context, child, frame, _) {
                  if (frame != null && !painted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => painted = true); });
                  }
                  return child;
                },
              ),
            if (photo && widget.titleAtBottom)
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB3000000)]))),
            SafeArea(
              bottom: false,
              // Fills the hero on phones, scrolls instead of overflowing on
              // short screens (landscape, large text).
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 56),
                        child: Column(children: [
                          const Spacer(),
                          Semantics(label: 'VEYRA', child: ExcludeSemantics(child: _wordmark(top))),
                          if (!widget.titleAtBottom) ...[const SizedBox(height: 16), title],
                          const Spacer(flex: 2),
                          if (widget.titleAtBottom) ...[title, const SizedBox(height: 16)],
                          widget.languages(photo),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
}

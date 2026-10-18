import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../app_locale.dart';

String _t(String s) => AppLocale.t(s);

/// En-tête des parcours d'inscription (planche 08) : retour, barre de
/// progression à pastille et compteur « 1/3 ».
class VeyraStepProgress extends StatelessWidget implements PreferredSizeWidget {
  final int step;
  final int total;
  final VoidCallback? onBack;
  const VeyraStepProgress({required this.step, required this.total, this.onBack, super.key});
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            IconButton(
              tooltip: _t('Retour'),
              icon: const Icon(Icons.chevron_left, size: 30, color: VeyraColors.textPrimary),
              onPressed: onBack ?? () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LayoutBuilder(builder: (context, c) {
                  final ratio = total <= 1 ? 1.0 : (step - 1) / (total - 1);
                  final x = (c.maxWidth - 14) * ratio;
                  return SizedBox(
                    height: 14,
                    child: Stack(alignment: Alignment.centerLeft, children: [
                      Container(height: 4, decoration: BoxDecoration(color: VeyraColors.border, borderRadius: BorderRadius.circular(2))),
                      Container(width: x + 7, height: 4, decoration: BoxDecoration(color: VeyraColors.accent, borderRadius: BorderRadius.circular(2))),
                      Positioned(
                        left: x,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: VeyraColors.accent, width: 3)),
                        ),
                      ),
                    ]),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('$step/$total', style: const TextStyle(color: VeyraColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      );
}

/// Libellé au-dessus d'un champ (« Prénom * »).
class VeyraFieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const VeyraFieldLabel(this.text, {this.required = false, super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text, style: const TextStyle(fontWeight: FontWeight.w600, color: VeyraColors.textPrimary)),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: VeyraColors.danger, fontWeight: FontWeight.w700)),
        ])),
      );
}

/// Ligne de la liste de contrôle du mot de passe (planche 08 A3).
class VeyraCheckLine extends StatelessWidget {
  final bool ok;
  final String text;
  const VeyraCheckLine({required this.ok, required this.text, super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 18, color: ok ? VeyraColors.success : VeyraColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: ok ? VeyraColors.textPrimary : VeyraColors.textSecondary, fontSize: 13))),
        ]),
      );
}

/// Saisie d'un code à 6 chiffres affiché en cases (planche 08 A5). Le
/// vrai champ reste un TextField (accessibilité, collage, remplissage
/// automatique du SMS) dont le texte est masqué derrière les cases.
class VeyraCodeBoxes extends StatefulWidget {
  final TextEditingController controller;
  final int length;
  final bool enabled;
  final ValueChanged<String>? onCompleted;
  const VeyraCodeBoxes({required this.controller, this.length = 6, this.enabled = true, this.onCompleted, super.key});
  @override
  State<VeyraCodeBoxes> createState() => _VeyraCodeBoxesState();
}

class _VeyraCodeBoxesState extends State<VeyraCodeBoxes> {
  final focus = FocusNode();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
    if (widget.controller.text.length == widget.length) widget.onCompleted?.call(widget.controller.text);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    return GestureDetector(
      onTap: () => focus.requestFocus(),
      child: Stack(children: [
        // Invisible input covering the boxes.
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              key: const ValueKey('code-field'),
              controller: widget.controller,
              focusNode: focus,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: widget.length,
              showCursor: false,
              decoration: const InputDecoration(counterText: '', border: InputBorder.none),
            ),
          ),
        ),
        IgnorePointer(
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < widget.length; i++)
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 48),
                  height: 56,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(VeyraRadius.md),
                    border: Border.all(color: i == text.length && focus.hasFocus ? VeyraColors.accent : VeyraColors.border, width: i == text.length && focus.hasFocus ? 1.6 : 1),
                  ),
                  child: Text(i < text.length ? text[i] : '', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// « Compte créé » / « Dossier envoyé » : pastille, titre, texte, action.
class VeyraSuccessView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;
  final bool confetti;
  const VeyraSuccessView({this.icon = Icons.check, required this.title, required this.text, required this.actionLabel, required this.onAction, this.confetti = true, super.key});

  static const _dots = [
    (-110.0, -60.0, Color(0xFFE5342E)), (95.0, -75.0, Color(0xFF0C6CFD)), (-80.0, 50.0, Color(0xFFF5A623)),
    (115.0, 30.0, Color(0xFF2E7D4F)), (-125.0, -5.0, Color(0xFF7C4DFF)), (70.0, 70.0, Color(0xFFE5342E)),
    (-40.0, -90.0, Color(0xFF2E7D4F)), (40.0, -95.0, Color(0xFFF5A623)),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(children: [
            const Spacer(),
            SizedBox(
              width: 280,
              height: 200,
              child: Stack(alignment: Alignment.center, children: [
                if (confetti)
                  for (final (dx, dy, c) in _dots)
                    Transform.translate(offset: Offset(dx, dy), child: Container(width: 8, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)))),
                Container(
                  width: 104,
                  height: 104,
                  decoration: const BoxDecoration(color: VeyraColors.success, shape: BoxShape.circle),
                  child: Icon(icon, color: Colors.white, size: 60),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: VeyraColors.textSecondary, fontSize: 15, height: 1.4)),
            const Spacer(flex: 2),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: onAction, child: Text(actionLabel))),
          ]),
        ),
      );
}

/// Préfixe « 🇫🇷 +33 » du champ téléphone (service en France d'abord, DEC-06).
class VeyraPhonePrefix extends StatelessWidget {
  const VeyraPhonePrefix({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(left: 12, right: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('🇫🇷', style: TextStyle(fontSize: 18)),
          SizedBox(width: 6),
          Text('+33', style: TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}

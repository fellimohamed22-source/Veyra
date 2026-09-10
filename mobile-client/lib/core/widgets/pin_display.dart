import 'package:flutter/material.dart';
import '../../app/theme.dart';

/// Trouvé lors de l'étude UX/navigation : le PIN de démarrage de course
/// était affiché comme simple texte de bouton ("PIN : 0427"), avec la
/// même taille et le même contraste que n'importe quel autre libellé --
/// alors que c'est un code que le client doit souvent lire à voix haute
/// ou montrer à l'écran à un chauffeur qui approche, parfois dans la
/// rue, parfois sous stress. Chiffres larges, bien espacés, fond
/// contrasté -- pas de logique métier ici, uniquement de l'affichage
/// (le PIN reste récupéré et validé exclusivement côté serveur).
class VeyraPinDisplay extends StatelessWidget {
  final String pin;

  const VeyraPinDisplay({required this.pin, super.key});

  @override
  Widget build(BuildContext context) {
    final digits = pin.split('');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: VeyraColors.primaryDark,
        borderRadius: BorderRadius.circular(VeyraRadius.lg),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final d in digits)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 6),
              width: 44,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(VeyraRadius.sm),
              ),
              child: Text(
                d,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: VeyraColors.primaryDark,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

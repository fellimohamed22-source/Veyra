import 'package:flutter/material.dart';
import '../../app_locale.dart';

class VeyraPasswordDialog extends StatefulWidget {
  const VeyraPasswordDialog({super.key});
  @override
  State<VeyraPasswordDialog> createState() => _VeyraPasswordDialogState();
}

class _VeyraPasswordDialogState extends State<VeyraPasswordDialog> {
  final form = GlobalKey<FormState>();
  final current = TextEditingController(), next = TextEditingController();
  @override
  void dispose() {
    current.dispose();
    next.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(AppLocale.t('Modifier mon mot de passe')),
        content: SingleChildScrollView(
            child: Form(
                key: form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                      controller: current,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: AppLocale.t('Mot de passe actuel')),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? AppLocale.t('Mot de passe actuel requis.')
                              : null),
                  TextFormField(
                      controller: next,
                      obscureText: true,
                      decoration: InputDecoration(
                          labelText: AppLocale.t('Nouveau mot de passe')),
                      validator: (value) => value == null ||
                              value.trim().isEmpty ||
                              value.length < 10
                          ? AppLocale.t('10 caractères minimum.')
                          : null),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocale.t('Annuler'))),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: () {
                if (form.currentState!.validate())
                  Navigator.pop(context, (current.text, next.text));
              },
              child: Text(AppLocale.t('Enregistrer'))),
        ],
      );
}

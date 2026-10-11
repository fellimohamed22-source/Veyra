import 'package:flutter/material.dart';
import '../../app_locale.dart';

class VeyraProfileDialog extends StatefulWidget {
  final Map<String, dynamic> profile;
  const VeyraProfileDialog({required this.profile, super.key});
  @override
  State<VeyraProfileDialog> createState() => _VeyraProfileDialogState();
}

class _VeyraProfileDialogState extends State<VeyraProfileDialog> {
  final form = GlobalKey<FormState>();
  late final first =
      TextEditingController(text: '${widget.profile['first_name'] ?? ''}');
  late final last =
      TextEditingController(text: '${widget.profile['last_name'] ?? ''}');
  late final phone =
      TextEditingController(text: '${widget.profile['phone'] ?? ''}');
  @override
  void dispose() {
    first.dispose();
    last.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(AppLocale.t('Modifier mes informations')),
        content: SingleChildScrollView(
            child: Form(
                key: form,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                      controller: first,
                      maxLength: 100,
                      decoration:
                          InputDecoration(labelText: AppLocale.t('Prénom')),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? AppLocale.t('Prénom requis.')
                              : null),
                  TextFormField(
                      controller: last,
                      maxLength: 100,
                      decoration:
                          InputDecoration(labelText: AppLocale.t('Nom'))),
                  TextFormField(
                      controller: phone,
                      maxLength: 32,
                      keyboardType: TextInputType.phone,
                      decoration:
                          InputDecoration(labelText: AppLocale.t('Téléphone')),
                      validator: (value) =>
                          value == null || value.trim().length < 6
                              ? AppLocale.t(
                                  'Téléphone de 6 caractères minimum requis.')
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
                  Navigator.pop(context, (first.text, last.text, phone.text));
              },
              child: Text(AppLocale.t('Enregistrer'))),
        ],
      );
}

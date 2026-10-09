import 'package:flutter/material.dart';
import '../../app_locale.dart';
import '../formatters/error_messages.dart';
import 'state_views.dart';

class DriverDocuments extends StatelessWidget {
  final Future<List<dynamic>> documents;
  final VoidCallback onRetry;
  final ValueChanged<String>? onUpload;
  const DriverDocuments(
      {required this.documents,
      required this.onRetry,
      this.onUpload,
      super.key});

  static String label(String type) => AppLocale.t(const {
        'IDENTITY': 'Pièce d’identité',
        'VTC_CARD': 'Carte professionnelle VTC',
        'DRIVING_LICENSE': 'Permis de conduire',
        'INSURANCE': 'Assurance professionnelle / véhicule',
        'VEHICLE_REGISTRATION': 'Carte grise du véhicule',
      }[type] ??
      'Document chauffeur');

  static String status(String? code) => AppLocale.t(const {
        'SUBMITTED': 'En vérification',
        'APPROVED': 'Validé',
        'REJECTED': 'Refusé',
        'SUPERSEDED': 'Remplacé',
      }[code] ??
      'Statut indisponible');

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
        future: documents,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return VeyraErrorMessages.isOffline(snapshot.error!)
                ? VeyraOfflineBanner(onRetry: onRetry)
                : VeyraErrorView(
                    customMessage:
                        VeyraErrorMessages.forException(snapshot.error!),
                    onRetry: onRetry);
          }
          final rows = snapshot.data ?? [];
          if (rows.isEmpty)
            return Padding(
                padding: const EdgeInsets.all(12),
                child: Text(AppLocale.t(
                    'Aucun document envoyé. Complétez votre dossier chauffeur.')));
          return Column(
              children: rows.map((raw) {
            final doc = Map<String, dynamic>.from(raw as Map);
            final type = (doc['type'] ?? '').toString();
            return Card(
                child: ListTile(
              leading: const Icon(Icons.description),
              title: Text(label(type)),
              subtitle: Text(
                  '${doc['original_filename'] ?? ''} • ${status(doc['status']?.toString())}'),
              trailing: IconButton(
                  icon: const Icon(Icons.upload_file),
                  tooltip: AppLocale.t('Téléverser'),
                  onPressed: onUpload == null ? null : () => onUpload!(type)),
            ));
          }).toList());
        },
      );
}

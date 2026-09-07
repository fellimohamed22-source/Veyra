import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../formatters/status_labels.dart';

/// Reprend exactement le mapping statut -> couleur déjà en usage dans le
/// code existant (main.dart, avant ce lot), centralisé ici pour éviter
/// la duplication écran par écran.
Color _bookingStatusColor(String? status) {
  const map = {
    'OPEN_FOR_OFFERS': VeyraColors.warning,
    'OFFERS_RECEIVED': VeyraColors.warning,
    'CONFIRMED': VeyraColors.info,
    'DRIVER_EN_ROUTE': VeyraColors.info,
    'DRIVER_ARRIVED': VeyraColors.info,
    'IN_PROGRESS': VeyraColors.info,
    'COMPLETED': VeyraColors.success,
    'CLOSED': VeyraColors.success,
    'CANCELLED': VeyraColors.danger,
    'CANCELLED_BY_CLIENT': VeyraColors.danger,
    'CANCELLED_BY_DRIVER': VeyraColors.danger,
    'CUSTOMER_NO_SHOW': VeyraColors.danger,
    'EXPIRED': VeyraColors.neutral,
    'NO_OFFER': VeyraColors.neutral,
    'NO_DRIVER': VeyraColors.neutral,
  };
  return map[status] ?? VeyraColors.neutral;
}

class VeyraStatusBadge extends StatelessWidget {
  final String? status;

  const VeyraStatusBadge({required this.status, super.key});

  @override
  Widget build(BuildContext context) {
    final color = _bookingStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: VeyraSpacing.md, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(VeyraRadius.pill)),
      child: Text(
        VeyraStatusLabels.bookingStatus(status).toUpperCase(),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Reusable recent-destination section. The parent decides how a selected
/// destination populates the existing booking form; no automatic booking.
class RecentDestinationsSection extends StatelessWidget {
  const RecentDestinationsSection({
    super.key,
    required this.destinations,
    required this.onSelected,
    required this.onRemove,
    this.loading = false,
    this.error,
    this.onRetry,
  });
  final List<Map<String, dynamic>> destinations;
  final ValueChanged<Map<String, dynamic>> onSelected;
  final ValueChanged<String> onRemove;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (loading) return const Center(child: Padding(
      padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
    if (error != null) return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(error!, style: TextStyle(color: theme.colorScheme.error)),
        TextButton(onPressed: onRetry, child: const Text('Réessayer')),
      ],
    );
    if (destinations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Destinations récentes', style: theme.textTheme.titleMedium),
        ),
        ...destinations.map((destination) {
          final id = destination['id']?.toString() ?? '';
          final address = destination['address']?.toString() ?? '';
          return ListTile(
            leading: const Icon(Icons.history),
            title: Text(address, maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => onSelected(destination),
            trailing: IconButton(
              tooltip: 'Supprimer cette destination',
              icon: const Icon(Icons.close),
              onPressed: id.isEmpty ? null : () => onRemove(id),
            ),
          );
        }),
      ],
    );
  }
}

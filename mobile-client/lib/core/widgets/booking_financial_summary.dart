import 'package:flutter/material.dart';
import '../../app_locale.dart';
import '../formatters/money_formatter.dart';
import '../formatters/status_labels.dart';

class BookingFinancialSummary extends StatelessWidget {
  final Map<String, dynamic> booking;
  final String paymentLabel;
  const BookingFinancialSummary(
      {required this.booking, required this.paymentLabel, super.key});

  @override
  Widget build(BuildContext context) {
    final currency = (booking['currency'] ?? 'EUR').toString();
    Widget amount(String label, String key) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(spacing: 12, runSpacing: 4, children: [
            Text(AppLocale.t(label)),
            Text(
                VeyraMoneyFormatter.fromMinor(booking[key], currency: currency),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
        );
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppLocale.t('Récapitulatif financier'),
                  style: Theme.of(context).textTheme.titleMedium),
              if (booking['driver_net_amount_minor'] != null)
                amount('Prix chauffeur', 'driver_net_amount_minor'),
              if (booking['platform_commission_amount_minor'] != null)
                amount('Commission Veyra', 'platform_commission_amount_minor'),
              const Divider(),
              amount('Total client', 'customer_total_amount_minor'),
              Text(VeyraStatusLabels.paymentMethod(
                  booking['payment_method']?.toString())),
              if (booking['payment_method'] == 'ONLINE') Text(paymentLabel),
              if (booking['payment_method'] == 'CASH')
                Text(AppLocale.t('Règlement en espèces auprès du chauffeur.')),
            ])));
  }
}

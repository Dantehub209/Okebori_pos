import 'dart:math';
import 'package:intl/intl.dart';

class PricingRules {
  final double basePrice;
  final double baseWeightKg;
  final double pricePerExtraKg;
  final double fuelCostPerKm;

  /// VAT in percent, added on top of the price (0 = off).
  final double vatRate;

  const PricingRules({
    this.basePrice = 150.0,
    this.baseWeightKg = 5.0,
    this.pricePerExtraKg = 50.0,
    this.fuelCostPerKm = 30.0,
    this.vatRate = 0,
  });

  factory PricingRules.fromRow(Map<String, dynamic> row) => PricingRules(
        basePrice: (row['base_price'] as num).toDouble(),
        baseWeightKg: (row['base_weight_kg'] as num).toDouble(),
        pricePerExtraKg: (row['price_per_extra_kg'] as num).toDouble(),
        fuelCostPerKm: (row['fuel_cost_per_km'] as num).toDouble(),
        vatRate: (row['vat_rate'] as num?)?.toDouble() ?? 0,
      );
}

double _round2(double v) => double.parse(v.toStringAsFixed(2));

/// Mirrors quote_parcel in supabase/book_parcel.sql: prices exclude VAT; the customer pays
/// price + VAT in whole shillings rounded up, and the VAT is worked back from that total
/// so the eTIMS invoice adds up exactly (taxable + vat = total).
class Quote {
  final double baseRate;
  final double extraWeightKg;
  final double weightCharge;
  final double distanceKm;
  final double distanceCharge;
  final double vatRate;

  const Quote({
    required this.baseRate,
    required this.extraWeightKg,
    required this.weightCharge,
    required this.distanceKm,
    required this.distanceCharge,
    this.vatRate = 0,
  });

  double get net => _round2(baseRate + weightCharge + distanceCharge);
  double get total => _round2(net * (1 + vatRate / 100)).ceilToDouble();
  double get taxable => _round2(total / (1 + vatRate / 100));
  double get vat => _round2(total - taxable);
  double get rounding => _round2(taxable - net);
}

Quote calculateQuote(PricingRules rules, double weightKg, double distanceKm) {
  final extraKg = max(0.0, weightKg - rules.baseWeightKg);
  return Quote(
    baseRate: rules.basePrice,
    extraWeightKg: extraKg,
    weightCharge: extraKg * rules.pricePerExtraKg,
    distanceKm: distanceKm,
    distanceCharge: distanceKm * rules.fuelCostPerKm,
    vatRate: rules.vatRate,
  );
}

/// Straight-line distance between two GPS points (Haversine formula).
double distanceBetween(double lat1, double lon1, double lat2, double lon2) {
  const p = 0.017453292519943295; // Pi/180
  final a = 0.5 - cos((lat2 - lat1) * p) / 2 +
      cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
  return 12742 * asin(sqrt(a)); // 2 * Earth radius (6371 km)
}

/// 350 -> "350", 1250.5 -> "1,250.50"
String formatKsh(double amount) {
  final rounded = double.parse(amount.toStringAsFixed(2));
  return NumberFormat(rounded == rounded.roundToDouble() ? '#,##0' : '#,##0.00').format(rounded);
}

/// 0712345678, 712345678, +254 712 345 678 -> 254712345678; null if not a Kenyan mobile number.
/// Same rule as normalizePhone() in supabase/functions/mpesa-pay.
String? normalizeKenyanPhone(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('0')) {
    d = '254${d.substring(1)}';
  } else if (d.length == 9 && (d.startsWith('7') || d.startsWith('1'))) {
    d = '254$d';
  }
  return RegExp(r'^254(7|1)\d{8}$').hasMatch(d) ? d : null;
}

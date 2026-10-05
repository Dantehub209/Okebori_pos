import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:okebori_pos/services/pricing.dart';
import 'package:okebori_pos/services/receipt_service.dart';

void main() {
  test('VAT on top matches the server (quote_parcel) to the cent', () {
    // Same case as the SQL test: 2 kg, 136.65 km at 1.2/km, base 150, VAT 16%
    const rules = PricingRules(basePrice: 150, baseWeightKg: 5, pricePerExtraKg: 50, fuelCostPerKm: 1.2, vatRate: 16);
    final q = calculateQuote(rules, 2, 136.65);
    expect(q.net, 313.98);
    expect(q.total, 365);
    expect(q.taxable, 314.66);
    expect(q.vat, 50.34);
    expect(q.rounding, 0.68);
    expect(q.taxable + q.vat, closeTo(q.total, 0.001));
  });

  test('VAT off behaves exactly as before', () {
    const rules = PricingRules(basePrice: 150, baseWeightKg: 5, pricePerExtraKg: 50, fuelCostPerKm: 1.2);
    final q = calculateQuote(rules, 2, 136.65);
    expect(q.total, 314);
    expect(q.vat, 0);
    expect(q.taxable, 314);
  });

  test('receipt shows VAT, the eTIMS details, a simulation warning and a QR code', () {
    final bytes = ReceiptService.buildReceiptBytes(
      branchName: 'Nairobi CBD',
      bookingNumber: 'OKB-1',
      receiptNumber: 'RCT-1',
      senderName: 'Acme Ltd',
      senderPhone: '0733',
      receiverName: 'Bob',
      receiverPhone: '0744',
      destination: 'Nakuru',
      weight: 2,
      amount: 365,
      taxable: 314.66,
      vatRate: 16,
      vat: 50.34,
      paymentMethod: 'Cash',
      cashierName: 'Wanjiku',
      customerKraPin: 'P051234567X',
      printedAt: DateTime(2026, 10, 5, 10, 30),
      invoice: const {
        'mode': 'simulation',
        'status': 'signed',
        'invoice_number': 1,
        'kra_receipt_number': 'SIM-00000001',
        'kra_signature': 'ABCD-EFGH-IJKL-MNOP',
        'kra_sdc_id': 'SIMULATION',
        'qr_text': 'SIMULATION|P051234567X|00|ABCD',
      },
    );
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text, contains('VAT 16%                    50.34'));
    expect(text, contains('TOTAL KES                 365.00'));
    expect(text, contains('CUSTOMER PIN: P051234567X'));
    expect(text, contains('*** SIMULATION ***'));
    expect(text, contains('KRA RECEIPT: SIM-00000001'));
    // ESC/POS store-QR command followed by the data
    final qr = ReceiptService.qrCode('SIMULATION|P051234567X|00|ABCD');
    expect(String.fromCharCodes(bytes), contains(String.fromCharCodes(qr)));
  });

  test('no QR and a "being sent" note while KRA has not signed yet', () {
    final bytes = ReceiptService.buildReceiptBytes(
      branchName: 'B', bookingNumber: 'OKB-2', receiptNumber: 'RCT-2', senderName: 'S', senderPhone: '1',
      receiverName: 'R', receiverPhone: '2', destination: 'D', weight: 1, amount: 100, paymentMethod: 'Cash',
      cashierName: 'C', printedAt: DateTime(2026),
      invoice: const {'mode': 'production', 'status': 'queued', 'invoice_number': 7},
    );
    final text = latin1.decode(bytes, allowInvalid: true);
    expect(text, contains('Being sent to KRA (eTIMS)'));
    expect(text, isNot(contains('SIMULATION')));
    expect(String.fromCharCodes(bytes), isNot(contains(String.fromCharCodes([0x1D, 0x28, 0x6B])))); // no GS ( k QR command
  });
}

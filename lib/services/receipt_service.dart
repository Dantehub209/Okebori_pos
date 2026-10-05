import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ReceiptService {
  static Future<bool> printReceipt({
    required String macAddress,
    required String branchName,
    required String bookingNumber,
    required String receiptNumber,
    required String senderName,
    required String senderPhone,
    required String receiverName,
    required String receiverPhone,
    required String destination,
    required double weight,
    required double amount,
    required String paymentMethod,
    required String cashierName,
    double? taxable,
    double vatRate = 0,
    double vat = 0,
    String customerKraPin = '',
    Map<String, dynamic>? invoice, // eTIMS invoice row, if eTIMS is on
  }) async {
    try {
      final bool connectionResult = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      if (!connectionResult) return false;

      final bytes = buildReceiptBytes(
        branchName: branchName,
        bookingNumber: bookingNumber,
        receiptNumber: receiptNumber,
        senderName: senderName,
        senderPhone: senderPhone,
        receiverName: receiverName,
        receiverPhone: receiverPhone,
        destination: destination,
        weight: weight,
        amount: amount,
        paymentMethod: paymentMethod,
        cashierName: cashierName,
        taxable: taxable,
        vatRate: vatRate,
        vat: vat,
        customerKraPin: customerKraPin,
        invoice: invoice,
        printedAt: DateTime.now(),
      );
      final bool printResult = await PrintBluetoothThermal.writeBytes(bytes);
      await PrintBluetoothThermal.disconnect;
      return printResult;
    } catch (e) {
      debugPrint('Print Error: $e');
      return false;
    }
  }

  /// The bytes sent to a 58 mm ESC/POS printer (32 characters per line).
  @visibleForTesting
  static List<int> buildReceiptBytes({
    required String branchName,
    required String bookingNumber,
    required String receiptNumber,
    required String senderName,
    required String senderPhone,
    required String receiverName,
    required String receiverPhone,
    required String destination,
    required double weight,
    required double amount,
    required String paymentMethod,
    required String cashierName,
    required DateTime printedAt,
    double? taxable,
    double vatRate = 0,
    double vat = 0,
    String customerKraPin = '',
    Map<String, dynamic>? invoice,
  }) {
    const line = '--------------------------------';
    String money(double v) => v.toStringAsFixed(2);
    String row(String label, String value) {
      final gap = 32 - label.length - value.length;
      return gap > 0 ? '$label${' ' * gap}$value' : '$label $value';
    }

    final simulation = invoice?['mode'] == 'simulation';
    final top = [
      'OKEBORI COURIER SERVICES',
      branchName,
      'Tel: +254 700 000 000',
      line,
      'BOOKING NO: $bookingNumber',
      'RECEIPT NO: $receiptNumber',
      'DATE: ${printedAt.toString().substring(0, 16)}',
      if (customerKraPin.isNotEmpty) 'CUSTOMER PIN: $customerKraPin',
      line,
      'FROM:',
      senderName,
      'Tel: $senderPhone',
      '',
      'TO:',
      receiverName,
      'Tel: $receiverPhone',
      'Destination: $destination',
      line,
      'WEIGHT: $weight kg',
      line,
      if (vatRate > 0) ...[
        row('Taxable amount', money(taxable ?? amount - vat)),
        row('VAT ${vatRate.toStringAsFixed(vatRate % 1 == 0 ? 0 : 2)}%', money(vat)),
      ],
      row('TOTAL KES', money(amount)),
      'PAID VIA: $paymentMethod',
      line,
      if (invoice != null) ...[
        if (simulation) ...['*** SIMULATION ***', 'NOT A TAX INVOICE'],
        'eTIMS INVOICE NO: ${invoice['invoice_number']}',
        if (invoice['status'] == 'signed') ...[
          'KRA RECEIPT: ${invoice['kra_receipt_number']}',
          'SIGNATURE: ${invoice['kra_signature']}',
          'CU ID: ${invoice['kra_sdc_id']}',
        ] else
          'Being sent to KRA (eTIMS)',
      ],
    ].join('\n');

    final bottom = [
      if (invoice != null) line,
      'SERVED BY: $cashierName',
      '',
      'Thank you for choosing Okebori!',
      'Keep this receipt for collection.',
      '\n\n\n',
    ].join('\n');

    final signed = invoice != null && invoice['status'] == 'signed';
    final qrText = signed ? invoice['qr_text']?.toString() : null;
    return [
      ..._text(top),
      if (qrText != null && qrText.isNotEmpty) ...[..._text('\n'), ...qrCode(qrText), ..._text('\n')] else ..._text('\n'),
      ..._text(bottom),
    ];
  }

  static List<int> _text(String s) => latin1.encode(s.replaceAll(RegExp(r'[^\x00-\xFF]'), '?'));

  /// ESC/POS "GS ( k" commands: centred QR code, model 2, module size 6, error correction M.
  @visibleForTesting
  static List<int> qrCode(String data) {
    final payload = utf8.encode(data);
    final storeLength = payload.length + 3;
    return [
      0x1B, 0x61, 0x01, // centre
      0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00, // model 2
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x06, // module size
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31, // error correction M
      0x1D, 0x28, 0x6B, storeLength & 0xFF, storeLength >> 8, 0x31, 0x50, 0x30, ...payload, // store data
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30, // print
      0x1B, 0x61, 0x00, // back to left
    ];
  }
}

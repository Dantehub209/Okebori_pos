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
  }) async {
    try {
      final bool connectionResult = await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      if (!connectionResult) return false;

      const line = '--------------------------------';
      final receiptText = [
        'OKEBORI COURIER SERVICES',
        branchName,
        'Tel: +254 700 000 000',
        line,
        'BOOKING NO: $bookingNumber',
        'RECEIPT NO: $receiptNumber',
        'DATE: ${DateTime.now().toString().substring(0, 16)}',
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
        'TOTAL CHARGE: KES ${amount.toStringAsFixed(2)}',
        'PAID VIA: $paymentMethod',
        line,
        'SERVED BY: $cashierName',
        '',
        'Thank you for choosing Okebori!',
        'Keep this receipt for collection.',
        '\n\n\n',
      ].join('\n');

      final bytes = latin1.encode(receiptText.replaceAll(RegExp(r'[^\x00-\xFF]'), '?'));
      final bool printResult = await PrintBluetoothThermal.writeBytes(bytes);
      await PrintBluetoothThermal.disconnect;
      return printResult;
    } catch (e) {
      debugPrint('Print Error: $e');
      return false;
    }
  }
}

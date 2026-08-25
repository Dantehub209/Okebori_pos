import 'dart:typed_data';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

class ReceiptService {
  static Future<bool> printReceipt({
    required String macAddress,
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

      // Professional Receipt Layout with Phone Numbers
      String receiptText = """
      OKEBORI COURIER SERVICES
      Nairobi Main Branch
      Tel: +254 700 000 000
      --------------------------------
      BOOKING NO: $bookingNumber
      RECEIPT NO: $receiptNumber
      DATE: ${DateTime.now().toString().substring(0, 16)}
      --------------------------------
      FROM:
      $senderName
      Tel: $senderPhone
      
      TO:
      $receiverName
      Tel: $receiverPhone
      Destination: $destination
      
      --------------------------------
      WEIGHT: $weight kg
      --------------------------------
      TOTAL CHARGE: KES $amount
      PAID VIA: $paymentMethod
      --------------------------------
      SERVED BY: $cashierName
      
      Thank you for choosing Okebori!
      Keep this receipt for collection.
      
      
      
      """;

      Uint8List bytes = Uint8List.fromList(receiptText.codeUnits);
      final bool printResult = await PrintBluetoothThermal.writeBytes(bytes);
      await PrintBluetoothThermal.disconnect;
      return printResult;
    } catch (e) {
      print("Print Error: $e");
      return false;
    }
  }
}
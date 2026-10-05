import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okebori_pos/screens/booking_screen.dart';
import 'package:okebori_pos/services/pricing.dart';
import 'package:okebori_pos/services/staff_profile.dart';
import 'package:okebori_pos/theme.dart';

final _setup = BookingSetup(
  branches: [
    {'id': 'nrb', 'name': 'Nairobi CBD', 'code': 'NRB', 'latitude': -1.2864, 'longitude': 36.8172},
    {'id': 'nkr', 'name': 'Nakuru', 'code': 'NKR', 'latitude': -0.3031, 'longitude': 36.0800},
  ],
  categories: [
    {'id': 'doc', 'name': 'Documents'},
  ],
  rules: const PricingRules(basePrice: 150, baseWeightKg: 5, pricePerExtraKg: 50, fuelCostPerKm: 1),
);

const _profile = StaffProfile(name: 'Wanjiku M.', role: 'Cashier', branchId: 'nrb', branchName: 'Nairobi CBD');

void main() {
  test('quote adds base rate, extra weight and distance', () {
    const rules = PricingRules(basePrice: 150, baseWeightKg: 5, pricePerExtraKg: 50, fuelCostPerKm: 2);
    final light = calculateQuote(rules, 3, 100);
    expect(light.weightCharge, 0);
    expect(light.total, 150 + 200);

    final heavy = calculateQuote(rules, 7.5, 100);
    expect(heavy.extraWeightKg, 2.5);
    expect(heavy.total, 150 + 125 + 200);
  });

  test('totals are whole shillings, rounded up like the server', () {
    const rules = PricingRules(basePrice: 150, baseWeightKg: 5, pricePerExtraKg: 50, fuelCostPerKm: 1.2);
    expect(calculateQuote(rules, 2, 136.65).total, 314); // 150 + 163.98 = 313.98 -> 314
    expect(calculateQuote(rules, 2, 100).total, 270); // exact amounts stay as they are
  });

  test('Kenyan phone numbers are normalised like the M-Pesa server function', () {
    expect(normalizeKenyanPhone('0712 345 678'), '254712345678');
    expect(normalizeKenyanPhone('+254712345678'), '254712345678');
    expect(normalizeKenyanPhone('712345678'), '254712345678');
    expect(normalizeKenyanPhone('0110345678'), '254110345678');
    expect(normalizeKenyanPhone('071234567'), isNull);
    expect(normalizeKenyanPhone('0812345678'), isNull);
  });

  test('formatKsh drops .00 but keeps real cents', () {
    expect(formatKsh(350), '350');
    expect(formatKsh(1250.5), '1,250.50');
  });

  testWidgets('booking shows the quote, change and cash button', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: BookingScreen(profile: _profile, loadSetup: () async => _setup)),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Book parcel'), findsOneWidget);

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'To'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nakuru').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Weight (kg)'), '2');
    await tester.enterText(find.widgetWithText(TextField, 'Cash received (KSh)'), '500');
    await tester.pumpAndSettle();

    final quote = calculateQuote(_setup.rules, 2, distanceBetween(-1.2864, 36.8172, -0.3031, 36.0800));
    expect(find.text('NKR'), findsOneWidget);
    expect(find.text('KSh ${formatKsh(quote.total)}'), findsOneWidget);
    expect(find.text('Take KSh ${formatKsh(quote.total)} cash and book'), findsOneWidget);
    expect(find.text('Change to give: KSh ${formatKsh(500 - quote.total)}'), findsOneWidget);

    // Missing names are reported instead of booking
    await tester.tap(find.text('Take KSh ${formatKsh(quote.total)} cash and book'));
    await tester.pumpAndSettle();
    expect(find.text("Enter the sender's name."), findsOneWidget);
  });

  testWidgets('M-Pesa sends a prompt to the sender\'s number by default', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: BookingScreen(profile: _profile, loadSetup: () async => _setup)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'To'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nakuru').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Phone number').first, '0712345678');
    await tester.enterText(find.widgetWithText(TextField, 'Weight (kg)'), '2');
    await tester.tap(find.text('M-Pesa'));
    await tester.pumpAndSettle();

    final quote = calculateQuote(_setup.rules, 2, distanceBetween(-1.2864, 36.8172, -0.3031, 36.0800));
    expect(find.widgetWithText(TextField, "Customer's M-Pesa number"), findsOneWidget);
    expect(find.text('0712345678'), findsNWidgets(2)); // sender phone copied into the M-Pesa field
    expect(find.text('Send KSh ${formatKsh(quote.total)} M-Pesa prompt'), findsOneWidget);
  });
}

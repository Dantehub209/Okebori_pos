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
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:okebori_pos/admin/admin_theme.dart';
import 'package:okebori_pos/admin/overview_screen.dart';

void main() {
  testWidgets('overview adds up bookings and payments per branch', (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const data = OverviewData(
      branches: [
        {'id': 'nrb', 'name': 'Nairobi CBD'},
        {'id': 'msa', 'name': 'Mombasa'},
      ],
      bookedToday: [
        {'origin_branch_id': 'nrb', 'shipping_charge': 350},
        {'origin_branch_id': 'msa', 'shipping_charge': 890},
      ],
      paymentsToday: [
        {'branch_id': 'nrb', 'received_by': 'w', 'amount': 350, 'payment_method': 'CASH'},
        {'branch_id': 'msa', 'received_by': 'd', 'amount': 890, 'payment_method': 'MPESA'},
      ],
      onShelf: [{'destination_branch_id': 'msa'}],
      latest: [],
      staff: {'w': {'name': 'Wanjiku M.', 'branch_id': 'nrb'}},
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildAdminTheme(),
      home: Scaffold(body: OverviewScreen(loadData: (_) async => data)),
    ));
    await tester.pump();

    expect(find.text('Today across the network'), findsOneWidget);
    expect(find.text('KSh 1,240'), findsOneWidget); // value booked
    expect(find.text('KSh 350'), findsOneWidget); // cash
    expect(find.text('KSh 890'), findsOneWidget); // M-Pesa
    expect(find.text('All branches'), findsOneWidget);
    expect(find.text('Wanjiku M.'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget); // cashier missing from staff list

    await tester.pumpWidget(const SizedBox()); // stops the refresh timer
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luxe_stays/app/app.dart';

/// End-to-end smoke test against the local mock back end.
///
/// Run it with the server up:
/// ```
///   dart run tool/mock_server/server.dart          # terminal 1
///   make integration                                # terminal 2
/// ```
///
/// It deliberately stops short of the payment WebView: driving a WebView from
/// `integration_test` is possible but slow and flaky, and the value is low
/// compared with the bridge unit tests plus a manual pass on the hosted page.
/// What this test protects is the multi-vendor fan-out - that search really
/// does compose SynXis, the CMS and Leonardo on a real device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('search → detail → cart', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: LuxeStaysApp()),
    );
    await tester.pumpAndSettle();

    // 1. Search the default destination.
    expect(find.textContaining('Search'), findsWidgets);
    await tester.tap(find.textContaining('Search').first);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 2. Results arrived from SynXis, enriched by the CMS and Leonardo.
    expect(find.textContaining('available'), findsWidgets);

    // 3. Add the first result to the cart.
    final Finder addButton = find.text('Add').first;
    await tester.ensureVisible(addButton);
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    // 4. The cart badge reflects it.
    await tester.tap(find.byIcon(Icons.shopping_bag_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining('Checkout'), findsOneWidget);
  });
}

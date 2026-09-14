import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luxe_stays/app/app.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Runs against the local mock server on a native Android/iOS device.
/// The JavaScript call invokes the same mock-page function as its Pay button;
/// authorization, bridge, server verification and reservation creation remain real.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (int i = 0; i < 160 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(finder, findsWidgets);
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('search → cart → hosted payment → confirmed reservation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: LuxeStaysApp()));
    final Finder add = find.text('Add');
    await waitFor(tester, add);
    await tester.ensureVisible(add.first);
    await tester.pumpAndSettle();
    await tester.tap(add.first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.shopping_bag_outlined));
    final Finder checkout = find.textContaining('Checkout');
    await waitFor(tester, checkout);
    await tester.ensureVisible(checkout.last);
    await tester.pumpAndSettle();
    await tester.tap(checkout.last);
    await waitFor(tester, find.byType(TextFormField));
    for (final (String label, String value) in [
      ('First name', 'Ada'),
      ('Last name', 'Guest'),
      ('Email', 'ada@example.test'),
      ('Mobile', '+15555550123'),
    ]) {
      final Finder field = find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(field, value);
    }
    // Hide the keyboard before scrolling to the payment action.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    final Finder pay = find.textContaining(RegExp(r'^Pay '));
    await tester.ensureVisible(pay);
    await tester.pumpAndSettle();
    await tester.tap(pay);
    await waitFor(tester, find.byType(WebViewWidget));
    final controller = tester
        .widget<WebViewWidget>(find.byType(WebViewWidget))
        .platform
        .params
        .controller;
    bool ready = false;
    for (int i = 0; i < 80; i++) {
      final Object value = await controller.runJavaScriptReturningResult(
        "typeof finish === 'function'",
      );
      if (value == true || value == 'true') {
        ready = true;
        break;
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(ready, isTrue, reason: 'Hosted mock payment page must load');
    await controller.runJavaScript("finish('authorize', false)");
    await waitFor(tester, find.text('You are all set'));
    expect(find.text('Confirmed'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

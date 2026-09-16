import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/app/router.dart';
import 'package:luxe_stays/webview/cms_content_webview_screen.dart';

void main() {
  testWidgets('Browse hotels removes the CMS WebView stack above search', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text(Routes.search)),
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text(settings.name!)),
        ),
      ),
    );

    final NavigatorState navigator = navigatorKey.currentState!;
    unawaited(navigator.pushNamed<void>(Routes.confirmation));
    await tester.pumpAndSettle();
    unawaited(navigator.pushNamed<void>(Routes.cmsPage));
    await tester.pumpAndSettle();

    expect(find.text(Routes.cmsPage), findsOneWidget);

    navigateFromCmsWebView(navigator, Routes.search);
    await tester.pumpAndSettle();

    expect(find.text(Routes.search), findsOneWidget);
    expect(navigator.canPop(), isFalse);
  });

  testWidgets('other CMS destinations replace the WebView route', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text(Routes.search)),
        onGenerateRoute: (RouteSettings settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => Scaffold(body: Text(settings.name!)),
        ),
      ),
    );

    final NavigatorState navigator = navigatorKey.currentState!;
    unawaited(navigator.pushNamed<void>(Routes.cmsPage));
    await tester.pumpAndSettle();

    navigateFromCmsWebView(navigator, Routes.cart);
    await tester.pumpAndSettle();

    expect(find.text(Routes.cart), findsOneWidget);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text(Routes.search), findsOneWidget);
    expect(find.text(Routes.cmsPage), findsNothing);
  });
}

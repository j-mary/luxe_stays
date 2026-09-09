import 'dart:async';

// `kIsWeb`, `defaultTargetPlatform` and `TargetPlatform` live in foundation,
// which material.dart does not re-export (widgets.dart forwards only
// `Brightness` and `UniqueKey` from it).
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/analytics/analytics.dart';
import 'core/config/app_config.dart';
import 'core/logging/app_logger.dart';

/// Entry point.
///
/// `runZonedGuarded` plus the two Flutter error hooks give one funnel for every
/// uncaught error - framework, platform and asynchronous - which is what you
/// need before wiring a crash reporter. Swap [AnalyticsService.error] for
/// `FirebaseCrashlytics.instance.recordError` and every path is already covered.
void main() {
  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      final ProviderContainer container = ProviderContainer();
      final AppLogger logger = container.read(loggerProvider);
      final AnalyticsService analytics = container.read(analyticsProvider);
      final AppConfig config = container.read(appConfigProvider);

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        analytics.error(details.exception, details.stack ?? StackTrace.current);
      };

      // Errors from the platform side (plugins, message channels) that never
      // reach the Flutter framework.
      WidgetsBinding.instance.platformDispatcher.onError =
          (Object error, StackTrace stack) {
        analytics.error(error, stack);
        return true;
      };

      _warnIfUnreachableBackend(config, logger);

      logger.info(
        'LuxeStays starting',
        context: <String, Object?>{
          'flavor': config.flavor.name,
          'synxis': config.synxisBaseUrl,
          'cms': config.cmsBaseUrl,
          'leonardo': config.leonardoBaseUrl,
          'salesforce': config.salesforceBaseUrl,
        },
      );

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const LuxeStaysApp(),
        ),
      );
    },
    (Object error, StackTrace stack) {
      debugPrint('Uncaught zone error: $error');
    },
  );
}

/// Catches the single most common local-setup failure before it becomes a
/// network error three screens later.
///
/// On Android, `localhost` resolves to the handset, not to the developer's
/// machine - so a mock server that is plainly running in another terminal is
/// unreachable, and the app reports a `NetworkFailure` that looks like a bug in
/// the app. Saying so at startup, loudly and with the fix, costs nothing.
void _warnIfUnreachableBackend(AppConfig config, AppLogger logger) {
  if (config.isProd || kIsWeb) {
    return;
  }
  final bool isAndroid = defaultTargetPlatform == TargetPlatform.android;
  final bool pointsAtLoopback = config.synxisBaseUrl.contains('localhost') ||
      config.synxisBaseUrl.contains('127.0.0.1');
  if (!isAndroid || !pointsAtLoopback) {
    return;
  }
  logger.error(
    'CONFIGURATION: this build points at ${config.apiBaseUrl}, but on Android '
    '"localhost" is the handset itself - not the machine running the mock '
    'server. Every request will fail with a connection error. Fix it with one '
    'of:  `make adb-reverse` (USB device, easiest),  `make run-emulator` '
    '(10.0.2.2),  or `make run-lan` (physical device over Wi-Fi). '
    'See docs/13-RUNBOOK.md.',
  );
}

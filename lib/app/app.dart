import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class LuxeStaysApp extends ConsumerWidget {
  const LuxeStaysApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Touching the config provider here surfaces a misconfigured build at
    // startup rather than at the first network call.
    ref.watch(appConfigProvider);

    return MaterialApp(
      title: 'LuxeStays',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      initialRoute: Routes.search,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

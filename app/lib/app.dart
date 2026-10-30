import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/theme.dart';
import 'router/app_router.dart';
import 'state/providers.dart';

class BubbleApp extends ConsumerWidget {
  const BubbleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'BubbleApp',
      debugShowCheckedModeBanner: false,
      theme: BubbleTheme.light(),
      darkTheme: BubbleTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

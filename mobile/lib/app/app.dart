import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routes.dart';
import 'theme.dart';

class DeepTutorApp extends ConsumerWidget {
  const DeepTutorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'DeepTutor',
      debugShowCheckedModeBanner: false,
      theme: buildDeepTutorTheme(Brightness.light),
      darkTheme: buildDeepTutorTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'features/home/home_screen.dart';
import 'firebase_options.dart';
import 'providers.dart';
import 'theme.dart';

Future<void> main() async {
  // Needed before calling plugins (Firebase) ahead of runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Connects the app to the study-buddy-ffd63 Firebase project. Works offline.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check proves requests come from THIS app. Debug builds on my own
  // phone use the debug provider (token registered in the Firebase console);
  // release builds use Play Integrity.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
  );

  runApp(const ProviderScope(child: StudyBuddyApp()));
}

class StudyBuddyApp extends ConsumerWidget {
  const StudyBuddyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = switch (ref.watch(settingsProvider).value?.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp(
      title: 'Study Buddy',
      themeMode: themeMode,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }
}

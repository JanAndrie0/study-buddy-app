import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';

import 'config.dart';
import 'firebase_options.dart';
import 'services/generator_service.dart';

Future<void> main() async {
  // Needed before calling plugins (Firebase) ahead of runApp().
  WidgetsFlutterBinding.ensureInitialized();

  // Connects the app to the study-buddy-ffd63 Firebase project.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check proves requests come from THIS app. Debug builds on my own
  // phone use the debug provider (prints a token to register in the
  // Firebase console); release builds use Play Integrity.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
  );

  runApp(StudyBuddyApp(generator: GeneratorService()));
}

class StudyBuddyApp extends StatelessWidget {
  const StudyBuddyApp({super.key, required this.generator});

  final GeneratorService generator;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Study Buddy',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.indigo)),
      home: HelloScreen(generator: generator),
    );
  }
}

/// Phase 0 hello-world: pick a lecture PDF -> Taglish summary from Gemini.
class HelloScreen extends StatefulWidget {
  const HelloScreen({super.key, required this.generator});

  final GeneratorService generator;

  @override
  State<HelloScreen> createState() => _HelloScreenState();
}

class _HelloScreenState extends State<HelloScreen> {
  bool _loading = false;
  String? _fileName;
  String? _error;
  SummaryResult? _result;

  Future<void> _pickAndSummarize() async {
    // 1. Let the user choose a PDF (null = they cancelled).
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (file == null) return;

    // 2. Read the bytes and check the size BEFORE spending money on a call.
    final bytes = await file.xFile.readAsBytes();
    if (bytes.length > AppConfig.maxPdfBytes) {
      setState(() {
        _fileName = file.name;
        _result = null;
        _error = 'Masyadong malaki ang file '
            '(${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
            'Max is ${AppConfig.maxPdfBytes ~/ 1024 ~/ 1024} MB.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _fileName = file.name;
      _error = null;
      _result = null;
    });

    // 3. Ask Gemini. Network/server problems become a friendly message,
    //    never a crash.
    try {
      final result = await widget.generator.summarizePdf(bytes);
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = 'Hindi natuloy ang summary: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Study Buddy · Hello Gemini')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _loading ? null : _pickAndSummarize,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Pick a lecture PDF'),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Text('File: $_fileName'),
          ],
          if (_loading) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            const Center(child: Text('Binabasa ni Gemini ang lecture mo...')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (result != null) ...[
            const SizedBox(height: 16),
            SelectableText(result.text),
            const SizedBox(height: 16),
            Text(
              'Tokens: ${result.inputTokens ?? '?'} in · '
              '${result.outputTokens ?? '?'} out · '
              '${result.thinkingTokens ?? 0} thinking '
              '(${AppConfig.geminiModel})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

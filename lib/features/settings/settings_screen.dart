import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../providers.dart';

/// Explanation language, new cards per day and theme. Saved in the local
/// database (CLAUDE.md: Drift for all persistence).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const newCardChoices = [5, 10, 20, 30, 50];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Explanation language', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'english', label: Text('English')),
                    ButtonSegment(value: 'taglish', label: Text('Taglish')),
                    ButtonSegment(value: 'filipino', label: Text('Filipino')),
                  ],
                  selected: {settings.language},
                  onSelectionChanged: (s) =>
                      db.updateSettings(AppSettingsCompanion(language: Value(s.first))),
                ),
                const SizedBox(height: 4),
                Text('Default for new reviewers. Existing ones keep their language.',
                    style: theme.textTheme.bodySmall),
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('New cards per day'),
                  subtitle: const Text('Due reviews are never limited'),
                  trailing: DropdownButton<int>(
                    value: newCardChoices.contains(settings.newCardsPerDay) ? settings.newCardsPerDay : 20,
                    items: [
                      for (final n in newCardChoices) DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (n) {
                      if (n != null) db.updateSettings(AppSettingsCompanion(newCardsPerDay: Value(n)));
                    },
                  ),
                ),
                const Divider(height: 32),
                Text('Theme', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'system', label: Text('System')),
                    ButtonSegment(value: 'light', label: Text('Light')),
                    ButtonSegment(value: 'dark', label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) =>
                      db.updateSettings(AppSettingsCompanion(themeMode: Value(s.first))),
                ),
              ],
            ),
    );
  }
}

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/database.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../../widgets/logo.dart';
import '../../widgets/ui.dart';

/// Theme, explanation language, new cards per day, and About. Saved in the
/// local database (CLAUDE.md: Drift for all persistence). Figma: "Settings".
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const newCardChoices = [5, 10, 20, 30, 50];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final db = ref.read(databaseProvider);
    final theme = Theme.of(context);
    final t = context.tokens;

    Widget section(String label) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.sm),
          child: SectionLabel(label),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: settings == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: Space.xxxl),
              children: [
                section('Appearance'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Theme', style: theme.textTheme.bodyLarge),
                      const SizedBox(height: Space.sm),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'system', label: Text('System')),
                            ButtonSegment(value: 'light', label: Text('Light')),
                            ButtonSegment(value: 'dark', label: Text('Dark')),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (s) =>
                              db.updateSettings(AppSettingsCompanion(themeMode: Value(s.first))),
                        ),
                      ),
                    ],
                  ),
                ),
                section('Study'),
                Container(
                  color: t.surface,
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.language, color: t.textSecondary),
                        const SizedBox(width: Space.lg),
                        Text('Explanation language', style: theme.textTheme.bodyLarge),
                      ]),
                      const SizedBox(height: Space.md),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'english', label: Text('English')),
                            ButtonSegment(value: 'taglish', label: Text('Taglish')),
                            ButtonSegment(value: 'filipino', label: Text('Filipino')),
                          ],
                          selected: {settings.language},
                          onSelectionChanged: (s) =>
                              db.updateSettings(AppSettingsCompanion(language: Value(s.first))),
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text('Default for new reviewers. Existing ones keep their language.',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(height: 1),
                Container(
                  color: t.surface,
                  padding: const EdgeInsets.fromLTRB(Space.xl, Space.md, Space.lg, Space.md),
                  child: Row(
                    children: [
                      Icon(Icons.style_outlined, color: t.textSecondary),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('New cards per day', style: theme.textTheme.bodyLarge),
                            Text('Due reviews are never limited', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      _Stepper(
                        value: newCardChoices.contains(settings.newCardsPerDay) ? settings.newCardsPerDay : 20,
                        choices: newCardChoices,
                        onChanged: (n) => db.updateSettings(AppSettingsCompanion(newCardsPerDay: Value(n))),
                      ),
                    ],
                  ),
                ),
                section('About'),
                Material(
                  color: t.surface,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.xs),
                    leading: const StudyBuddyLogo(size: 32),
                    title: const Text('About Study Buddy'),
                    subtitle: const Text('Your reviewers stay on this phone'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'Study Buddy',
                      applicationIcon: const StudyBuddyLogo(size: 56),
                      applicationLegalese: 'Turns your lecture PDFs into a reviewer you can study offline.\n\n'
                          'Fonts: Fraunces and Inter (SIL Open Font License).',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// − 20 + : steps through [choices].
class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.choices, required this.onChanged});

  final int value;
  final List<int> choices;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final i = choices.indexOf(value);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: t.borderStrong),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Fewer',
            icon: const Icon(Icons.remove),
            onPressed: i > 0 ? () => onChanged(choices[i - 1]) : null,
          ),
          SizedBox(
            width: 28,
            child: Text('$value', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.add),
            onPressed: i < choices.length - 1 ? () => onChanged(choices[i + 1]) : null,
          ),
        ],
      ),
    );
  }
}

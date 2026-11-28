import 'package:flutter/material.dart';

import '../models/spot.dart';
import '../services/comparison_history.dart';
import '../theme/app_colors.dart';

typedef ComparePair = ({String first, String second});

/// Picks the restaurant to compare [firstId] with, or a recent comparison.
/// It only uses data on the phone (the catalog and SQLite), so it works the
/// same with or without network.
Future<ComparePair?> showComparePicker(
  BuildContext context, {
  required String firstId,
  required List<Spot> catalog,
  required ComparisonHistoryStorage history,
}) {
  return showModalBottomSheet<ComparePair>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.cream,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => ComparePickerSheet(firstId: firstId, catalog: catalog, history: history),
  );
}

class ComparePickerSheet extends StatefulWidget {
  final String firstId;
  final List<Spot> catalog;
  final ComparisonHistoryStorage history;

  const ComparePickerSheet({super.key, required this.firstId, required this.catalog, required this.history});

  @override
  State<ComparePickerSheet> createState() => _ComparePickerSheetState();
}

class _ComparePickerSheetState extends State<ComparePickerSheet> {
  final _search = TextEditingController();

  /// Read once when the sheet opens, not on every keystroke.
  late final Future<List<ComparisonEntry>> _recent = widget.history.recent().catchError(
        (Object _) => const <ComparisonEntry>[],
      );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.catalog.where((s) => s.id == widget.firstId).firstOrNull;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListenableBuilder(
        listenable: _search,
        builder: (context, _) {
          final query = _search.text.trim().toLowerCase();
          final options = [
            for (final s in widget.catalog)
              if (s.id != widget.firstId && (query.isEmpty || s.matchesSearch(query))) s,
          ];
          return ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                first == null ? 'Compare with…' : 'Compare ${first.name} with…',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.espresso),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  hintText: 'Search a place',
                  prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                  filled: true,
                  fillColor: AppColors.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(999),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                ),
              ),
              if (query.isEmpty)
                FutureBuilder<List<ComparisonEntry>>(
                  future: _recent,
                  builder: (context, snapshot) {
                    final recent = snapshot.data ?? const [];
                    if (recent.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _SectionTitle('Recent comparisons'),
                        for (final e in recent.take(3))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Text('${e.firstEmoji}${e.secondEmoji}', style: const TextStyle(fontSize: 22)),
                            title: Text('${e.firstName} vs ${e.secondName}', maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.pop(context, (first: e.firstId, second: e.secondId)),
                          ),
                      ],
                    );
                  },
                ),
              const _SectionTitle('Places'),
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No places match "${_search.text.trim()}".', style: const TextStyle(color: AppColors.muted)),
                ),
              for (final s in options)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: s.emojiBackground,
                    child: Text(s.emoji, style: const TextStyle(fontSize: 20)),
                  ),
                  title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.espresso)),
                  subtitle: Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text('★ ${s.rating.toStringAsFixed(1)}', style: const TextStyle(color: AppColors.muted)),
                  onTap: () => Navigator.pop(context, (first: widget.firstId, second: s.id)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted),
        ),
      );
}

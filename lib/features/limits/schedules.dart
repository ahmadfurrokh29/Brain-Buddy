import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../core/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

const _dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String _time(BuildContext context, int minutes) =>
    TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

String _days(List<int> days) {
  final d = [...days]..sort();
  if (d.length == 7) return 'Every day';
  if (d.join() == '12345') return 'Weekdays';
  if (d.join() == '67') return 'Weekends';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return d.map((i) => names[i - 1]).join(', ');
}

/// "Schedules" section of the Limits screen: list, on/off switches and an add button.
class SchedulesSection extends ConsumerWidget {
  final AppConfig c;
  const SchedulesSection({super.key, required this.c});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.read(configProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Schedules', trailing: const ProTag()),
      Text('Reels are blocked automatically at these times, like a Hard lock.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.muted)),
      const SizedBox(height: 10),
      for (final s in c.schedules)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _ScheduleTile(
            s: s,
            active: s.id == c.activeScheduleId,
            onEdit: () => _openEditor(context, ref, c, s),
            onToggle: (v) => cfg.setSchedules([for (final x in c.schedules) x.id == s.id ? x.copyWith(enabled: v) : x]),
          ),
        ),
      OutlinedButton.icon(
        onPressed: () => _openEditor(context, ref, c, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add schedule'),
      ),
    ]);
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, AppConfig c, Schedule? existing) async {
    if (existing != null && existing.id == c.activeScheduleId) {
      showSnack(context, '${existing.name} is running now. You can change it after it ends.');
      return;
    }
    final result = await showModalBottomSheet<_EditResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useRootNavigator: true,
      builder: (_) => _ScheduleEditor(existing: existing),
    );
    if (result == null) return;
    final list = [...c.schedules];
    if (result.delete) {
      list.removeWhere((s) => s.id == existing!.id);
    } else if (existing == null) {
      list.add(result.schedule!);
    } else {
      list[list.indexWhere((s) => s.id == existing.id)] = result.schedule!;
    }
    await ref.read(configProvider.notifier).setSchedules(list);
  }
}

class _ScheduleTile extends StatelessWidget {
  final Schedule s;
  final bool active;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  const _ScheduleTile({required this.s, required this.active, required this.onEdit, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? BB.coral : Colors.transparent, width: 2),
      ),
      child: BBCard(
        onTap: onEdit,
        child: Row(children: [
          CircleAvatar(
            backgroundColor: BB.mintLight,
            child: Icon(s.name.toLowerCase().contains('bed') ? Icons.bedtime_rounded : Icons.event_busy_rounded, color: BB.mintDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text('${_time(context, s.start)} – ${_time(context, s.end)} · ${_days(s.days)}', style: TextStyle(color: context.muted)),
              if (active) const Text('Running now', style: TextStyle(color: BB.coral, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ),
          // A running schedule can't be switched off until it ends.
          Switch(value: s.enabled, onChanged: active ? null : onToggle),
        ]),
      ),
    );
  }
}

class _EditResult {
  final Schedule? schedule;
  final bool delete;
  const _EditResult({this.schedule, this.delete = false});
}

class _ScheduleEditor extends StatefulWidget {
  final Schedule? existing;
  const _ScheduleEditor({this.existing});

  @override
  State<_ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<_ScheduleEditor> {
  static const _presets = {
    'Bedtime': (23 * 60, 7 * 60, [1, 2, 3, 4, 5, 6, 7]),
    'Study': (16 * 60, 19 * 60, [1, 2, 3, 4, 5]),
    'Work': (9 * 60, 17 * 60, [1, 2, 3, 4, 5]),
  };

  late final _name = TextEditingController(text: widget.existing?.name ?? 'Bedtime');
  late int _start = widget.existing?.start ?? 23 * 60;
  late int _end = widget.existing?.end ?? 7 * 60;
  late Set<int> _days = {...(widget.existing?.days ?? const [1, 2, 3, 4, 5, 6, 7])};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final current = start ? _start : _end;
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60));
    if (picked == null) return;
    setState(() => start ? _start = picked.hour * 60 + picked.minute : _end = picked.hour * 60 + picked.minute);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final valid = _name.text.trim().isNotEmpty && _days.isNotEmpty && _start != _end;
    // Scrolls only when the keyboard leaves too little room.
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(widget.existing == null ? 'New schedule' : 'Edit schedule', style: t.titleLarge),
        const SizedBox(height: 12),
        if (widget.existing == null)
          Wrap(spacing: 8, children: [
            for (final p in _presets.entries)
              ActionChip(
                label: Text(p.key),
                onPressed: () => setState(() {
                  _name.text = p.key;
                  _start = p.value.$1;
                  _end = p.value.$2;
                  _days = {...p.value.$3};
                }),
              ),
          ]),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _TimeBox(label: 'From', value: _time(context, _start), onTap: () => _pick(true))),
          const SizedBox(width: 12),
          Expanded(child: _TimeBox(label: 'To', value: _time(context, _end), onTap: () => _pick(false))),
        ]),
        // Always one line here, so the sheet keeps its height whichever preset is picked.
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _end < _start ? 'Runs past midnight, into the next morning.' : 'Starts and ends on the same day.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: context.muted),
          ),
        ),
        const SizedBox(height: 12),
        // Seven equal day buttons that always fit the width.
        Row(children: [
          for (var d = 1; d <= 7; d++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _DayButton(
                  letter: _dayLetters[d - 1],
                  selected: _days.contains(d),
                  onTap: () => setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: valid
              ? () => Navigator.pop(
                    context,
                    _EditResult(
                      schedule: Schedule(
                        id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                        name: _name.text.trim(),
                        start: _start,
                        end: _end,
                        days: (_days.toList()..sort()),
                        enabled: widget.existing?.enabled ?? true,
                      ),
                    ),
                  )
              : null,
          child: const Text('Save'),
        ),
        if (widget.existing != null)
          TextButton(
            onPressed: () => Navigator.pop(context, const _EditResult(delete: true)),
            child: const Text('Delete schedule', style: TextStyle(color: BB.coral)),
          ),
      ]),
    );
  }
}

class _DayButton extends StatelessWidget {
  final String letter;
  final bool selected;
  final VoidCallback onTap;
  const _DayButton({required this.letter, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? BB.mint : scheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 40,
          child: Center(
            child: Text(
              letter,
              style: TextStyle(fontWeight: FontWeight.w800, color: selected ? Colors.white : scheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _TimeBox({required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

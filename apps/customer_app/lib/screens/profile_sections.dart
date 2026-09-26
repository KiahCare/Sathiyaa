import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../backend.dart';
import '../widgets/common.dart';
import '../widgets/sathiyaa_ui.dart';
import '../theme/sathiyaa_theme.dart';
import '../utils/dates.dart';
import '../utils/chart_axis.dart';
import '../i18n/l10n.dart';

/// The six collapsible health/insurance/family sections of the customer
/// profile. Each one renders inline (no Scaffold) so `ProfileScreen` can wrap
/// it in an `ExpandableSection` — the requirements doc asks specifically for
/// these to expand and collapse. All of them support create, update and
/// delete; the four capped ones block adding past 5 records until one is
/// removed.
int _seq = 1000;
String _nextId(String prefix) => '$prefix${_seq++}';

const _cap = 5;

Future<void> _showError(BuildContext context, Object e) {
  return showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: SC.surface,
      title: Text(t('Could not save that'), style: ST.h2),
      content: Text(e.toString().replaceFirst('Exception: ', ''), style: ST.body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
      ],
    ),
  );
}

/// Shared row: what the record says, plus edit and delete.
///
/// Not a dense ListTile. `dense: true` squeezes the row to about 48px while
/// two trailing IconButtons each want 48px of their own, so the text was
/// clipped top and bottom — the "vertically cut" look on the Vitals list.
class _RecordTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final IconData icon;

  const _RecordTile({
    required this.title,
    required this.subtitle,
    required this.onEdit,
    required this.onDelete,
    this.icon = Icons.circle_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: SC.sunkTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: SC.surface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: SC.blueBright),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: ST.bodyStrong.copyWith(fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: ST.small.copyWith(fontSize: 12)),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, size: 18, color: SC.inkSoft),
            onPressed: onEdit,
            tooltip: t('Edit'),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: SC.red),
            onPressed: onDelete,
            tooltip: t('Delete'),
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

/// "Add" button that disables itself at the cap and says why.
class _AddBar extends StatelessWidget {
  final int count;
  final int cap;
  final String label;
  final VoidCallback onAdd;

  const _AddBar({
    required this.count,
    required this.cap,
    required this.label,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final atCap = count >= cap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        if (atCap)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: SC.amberTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFA9670F)),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'That is all $cap. Delete one to add another.',
                    style: ST.small.copyWith(color: const Color(0xFF8A5510)),
                  ),
                ),
              ],
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(label),
          onPressed: atCap ? null : onAdd,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        ),
      ],
    );
  }
}

Widget _empty(String text) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: SC.sunkTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, textAlign: TextAlign.center, style: ST.small),
    );

// ---------------------------------------------------------------- Vitals ---

/// Vitals, with a trend graph over a selectable window (7 / 30 / 90 days) as
/// the spec requires, plus the tabular add/edit/delete view underneath.
///
/// One record holds one reading of one vital type, matching how the backend
/// stores them — so the cap of 5 records counts the same way in demo mode and
/// against a live server.
class VitalsSection extends StatefulWidget {
  final VoidCallback onChanged;
  const VitalsSection({super.key, required this.onChanged});

  @override
  State<VitalsSection> createState() => _VitalsSectionState();
}

class _VitalsSectionState extends State<VitalsSection> {
  int windowDays = 90;
  VitalType metric = VitalType.bp;

  Future<void> _edit({VitalRecord? existing}) async {
    var type = existing?.type ?? metric;
    final primary = TextEditingController(text: existing?.valuePrimary.toStringAsFixed(0) ?? '');
    final secondary = TextEditingController(text: existing?.valueSecondary?.toStringAsFixed(0) ?? '');
    var date = existing?.date ?? DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add vital reading' : 'Edit vital reading'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<VitalType>(
                  initialValue: type,
                  decoration: InputDecoration(labelText: t('Reading')),
                  items: VitalType.values
                      .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                      .toList(),
                  onChanged: (v) => setLocal(() => type = v!),
                ),
                TextField(
                  controller: primary,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: type == VitalType.bp ? 'Systolic (${type.unit})' : '${type.label} (${type.unit})',
                  ),
                ),
                if (type == VitalType.bp)
                  TextField(
                    controller: secondary,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: t('Diastolic (mmHg)')),
                  ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(t('Taken on {date}', {'date': prettyDate(date)})),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setLocal(() => date = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Save'))),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final value = double.tryParse(primary.text);
    if (value == null) {
      if (mounted) _showError(context, Exception('Enter a number for the reading.'));
      return;
    }

    final record = VitalRecord(
      id: existing?.id ?? _nextId('v'),
      date: date,
      type: type,
      valuePrimary: value,
      valueSecondary: type == VitalType.bp ? double.tryParse(secondary.text) : null,
    );
    try {
      if (existing == null) {
        await Backend.instance.addVital(record);
      } else {
        await Backend.instance.updateVital(record);
      }
      if (mounted) setState(() => metric = type);
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = Backend.instance.currentCustomer!.vitals;
    final windowed = Backend.instance.vitalsWithin(windowDays, type: metric);

    // Blood pressure is two numbers and was being drawn as one.
    //
    // The diastolic reading was stored, shown in the record list underneath as
    // "138/88", and then left out of the graph — so the chart above the list
    // was showing half of each reading while claiming to be the trend. For
    // somebody watching their blood pressure that is the more important half
    // missing, not a cosmetic one.
    final points = <FlSpot>[];
    final lower = <FlSpot>[];
    for (var i = 0; i < windowed.length; i++) {
      points.add(FlSpot(i.toDouble(), windowed[i].valuePrimary));
      final d = windowed[i].valueSecondary;
      if (d != null) lower.add(FlSpot(i.toDouble(), d));
    }
    final hasLower = lower.length == points.length && lower.isNotEmpty;
    final axis = niceAxis([
      ...points.map((p) => p.y),
      if (hasLower) ...lower.map((p) => p.y),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Two clipping bugs in the same two controls, and they had different
        // causes.
        //
        // They were side by side, each in an Expanded, leaving about 150px on a
        // phone — and a DropdownButtonFormField does not shrink its selected
        // item to fit, so "Blood pressure" was sliced off at the right. That
        // was the horizontal half.
        //
        // The vertical half was the label. A floating label is painted *above*
        // the field's top edge, and ExpandableSection gives its body no top
        // padding at all, so the word "Reading" was drawn over the section
        // header and cut in two by the card's own clip. Moving the label out of
        // the decoration and above the field fixes it at the cause rather than
        // padding around it, and makes both controls read as a matched pair.
        const SizedBox(height: 14),
        FieldLabel(t('Reading')),
        DropdownButtonFormField<VitalType>(
          initialValue: metric,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          items: VitalType.values
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Text(t.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (v) => setState(() => metric = v!),
        ),
        const SizedBox(height: 16),
        FieldLabel(t('Over the last')),
        SegmentedTabs(
          tabs: const ['7 days', '30 days', '90 days'],
          index: const [7, 30, 90].indexOf(windowDays),
          onChanged: (i) => setState(() => windowDays = const [7, 30, 90][i]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: points.length < 2
              ? Center(
                  child: Text(
                    points.isEmpty
                        ? 'No ${metric.label.toLowerCase()} readings in this window.'
                        : 'Add a second ${metric.label.toLowerCase()} reading to see a trend.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                  ),
                )
              : LineChart(
                  LineChartData(
                    // Bounds rounded out to a whole step, so every gridline
                    // lands on a round number and the labels cannot collide.
                    minY: axis.min,
                    maxY: axis.max,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: axis.step,
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 34,
                          interval: axis.step,
                          // Drawn here rather than left to fl_chart, which
                          // labels the exact minimum and maximum *as well as*
                          // its own ticks — a series running 128 to 146 came
                          // out as "128 130 135 140 145 146" with both pairs
                          // printed on top of each other.
                          getTitlesWidget: (value, meta) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              value.toStringAsFixed(0),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 10.5,
                                  color: SC.inkFaint,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 26,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final i = value.toInt();
                            // Only at a real reading, and never a fraction —
                            // fl_chart asks for values between the points too.
                            if (i < 0 || i >= windowed.length) return const SizedBox();
                            if (value != i.toDouble()) return const SizedBox();
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(prettyDay(windowed[i].date),
                                  style: const TextStyle(fontSize: 10, color: SC.inkFaint)),
                            );
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: points,
                        // Not curved. A spline through three readings
                        // overshoots past the highest and lowest of them, so
                        // the line showed a value nobody recorded.
                        isCurved: false,
                        color: kPrimaryColor,
                        barWidth: 3,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                            show: !hasLower,
                            color: kPrimaryColor.withValues(alpha: 0.12)),
                      ),
                      if (hasLower)
                        LineChartBarData(
                          spots: lower,
                          isCurved: false,
                          color: SC.blueBright,
                          barWidth: 3,
                          dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(show: false),
                        ),
                    ],
                  ),
                ),
        ),
        // Only for the one metric that has two lines. A key over a single line
        // is furniture.
        if (hasLower) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              _key(kPrimaryColor, 'Systolic'),
              const SizedBox(width: 16),
              _key(SC.blueBright, 'Diastolic'),
            ],
          ),
        ],
        const Divider(height: 24),
        if (all.isEmpty)
          _empty('No vitals recorded yet.')
        else
          ...all.map(
            (v) => _RecordTile(
                icon: Icons.monitor_heart_rounded,
              title: '${v.type.label} \u00b7 ${v.display}',
              subtitle: prettyDate(v.date),
              onEdit: () => _edit(existing: v),
              onDelete: () async {
                await Backend.instance.deleteVital(v.id);
                if (mounted) setState(() {});
                widget.onChanged();
              },
            ),
          ),
        _AddBar(count: all.length, cap: _cap, label: t('Add reading'), onAdd: _edit),
      ],
    );
  }

  Widget _key(Color colour, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11.5, color: SC.inkSoft, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ----------------------------------------------------------- Medications ---

class MedicationsSection extends StatefulWidget {
  final VoidCallback onChanged;
  const MedicationsSection({super.key, required this.onChanged});

  @override
  State<MedicationsSection> createState() => _MedicationsSectionState();
}

class _MedicationsSectionState extends State<MedicationsSection> {
  Future<void> _edit({MedicationRecord? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final freq = TextEditingController(text: existing?.frequency ?? '');
    var prescription = existing?.prescriptionUrl;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add medication' : 'Edit medication'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: t('Medicine name'))),
              TextField(controller: freq, decoration: InputDecoration(labelText: t('Frequency'), hintText: t('e.g. Twice daily'))),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(prescription == null ? Icons.attach_file : Icons.check, size: 18),
                      label: Text(prescription == null ? 'Attach prescription' : 'Prescription attached'),
                      onPressed: () async {
                        final file = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                          maxWidth: 1600,
                          imageQuality: 85,
                        );
                        if (file != null) setLocal(() => prescription = file.path);
                      },
                    ),
                  ),
                  if (prescription != null)
                    IconButton(
                      tooltip: t('Remove'),
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setLocal(() => prescription = null),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;

    final record = MedicationRecord(
      id: existing?.id ?? _nextId('m'),
      name: name.text.trim(),
      frequency: freq.text.trim(),
      prescriptionUrl: prescription,
    );
    try {
      if (existing == null) {
        await Backend.instance.addMedication(record);
      } else {
        await Backend.instance.updateMedication(record);
      }
      if (mounted) setState(() {});
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = Backend.instance.currentCustomer!.medications;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          _empty('No medications recorded.')
        else
          ...items.map(
            (m) => _RecordTile(
                icon: Icons.medication_rounded,
              title: m.name,
              subtitle: m.prescriptionUploaded
                  ? t('{frequency} · prescription on file', {'frequency': m.frequency})
                  : m.frequency,
              onEdit: () => _edit(existing: m),
              onDelete: () async {
                await Backend.instance.deleteMedication(m.id);
                if (mounted) setState(() {});
                widget.onChanged();
              },
            ),
          ),
        _AddBar(count: items.length, cap: _cap, label: t('Add medication'), onAdd: _edit),
      ],
    );
  }
}

// ------------------------------------------------------------- Surgeries ---

class SurgeriesSection extends StatefulWidget {
  final VoidCallback onChanged;
  const SurgeriesSection({super.key, required this.onChanged});

  @override
  State<SurgeriesSection> createState() => _SurgeriesSectionState();
}

class _SurgeriesSectionState extends State<SurgeriesSection> {
  Future<void> _edit({SurgeryRecord? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    var date = existing?.date ?? DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add surgery' : 'Edit surgery'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: t('Surgery name'))),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(prettyDate(date)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setLocal(() => date = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;

    final record = SurgeryRecord(id: existing?.id ?? _nextId('s'), name: name.text.trim(), date: date);
    try {
      if (existing == null) {
        await Backend.instance.addSurgery(record);
      } else {
        await Backend.instance.updateSurgery(record);
      }
      if (mounted) setState(() {});
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = Backend.instance.currentCustomer!.surgeries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          _empty('No surgeries recorded.')
        else
          ...items.map(
            (s) => _RecordTile(
                icon: Icons.healing_rounded,
              title: s.name,
              subtitle: prettyDate(s.date),
              onEdit: () => _edit(existing: s),
              onDelete: () async {
                await Backend.instance.deleteSurgery(s.id);
                if (mounted) setState(() {});
                widget.onChanged();
              },
            ),
          ),
        _AddBar(count: items.length, cap: _cap, label: t('Add surgery'), onAdd: _edit),
      ],
    );
  }
}

// ------------------------------------------------------------- Allergies ---

class AllergiesSection extends StatefulWidget {
  final VoidCallback onChanged;
  const AllergiesSection({super.key, required this.onChanged});

  @override
  State<AllergiesSection> createState() => _AllergiesSectionState();
}

class _AllergiesSectionState extends State<AllergiesSection> {
  Future<void> _edit({AllergyRecord? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    var onset = existing?.onsetDate ?? DateTime.now();
    var active = existing?.active ?? true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add allergy' : 'Edit allergy'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: t('Allergy name'))),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(t('Onset {date}', {'date': prettyDate(onset)})),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: onset,
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setLocal(() => onset = picked);
                },
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: active,
                title: Text(t('Active'), style: const TextStyle(fontSize: 14)),
                onChanged: (v) => setLocal(() => active = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;

    final record = AllergyRecord(id: existing?.id ?? _nextId('a'), name: name.text.trim(), onsetDate: onset, active: active);
    try {
      if (existing == null) {
        await Backend.instance.addAllergy(record);
      } else {
        await Backend.instance.updateAllergy(record);
      }
      if (mounted) setState(() {});
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = Backend.instance.currentCustomer!.allergies;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          _empty('No allergies recorded.')
        else
          ...items.map(
            (a) => _RecordTile(
                icon: Icons.coronavirus_rounded,
              title: a.name,
              subtitle: t('Onset {date} · {state}', {
                'date': prettyDate(a.onsetDate),
                'state': a.active ? t('Active') : t('Inactive'),
              }),
              onEdit: () => _edit(existing: a),
              onDelete: () async {
                await Backend.instance.deleteAllergy(a.id);
                if (mounted) setState(() {});
                widget.onChanged();
              },
            ),
          ),
        _AddBar(count: items.length, cap: _cap, label: t('Add allergy'), onAdd: _edit),
      ],
    );
  }
}

// ------------------------------------------------------------- Insurance ---

class InsuranceSection extends StatefulWidget {
  final VoidCallback onChanged;
  const InsuranceSection({super.key, required this.onChanged});

  @override
  State<InsuranceSection> createState() => _InsuranceSectionState();
}

class _InsuranceSectionState extends State<InsuranceSection> {
  Future<void> _edit({InsuranceRecord? existing}) async {
    final insurer = TextEditingController(text: existing?.insuredWith ?? '');
    final policy = TextEditingController(text: existing?.policyNumber ?? '');
    var start = existing?.startDate ?? DateTime.now();
    var end = existing?.endDate ?? DateTime.now().add(const Duration(days: 365));

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add insurance' : 'Edit insurance'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: insurer, decoration: InputDecoration(labelText: t('Insured with'))),
                TextField(controller: policy, decoration: InputDecoration(labelText: t('Policy number'))),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(t('Start {date}', {'date': prettyDate(start)})),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setLocal(() => start = picked);
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_available, size: 16),
                  label: Text(t('End {date}', {'date': prettyDate(end)})),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: end,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setLocal(() => end = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Save'))),
          ],
        ),
      ),
    );
    if (ok != true || insurer.text.trim().isEmpty) return;

    final record = InsuranceRecord(
      id: existing?.id ?? _nextId('i'),
      insuredWith: insurer.text.trim(),
      policyNumber: policy.text.trim(),
      startDate: start,
      endDate: end,
    );
    try {
      if (existing == null) {
        await Backend.instance.addInsurance(record);
      } else {
        await Backend.instance.updateInsurance(record);
      }
      if (mounted) setState(() {});
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = Backend.instance.currentCustomer!.insurance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (items.isEmpty)
          _empty('No insurance policies recorded.')
        else
          ...items.map(
            (i) => _RecordTile(
                icon: Icons.shield_rounded,
              title: '${i.insuredWith} · ${i.policyNumber}',
              subtitle: t('Valid {from} – {to}', {
                'from': prettyDate(i.startDate),
                'to': prettyDate(i.endDate),
              }),
              onEdit: () => _edit(existing: i),
              onDelete: () async {
                await Backend.instance.deleteInsurance(i.id);
                if (mounted) setState(() {});
                widget.onChanged();
              },
            ),
          ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(icon: const Icon(Icons.add, size: 18), label: Text(t('Add policy')), onPressed: _edit),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Family ---

class FamilySection extends StatefulWidget {
  final VoidCallback onChanged;
  const FamilySection({super.key, required this.onChanged});

  @override
  State<FamilySection> createState() => _FamilySectionState();
}

class _FamilySectionState extends State<FamilySection> {
  Future<void> _edit({FamilyMember? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final rel = TextEditingController(text: existing?.relationship ?? '');
    final contact = TextEditingController(text: existing?.contact ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Add family contact' : 'Edit family contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: t('Name'))),
            TextField(controller: rel, decoration: InputDecoration(labelText: t('Relationship'))),
            TextField(controller: contact, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('Contact number'))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('Save'))),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;

    final record = FamilyMember(
      id: existing?.id ?? _nextId('f'),
      name: name.text.trim(),
      relationship: rel.text.trim(),
      contact: contact.text.trim(),
      active: existing?.active ?? true,
    );
    try {
      if (existing == null) {
        await Backend.instance.addFamilyMember(record);
      } else {
        await Backend.instance.updateFamilyMember(record);
      }
      if (mounted) setState(() {});
      widget.onChanged();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = Backend.instance.currentCustomer!.family.where((f) => f.active).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t('At least one contact is required; room for up to 5.'),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        if (active.isEmpty)
          _empty('No family contacts yet.')
        else
          ...active.map(
            (f) => _RecordTile(
                icon: Icons.person_rounded,
              title: '${f.name} (${f.relationship})',
              subtitle: f.contact,
              onEdit: () => _edit(existing: f),
              onDelete: () async {
                try {
                  await Backend.instance.removeFamilyMember(f.id);
                  if (mounted) setState(() {});
                  widget.onChanged();
                } catch (e) {
                  // `context` here is the builder's, not the State's, so it
                  // needs its own liveness check before opening a dialog.
                  if (context.mounted) _showError(context, e);
                }
              },
            ),
          ),
        _AddBar(count: active.length, cap: _cap, label: t('Add contact'), onAdd: _edit),
      ],
    );
  }
}

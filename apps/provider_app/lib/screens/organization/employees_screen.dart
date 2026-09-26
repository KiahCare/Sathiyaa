import 'package:flutter/material.dart';

import '../../backend.dart';
import '../../models.dart';
import '../../theme/sathiyaa_theme.dart';
import '../../widgets/motion.dart';
import '../../widgets/sathiyaa_ui.dart';
import 'add_edit_employee_screen.dart';
import '../../i18n/l10n.dart';

/// The carers who work for an organisation.
///
/// Rebuilt on the design system. The one behaviour that changed is the one
/// nobody could find: blocking a carer was a **long press on the row**, with no
/// label, no hint and no confirmation. Undiscoverable if you wanted it, and a
/// nasty surprise if you hit it by accident. It is a named action in a sheet
/// now, and it asks first.
class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key});
  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  Future<void> _add() async {
    await push(context, const AddEditEmployeeScreen());
    if (mounted) setState(() {});
  }

  Future<void> _edit(Employee e) async {
    await push(context, AddEditEmployeeScreen(employee: e));
    if (mounted) setState(() {});
  }

  Future<void> _actions(Employee e) async {
    final active = e.status == EmployeeStatus.active;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: SC.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: SC.hairlineCool,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(SC.gutter, 6, SC.gutter, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(e.name, style: ST.h2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: SC.blueBright),
              title: Text(t('Edit their details'), style: ST.bodyStrong),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(active ? Icons.block_rounded : Icons.check_circle_rounded,
                  color: active ? SC.red : SC.green),
              title: Text(
                active ? 'Stop allocating work to them' : 'Allow work again',
                style: ST.bodyStrong.copyWith(color: active ? SC.red : SC.ink),
              ),
              subtitle: Text(
                active
                    ? 'They keep any visit already booked.'
                    : 'They can be allocated new visits again.',
                style: ST.small.copyWith(fontSize: 12),
              ),
              onTap: () => Navigator.pop(context, 'toggle'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'edit') {
      await _edit(e);
      return;
    }

    final next = active ? EmployeeStatus.blocked : EmployeeStatus.active;
    if (active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: SC.surface,
          title: Text(t('Stop allocating work?'), style: ST.h2),
          content: Text(
            '${e.name} will not be given new visits. Anything already booked '
            'stays with them.',
            style: ST.body,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: SC.red),
              child: Text(t('Stop')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }

    final messenger = ScaffoldMessenger.of(context);
    try {
      await Backend.instance.setEmployeeStatus(e.id, next);
      if (!mounted) return;
      setState(() {});
      messenger.showSnackBar(SnackBar(
        content: Text(active
            ? '${e.name} will not be allocated new visits.'
            : '${e.name} can take work again.'),
      ));
    } catch (err) {
      messenger.showSnackBar(
        SnackBar(content: Text(err.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = Backend.instance.currentProvider!.employees;
    // How many can actually be sent to a family: approved by Sathiyaa and not
    // blocked by the organisation. "Active" counted the second alone, so a
    // team of ten unchecked carers read as "10 of 10 active".
    final active = employees
        .where((e) => e.status == EmployeeStatus.active && e.verified)
        .length;

    return Scaffold(
      backgroundColor: SC.paper,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: SC.blueBright,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_rounded),
        label: Text(t('Add a carer')),
      ),
      body: Column(
        children: [
          BrandHeader(
            curved: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, SC.gutter, 14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left_rounded,
                        color: Colors.white, size: 30),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t('Your carers'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(t('The people who visit families for you'),
                            style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                      ],
                    ),
                  ),
                  if (employees.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(SC.rPill),
                      ),
                      child: Text(
                          t('{active} of {total} verified',
                              {'active': active, 'total': employees.length}),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: employees.isEmpty
                ? Center(
                    child: PagePad(
                      child: EmptyState(
                        icon: Icons.group_add_rounded,
                        title: t('Nobody on the team yet'),
                        message: t('Add the carers who work for you. Once they are here you can allocate visits to them and see what each of them has done.'),
                        actionLabel: t('Add a carer'),
                        onAction: _add,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(SC.gutter, 18, SC.gutter, 96),
                    children: staggered([
                      for (final e in employees) _row(e),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }

  /// The chip.
  ///
  /// "Verified" is reserved for a carer an administrator has actually
  /// approved. Everything else says what is being waited on, and whose job it
  /// is -- an organisation that reads "Incomplete" can do something about it,
  /// and one that reads "With Sathiyaa" knows not to.
  String _chipLabel(Employee e) {
    switch (e.approvalStatus) {
      case 'approved':
        return t('Verified');
      case 'hold':
        return t('On hold');
      case 'rejected':
        return t('Rejected');
      default:
        return e.documentsComplete ? t('With Sathiyaa') : t('Incomplete');
    }
  }

  ChipTone _chipTone(Employee e) {
    switch (e.approvalStatus) {
      case 'approved':
        return ChipTone.good;
      case 'rejected':
        return ChipTone.bad;
      case 'hold':
        return ChipTone.warn;
      default:
        return e.documentsComplete ? ChipTone.info : ChipTone.warn;
    }
  }

  String? _note(Employee e) {
    if (e.approvalStatus == 'approved') return null;
    if (e.approvalStatus == 'hold') return t('Sathiyaa has paused this carer');
    if (e.approvalStatus == 'rejected') return t('Sathiyaa did not approve this carer');
    if (!e.documentsComplete) {
      return e.policeVerification.uploaded
          ? t('Police verification out of date')
          : t('Documents missing — send them to be checked');
    }
    return t('Waiting for Sathiyaa to check them');
  }

  IconData _noteIcon(Employee e) => switch (e.approvalStatus) {
        'rejected' => Icons.block_rounded,
        'hold' => Icons.pause_circle_rounded,
        _ => e.documentsComplete
            ? Icons.hourglass_top_rounded
            : Icons.gpp_maybe_rounded,
      };

  Color _noteColour(Employee e) => switch (e.approvalStatus) {
        'rejected' => SC.red,
        _ => e.documentsComplete && e.approvalStatus == 'pending'
            ? SC.blueBright
            : SC.amber,
      };

  Widget _row(Employee e) {
    final active = e.status == EmployeeStatus.active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
        onTap: () => _actions(e),
        child: Row(
          children: [
            InitialsAvatar(name: e.name, size: 46, radius: 14),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.name,
                      style: ST.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                      e.gender.isEmpty
                          ? e.mobile
                          : t('{gender} · {mobile}',
                              {'gender': e.gender, 'mobile': e.mobile}),
                      style: ST.small.copyWith(fontSize: 12.5)),
                  // Why they cannot be allocated, on the row, rather than
                  // three taps away inside their record.
                  if (active && _note(e) != null) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(_noteIcon(e), size: 13, color: _noteColour(e)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _note(e)!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ST.small.copyWith(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _noteColour(e)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            StatusChip(
              !active ? e.status.label : _chipLabel(e),
              tone: !active ? ChipTone.bad : _chipTone(e),
              dense: true,
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, size: 20, color: SC.inkSoft),
              tooltip: t('More'),
              onPressed: () => _actions(e),
            ),
          ],
        ),
      ),
    );
  }
}

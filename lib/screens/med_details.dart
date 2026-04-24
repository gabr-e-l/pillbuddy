// lib/screens/med_details.dart
//
// Displays and edits the details of a single medication.
// Wired to Firestore via MedicationService:
//   - Every picker change auto-saves to Firestore.
//   - Delete removes the document and pops the screen.

import 'package:flutter/material.dart';
import '../models/medication_model.dart';
import '../services/medication_service.dart';
import 'calendar_modal.dart';
import 'med_details_data.dart';
import 'med_details_modals.dart';

class MedDetailsScreen extends StatefulWidget {
  final String medId;
  final MedicationModel initialMed;

  const MedDetailsScreen({
    super.key,
    required this.medId,
    required this.initialMed,
  });

  @override
  State<MedDetailsScreen> createState() => _MedDetailsScreenState();
}

class _MedDetailsScreenState extends State<MedDetailsScreen> {
  final _service = MedicationService();
  late MedDetailsData _data;
  bool _isSaving = false;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    // Initialise from the MedicationModel passed in — no extra Firestore fetch needed
    _data = MedDetailsData.fromModel(widget.initialMed);
  }

  // ── Persist helpers ────────────────────────────────────────────────────────

  /// Converts current _data back to a MedicationModel and updates Firestore.
  Future<void> _saveChanges() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final updated = widget.initialMed.copyWith(
        name: _data.name,
        type: _data.type,
        dose: _data.doseAmount,
        unit: _data.doseForm,
        freqNumber: _data.freqNumber,
        freqUnit: _data.freqUnit,
        startingDate: _data.startDate,
        hour: _data.hour,
        minute: _data.minute,
        period: _data.period,
        note: _data.note,
        stockCount: _data.stockCount,
        stockUnit: _data.stockUnit,
      );
      await _service.updateMedication(widget.medId, updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save changes: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Picker handlers ────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await CalendarModal.show(
      context,
      initialDate: _data.startDate,
    );
    if (picked != null) {
      setState(() => _data.startDate = picked);
      await _saveChanges();
    }
  }

  Future<void> _pickTime() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => TimePickerModal(
        hour: _data.hour,
        minute: _data.minute,
        period: _data.period,
        onDone: (h, m, p) async {
          setState(() {
            _data.hour = h;
            _data.minute = m;
            _data.period = p;
          });
          await _saveChanges();
        },
      ),
    );
  }

  Future<void> _pickFrequency() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => FrequencyPickerModal(
        freqNumber: _data.freqNumber,
        freqUnit: _data.freqUnit,
        onDone: (n, u) async {
          setState(() {
            _data.freqNumber = n;
            _data.freqUnit = u;
          });
          await _saveChanges();
        },
      ),
    );
  }

  Future<void> _pickDose() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => DosePickerModal(
        doseAmount: _data.doseAmount,
        doseForm: _data.doseForm,
        onDone: (amount, form) async {
          setState(() {
            _data.doseAmount = amount;
            _data.doseForm = form;
          });
          await _saveChanges();
        },
      ),
    );
  }

  Future<void> _pickStock() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => StockPickerModal(
        stockCount: _data.stockCount,
        stockUnit: _data.stockUnit,
        onDone: (count, unit) async {
          setState(() {
            _data.stockCount = count;
            _data.stockUnit = unit;
          });
          await _saveChanges();
        },
      ),
    );
  }

  Future<void> _pickNote() async {
    final controller = TextEditingController(text: _data.note);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: NoteEditModal(
          controller: controller,
          onDone: () async {
            setState(() => _data.note = controller.text.trim());
            Navigator.pop(context);
            await _saveChanges();
          },
        ),
      ),
    );
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Medication'),
        content: Text('Are you sure you want to delete "${_data.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx); // close dialog
              await _deleteMedication();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMedication() async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);
    try {
      await _service.deleteMedication(widget.medId);
      if (!mounted) return;
      Navigator.pop(context); // go back to My Meds
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${_data.name}" deleted.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FF),
      appBar: _buildAppBar(),
      body: _isDeleting
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIdentityCard(),
                  const SizedBox(height: 20),
                  _buildScheduleSection(),
                  const SizedBox(height: 20),
                  _buildDoseSection(),
                  const SizedBox(height: 12),
                  _buildStatsCard(),
                  const SizedBox(height: 24),
                  _buildDeleteButton(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFFF4F7FF),
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.chevron_left, size: 30, color: Colors.black),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Medication details',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      centerTitle: true,
      actions: [
        if (_isSaving)
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
      ],
    );
  }

  // ── Identity card ──────────────────────────────────────────────────────────

  Widget _buildIdentityCard() {
    return _Card(
      child: Row(
        children: [
          Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset(_data.asset, fit: BoxFit.contain),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _data.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Switch(
            value: _data.isActive,
            activeThumbColor: const Color(0xFF3B71FE),
            activeTrackColor:
                const Color(0xFF3B71FE).withValues(alpha: 0.4),
            onChanged: (val) async {
              setState(() => _data.isActive = val);
              // Persist the isActive flag as a partial update
              try {
                await _service.updateFields(
                  widget.medId,
                  {'isActive': val},
                );
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }

  // ── Schedule section ───────────────────────────────────────────────────────

  Widget _buildScheduleSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(text: 'Schedule'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoTile(
                label: 'Start date',
                value: _data.formattedDate,
                icon: Icons.calendar_today_outlined,
                onTap: _pickDate,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoTile(
                label: 'Time',
                value: _data.formattedTime,
                icon: Icons.access_time_outlined,
                onTap: _pickTime,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InfoTile(
          label: 'Frequency',
          value: _data.formattedFreq,
          icon: Icons.alarm_outlined,
          fullWidth: true,
          onTap: _pickFrequency,
        ),
      ],
    );
  }

  // ── Dose section ───────────────────────────────────────────────────────────

  Widget _buildDoseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(text: 'Dose'),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _InfoTile(
                label: 'Dose amount',
                value: _data.formattedDose,
                icon: Icons.edit_outlined,
                onTap: _pickDose,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _InfoTile(
                label: 'Note',
                value: _data.note.isEmpty ? 'Write note' : _data.note,
                icon: Icons.notes_outlined,
                valueColor: _data.note.isEmpty ? Colors.grey : null,
                onTap: _pickNote,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InfoTile(
          label: 'Initial stock',
          value: _data.formattedStock,
          icon: Icons.sync_alt_outlined,
          fullWidth: true,
          onTap: _pickStock,
        ),
      ],
    );
  }

  // ── Stats card ─────────────────────────────────────────────────────────────

  Widget _buildStatsCard() {
    final daysSinceStart = _data.startDate != null
        ? DateTime.now().difference(_data.startDate!).inDays
        : 0;

    return _Card(
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.medication_outlined,
              color: Colors.black54,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Stock: ${_data.stockCount} ${_data.stockUnit}',
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(width: 16),
          Text(
            daysSinceStart > 0
                ? 'Started $daysSinceStart days ago'
                : 'Starting today',
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  // ── Delete button ──────────────────────────────────────────────────────────

  Widget _buildDeleteButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _isDeleting ? null : _confirmDelete,
        icon: const Icon(Icons.delete_outline, color: Colors.red),
        label: const Text(
          'Delete Medication',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }
}

// ── Reusable UI components ────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  final bool fullWidth;
  final Color? valueColor;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.fullWidth = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      color: valueColor ?? Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }
}
// calendar_modal.dart
import 'package:flutter/material.dart';

class CalendarModal extends StatefulWidget {
  const CalendarModal({super.key, this.initialDate});

  final DateTime? initialDate;

  /// Shows the bottom-sheet and returns the chosen [DateTime], or null if
  /// the user dismissed without picking.
  static Future<DateTime?> show(
    BuildContext context, {
    DateTime? initialDate,
  }) {
    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => CalendarModal(initialDate: initialDate),
    );
  }

  @override
  State<CalendarModal> createState() => _CalendarModalState();
}

class _CalendarModalState extends State<CalendarModal> {
  late DateTime _viewMonth;
  DateTime? _picked;

  @override
  void initState() {
    super.initState();
    _viewMonth = widget.initialDate ?? DateTime.now();
    _picked = widget.initialDate;
  }

  void _shiftMonth(int delta) =>
      setState(() => _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta));

  String _monthName(int month) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][month - 1];

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_viewMonth.year, _viewMonth.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(_viewMonth.year, _viewMonth.month);
    // Monday-based offset
    final startOffset = (firstDay.weekday - 1) % 7;

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          _buildMonthNav(),
          _buildWeekdayRow(),
          const SizedBox(height: 8),
          _buildGrid(startOffset, daysInMonth),
          const SizedBox(height: 16),
          _buildDoneButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Row(
        children: [
          const Text(
            'Select date',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNav() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shiftMonth(-1),
          ),
          Text(
            '${_monthName(_viewMonth.month)} ${_viewMonth.year}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shiftMonth(1),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
            .map(
              (d) => SizedBox(
                width: 36,
                child: Center(
                  child: Text(
                    d,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildGrid(int startOffset, int daysInMonth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 1,
        ),
        itemCount: startOffset + daysInMonth,
        itemBuilder: (_, index) {
          if (index < startOffset) return const SizedBox();
          final day = index - startOffset + 1;
          final date = DateTime(_viewMonth.year, _viewMonth.month, day);
          final isSelected = _picked != null && DateUtils.isSameDay(_picked, date);

          return GestureDetector(
            onTap: () => setState(() => _picked = date),
            child: Container(
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue : null,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  '$day',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.black87,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDoneButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _picked == null
              ? null
              : () => Navigator.pop(context, _picked),
          style: ElevatedButton.styleFrom(
            backgroundColor: _picked != null ? Colors.blue : Colors.grey[300],
            foregroundColor:
                _picked != null ? Colors.white : Colors.grey[500],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            elevation: 0,
          ),
          child: const Text('Done', style: TextStyle(fontSize: 16)),
        ),
      ),
    );
  }
}

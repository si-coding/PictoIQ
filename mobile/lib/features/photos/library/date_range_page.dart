import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/core/config/app_colors.dart';

/// Picks a from and to date. "Apply" (with a tick) is at the left of the top bar and
/// the close button at the right. Tap a day to start, tap another to finish;
/// tap again to start over.
class DateRangePage extends StatefulWidget {
  const DateRangePage({
    super.key,
    required this.firstDate,
    required this.lastDate,
    this.initialRange,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange? initialRange;

  @override
  State<DateRangePage> createState() => _DateRangePageState();
}

class _DateRangePageState extends State<DateRangePage> {
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  DateTime? _start;
  DateTime? _end;

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRange;
    if (initial != null) {
      _start = _day(initial.start);
      _end = _day(initial.end);
    }
  }

  int get _monthCount =>
      (widget.lastDate.year - widget.firstDate.year) * 12 +
      widget.lastDate.month -
      widget.firstDate.month +
      1;

  void _tap(DateTime day) {
    setState(() {
      if (_start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(_start!)) {
        _start = day;
      } else {
        _end = day;
      }
    });
  }

  String _label(DateTime? d) =>
      d == null ? '—' : '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year}';

  Widget _month(DateTime first) {
    final last = DateTime(first.year, first.month + 1, 0);
    final offset = (first.weekday + 6) % 7; // Monday first
    final cells = <Widget>[
      for (var i = 0; i < offset; i++) const SizedBox.shrink(),
      for (var d = 1; d <= last.day; d++) _dayCell(DateTime(first.year, first.month, d)),
    ];
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 6),
            child: Text(
              '${_months[first.month - 1]} ${first.year}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < cells.length; row += 7)
            SizedBox(
              height: 44,
              child: Row(
                children: [for (final cell in cells.sublist(row, row + 7)) Expanded(child: cell)],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime day) {
    final disabled =
        day.isBefore(_day(widget.firstDate)) || day.isAfter(_day(widget.lastDate));
    final isStart = _start != null && day == _start;
    final isEnd = _end != null && day == _end;
    final inside =
        _start != null && _end != null && day.isAfter(_start!) && day.isBefore(_end!);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: disabled ? null : () => _tap(day),
      child: Container(
        margin: EdgeInsets.symmetric(
          vertical: 3,
          horizontal: inside ? 0 : 2,
        ),
        decoration: BoxDecoration(
          color: isStart || isEnd
              ? AppColors.primary
              : inside
              ? AppColors.tint
              : null,
          borderRadius: BorderRadius.circular(inside ? 0 : 20),
        ),
        alignment: Alignment.center,
        child: Text(
          '${day.day}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: isStart || isEnd ? FontWeight.w800 : FontWeight.w500,
            color: isStart || isEnd
                ? Colors.white
                : disabled
                ? Colors.black26
                : Colors.black87,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _start != null;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 136,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
          child: FilledButton.icon(
            onPressed: ready
                ? () => Navigator.of(context).pop(
                    DateTimeRange(start: _start!, end: _end ?? _start!),
                  )
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Apply', maxLines: 1, softWrap: false),
          ),
        ),
        title: const Text('Select dates'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('From ${_label(_start)}'),
                Text('To ${_label(_end ?? _start)}'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _monthCount,
              itemBuilder: (context, index) => _month(
                DateTime(
                  widget.lastDate.year,
                  widget.lastDate.month - index,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

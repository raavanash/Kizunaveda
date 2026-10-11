import '../../../../core/constants/app_constants.dart';

/// Available outlet filter options for executive reporting.
enum OutletFilter {
  all,
  jaipur,
  neemrana;

  String get label {
    switch (this) {
      case OutletFilter.all:
        return 'All Stores';
      case OutletFilter.jaipur:
        return 'Jaipur Retail';
      case OutletFilter.neemrana:
        return 'Neemrana Retail';
    }
  }

  String? get locationId {
    switch (this) {
      case OutletFilter.all:
        return null;
      case OutletFilter.jaipur:
        return LocationConstants.jaipurId;
      case OutletFilter.neemrana:
        return LocationConstants.neemranaId;
    }
  }
}

/// Standard date range filter presets.
enum DateRangePreset {
  allTime,
  today,
  last7Days,
  thisMonth,
  custom;

  String get label {
    switch (this) {
      case DateRangePreset.allTime:
        return 'All Time';
      case DateRangePreset.today:
        return 'Today';
      case DateRangePreset.last7Days:
        return 'Last 7 Days';
      case DateRangePreset.thisMonth:
        return 'This Month';
      case DateRangePreset.custom:
        return 'Custom';
    }
  }
}

/// Dynamic date range filter supporting presets and custom date boundaries.
class DateRangeFilter {
  final DateRangePreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;

  const DateRangeFilter({
    this.preset = DateRangePreset.allTime,
    this.customStart,
    this.customEnd,
  });

  const DateRangeFilter.allTime() : this(preset: DateRangePreset.allTime);
  const DateRangeFilter.today() : this(preset: DateRangePreset.today);
  const DateRangeFilter.last7Days() : this(preset: DateRangePreset.last7Days);
  const DateRangeFilter.thisMonth() : this(preset: DateRangePreset.thisMonth);

  /// Check whether a given timestamp falls within the active filter window.
  bool matches(DateTime timestamp) {
    if (preset == DateRangePreset.allTime && customStart == null && customEnd == null) {
      return true;
    }

    final local = timestamp.toLocal();
    final now = DateTime.now();

    DateTime start;
    DateTime end;

    if (preset == DateRangePreset.custom && customStart != null && customEnd != null) {
      start = DateTime(customStart!.year, customStart!.month, customStart!.day, 0, 0, 0);
      end = DateTime(customEnd!.year, customEnd!.month, customEnd!.day, 23, 59, 59, 999);
    } else {
      switch (preset) {
        case DateRangePreset.allTime:
          return true;
        case DateRangePreset.today:
          start = DateTime(now.year, now.month, now.day, 0, 0, 0);
          end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
          break;
        case DateRangePreset.last7Days:
          final startDay = now.subtract(const Duration(days: 6));
          start = DateTime(startDay.year, startDay.month, startDay.day, 0, 0, 0);
          end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
          break;
        case DateRangePreset.thisMonth:
          start = DateTime(now.year, now.month, 1, 0, 0, 0);
          end = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
          break;
        case DateRangePreset.custom:
          return true;
      }
    }

    return (local.isAfter(start) || local.isAtSameMomentAs(start)) &&
        (local.isBefore(end) || local.isAtSameMomentAs(end));
  }
}

import 'package:flutter/material.dart';

import '../../../core/utils/date_x.dart';
import '../../../domain/search.dart';

/// Destination / dates / guests, in one compact card.
class StaySelector extends StatelessWidget {
  const StaySelector({
    required this.query,
    required this.destinations,
    required this.onDestinationChanged,
    required this.onStayChanged,
    required this.onOccupancyChanged,
    required this.onSearch,
    super.key,
  });

  final SearchQuery query;
  final List<Destination> destinations;
  final ValueChanged<Destination> onDestinationChanged;
  final ValueChanged<DateRange> onStayChanged;
  final ValueChanged<Occupancy> onOccupancyChanged;
  final VoidCallback onSearch;

  Future<void> _pickDates(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      // Hotel rate calendars are typically loaded ~500 days out; offering more
      // just produces searches the CRS cannot price.
      lastDate: now.addDays(500),
      initialDateRange: DateTimeRange(
        start: query.stay.checkIn,
        end: query.stay.checkOut,
      ),
      helpText: 'Select your stay',
    );
    if (picked != null && picked.end.isAfter(picked.start)) {
      onStayChanged(DateRange(picked.start, picked.end));
    }
  }

  Future<void> _pickGuests(BuildContext context) async {
    Occupancy draft = query.occupancy;
    final Occupancy? result = await showModalBottomSheet<Occupancy>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          Widget stepper(
            String label,
            int value,
            ValueChanged<int> onChanged, {
            int min = 1,
            int max = 8,
          }) {
            return ListTile(
              title: Text(label),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    onPressed: value > min
                        ? () => setSheetState(() => onChanged(value - 1))
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  SizedBox(
                    width: 28,
                    child: Text('$value', textAlign: TextAlign.center),
                  ),
                  IconButton(
                    onPressed: value < max
                        ? () => setSheetState(() => onChanged(value + 1))
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            );
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const SizedBox(height: 12),
                stepper(
                  'Adults',
                  draft.adults,
                  (int v) => draft = draft.copyWith(adults: v),
                ),
                stepper(
                  'Children',
                  draft.children.length,
                  (int v) => draft = draft.copyWith(
                    // Child ages drive pricing; 8 is a sane default the guest
                    // can refine before booking.
                    children: List<int>.filled(v, 8),
                  ),
                  min: 0,
                  max: 4,
                ),
                stepper(
                  'Rooms',
                  draft.rooms,
                  (int v) => draft = draft.copyWith(rooms: v),
                  max: 4,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(draft),
                      child: const Text('Done'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (result != null) {
      onOccupancyChanged(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    // A field-like label rather than the theme's uppercase action stamp: these
    // two buttons stand in for inputs, and setting them in the button voice
    // would make the dates shout louder than the search.
    final ButtonStyle fieldStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(64, 50),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      foregroundColor: colors.onSurface,
    );

    // Full width against a hairline rather than a floating rounded card: the
    // results below run edge to edge, and a card here would leave the search
    // sitting on a different grid from everything it produces.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          children: <Widget>[
            // DropdownButton inside an InputDecorator rather than
            // DropdownButtonFormField: that widget's selected-value argument was
            // renamed (`value` -> `initialValue`) in a recent Flutter release, so
            // either spelling pins the project to one side of that change. This
            // composition has been stable for years and looks identical.
            InputDecorator(
              decoration: InputDecoration(
                labelText: 'Destination',
                prefixIcon: const Icon(Icons.place_outlined, size: 19),
                labelStyle: theme.textTheme.bodyMedium,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(2),
                  borderSide: BorderSide(color: colors.outlineVariant),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: query.destination.id,
                  isExpanded: true,
                  items: destinations
                      .map(
                        (Destination d) => DropdownMenuItem<String>(
                          value: d.id,
                          child: Text(d.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? id) {
                    if (id == null) {
                      return;
                    }
                    onDestinationChanged(
                      destinations.firstWhere((Destination d) => d.id == id),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDates(context),
                    style: fieldStyle,
                    icon: const Icon(Icons.calendar_month_outlined, size: 17),
                    label: Text(
                      '${formatShortDate(query.stay.checkIn)} – '
                      '${formatShortDate(query.stay.checkOut)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickGuests(context),
                    style: fieldStyle,
                    icon: const Icon(Icons.person_outline, size: 17),
                    label: Text(
                      query.occupancy.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSearch,
                child: Text(
                  'SEARCH · ${query.stay.nights} NIGHT'
                  '${query.stay.nights == 1 ? '' : 'S'}',
                ),
              ),
            ),
            if (query.promotionCode != null) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: Text('Offer ${query.promotionCode}'),
                  avatar: const Icon(Icons.local_offer_outlined, size: 16),
                  labelStyle: theme.textTheme.labelMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

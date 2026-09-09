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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            // DropdownButton inside an InputDecorator rather than
            // DropdownButtonFormField: that widget's selected-value argument was
            // renamed (`value` -> `initialValue`) in a recent Flutter release, so
            // either spelling pins the project to one side of that change. This
            // composition has been stable for years and looks identical.
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Destination',
                prefixIcon: Icon(Icons.place_outlined),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
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
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDates(context),
                    icon: const Icon(Icons.calendar_month_outlined, size: 18),
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
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(
                      query.occupancy.label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search),
                label: Text(
                  '${query.stay.nights} night'
                  '${query.stay.nights == 1 ? '' : 's'} · Search',
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

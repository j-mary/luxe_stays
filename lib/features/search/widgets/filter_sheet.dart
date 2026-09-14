import 'package:flutter/material.dart';

import '../../../core/utils/money.dart';
import '../../../domain/search.dart';

/// Filter and sort controls.
///
/// Applied client-side over the availability response the CRS already returned.
/// That is a deliberate trade: a shop request against SynXis is expensive and
/// rate-limited, so filtering 60 offers in memory beats asking the CRS again
/// every time the guest moves a slider. Filters that genuinely change what the
/// CRS returns - promotion and corporate codes, member-rate access - are the
/// exception and do trigger a new request.
class FilterSheet extends StatefulWidget {
  const FilterSheet({required this.initial, required this.currency, super.key});

  final SearchFilters initial;
  final String currency;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late SearchFilters _filters = widget.initial;

  static const int _maxRateMinor = 300000; // 3,000.00 per night

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Refine', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 20),
              Text('Sort by', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: SortOption.values
                    .map(
                      (SortOption option) => ChoiceChip(
                        label: Text(option.label),
                        selected: _filters.sort == option,
                        onSelected: (_) => setState(
                          () => _filters = _filters.copyWith(sort: option),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 24),
              Text('Star rating', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <int>[0, 4, 5]
                    .map(
                      (int stars) => ChoiceChip(
                        label: Text(stars == 0 ? 'Any' : '$stars+'),
                        selected: _filters.minStars == stars,
                        onSelected: (_) => setState(
                          () => _filters = _filters.copyWith(minStars: stars),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Text('Max nightly rate', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    _filters.maxNightlyRateMinor == null
                        ? 'Any'
                        : Money(
                            _filters.maxNightlyRateMinor!,
                            widget.currency,
                          ).format(),
                    style: theme.textTheme.labelLarge,
                  ),
                ],
              ),
              Slider(
                value: (_filters.maxNightlyRateMinor ?? _maxRateMinor)
                    .toDouble()
                    .clamp(20000.0, _maxRateMinor.toDouble())
                    .toDouble(),
                min: 20000,
                max: _maxRateMinor.toDouble(),
                divisions: 28,
                onChanged: (double value) => setState(
                  () => _filters = _filters.copyWith(
                    maxNightlyRateMinor: value.round(),
                    clearMaxRate: value >= _maxRateMinor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('Board', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: MealPlan.values
                    .map(
                      (MealPlan plan) => FilterChip(
                        label: Text(plan.label),
                        selected: _filters.mealPlans.contains(plan),
                        onSelected: (bool selected) => setState(() {
                          final Set<MealPlan> next = Set<MealPlan>.from(
                            _filters.mealPlans,
                          );
                          if (selected) {
                            next.add(plan);
                          } else {
                            next.remove(plan);
                          }
                          _filters = _filters.copyWith(mealPlans: next);
                        }),
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Free cancellation only'),
                value: _filters.freeCancellationOnly,
                onChanged: (bool value) => setState(
                  () =>
                      _filters = _filters.copyWith(freeCancellationOnly: value),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Member rates only'),
                subtitle: const Text(
                  'Rates released by the property to LuxeStays Rewards members',
                ),
                value: _filters.memberRatesOnly,
                onChanged: (bool value) => setState(
                  () => _filters = _filters.copyWith(memberRatesOnly: value),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(const SearchFilters()),
                      child: const Text('Clear all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_filters),
                      child: const Text('Show results'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

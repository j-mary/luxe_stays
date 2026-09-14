import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/error/failure.dart';
import '../../core/utils/date_x.dart';
import '../../data/hotel_repository.dart';
import '../../domain/cart.dart';
import '../../domain/hotel.dart';
import '../../domain/media.dart';
import '../../domain/rate.dart';
import '../../shared/widgets/app_snack_bar.dart';
import '../../shared/widgets/app_states.dart';
import '../../shared/widgets/media_image.dart';
import '../../shared/widgets/section_heading.dart';
import '../cart/cart_controller.dart';
import '../search/search_controller.dart';
import 'hotel_detail_controller.dart';

class HotelDetailScreen extends ConsumerWidget {
  const HotelDetailScreen({required this.args, super.key});

  final HotelDetailArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<HotelDetail> detail = ref.watch(
      hotelDetailProvider(args.hotelId),
    );

    return Scaffold(
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Scaffold(
          appBar: AppBar(title: Text(args.hotelName)),
          body: FailureView(
            failure: error is Failure
                ? error
                : ServerFailure(
                    developerMessage: error.toString(),
                    statusCode: 0,
                  ),
            onRetry: () => ref.invalidate(hotelDetailProvider(args.hotelId)),
          ),
        ),
        data: (HotelDetail data) => _HotelDetailBody(detail: data),
      ),
    );
  }
}

class _HotelDetailBody extends ConsumerWidget {
  const _HotelDetailBody({required this.detail});

  final HotelDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Hotel hotel = detail.hotel;
    final ThemeData theme = Theme.of(context);
    final Map<String, List<RoomOffer>> byRoom = detail.offersByRoomType;

    return CustomScrollView(
      slivers: <Widget>[
        // A tall full-bleed hero with the property name set over it in the
        // display serif. The scrim is a gradient rather than a flat overlay so
        // the top of the photograph stays untouched: it only darkens where type
        // actually sits, which is the difference between a dimmed picture and a
        // legible caption. The bar keeps the ink plate as its own background,
        // so the light icons stay legible once it collapses.
        SliverAppBar(
          expandedHeight: 340,
          pinned: true,
          backgroundColor: AppTheme.plate,
          foregroundColor: AppTheme.onPlate,
          iconTheme: const IconThemeData(color: AppTheme.onPlate),
          flexibleSpace: FlexibleSpaceBar(
            titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            title: Text(
              hotel.name,
              style: AppTheme.serif(size: 21, color: AppTheme.onPlate),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                MediaImage(
                  asset: hotel.heroImage,
                  transform: MediaTransform.hero,
                  borderRadius: BorderRadius.zero,
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.center,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0x00191510), Color(0xC2191510)],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  hotel.locationLabel.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                ),
                if (hotel.editorial != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    hotel.editorial!.headline,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 14),
                  Text(hotel.editorial!.body, style: theme.textTheme.bodyLarge),
                  if (hotel.editorial!.signatureExperience != null) ...<Widget>[
                    const SizedBox(height: 20),
                    _SignatureCard(text: hotel.editorial!.signatureExperience!),
                  ],
                  const SizedBox(height: 10),
                  // Provenance matters when three systems feed one screen: this
                  // line is the CMS's, not the CRS's.
                  Text(
                    'Editorial content from the CMS'
                    '${hotel.editorial!.updatedAt != null ? ' · updated '
                              '${formatShortDate(hotel.editorial!.updatedAt!)}' : ''}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
                if (hotel.amenities.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: hotel.amenities
                        .map((String a) => Chip(label: Text(a)))
                        .toList(growable: false),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hotel.gallery.length > 1)
          SliverToBoxAdapter(
            child: _Gallery(assets: hotel.gallery.skip(1).toList()),
          ),
        const SliverToBoxAdapter(child: SectionHeading(label: 'ROOMS & RATES')),
        if (detail.offers.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                detail.offersFailure ??
                    'No rooms are available for the selected dates.',
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: byRoom.length,
            itemBuilder: (BuildContext context, int index) {
              final String code = byRoom.keys.elementAt(index);
              final List<RoomOffer> offers = byRoom[code]!;
              return _RoomSection(hotel: hotel, offers: offers);
            },
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed(
                Routes.bookingEngine,
                arguments: BookingEngineArgs(
                  hotelId: hotel.id,
                  hotelName: hotel.name,
                  query: ref.read(searchProvider).query,
                ),
              ),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('Packages & add-ons (booking engine)'),
            ),
          ),
        ),
      ],
    );
  }
}

class _SignatureCard extends StatelessWidget {
  const _SignatureCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: colors.secondary, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'SIGNATURE EXPERIENCE',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.secondary,
            ),
          ),
          const SizedBox(height: 8),
          // Set in the serif: it is the one line of copy on the screen the
          // brand wants read as a promise rather than as a description.
          Text(text, style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({required this.assets});

  final List<MediaAsset> assets;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 194,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        itemCount: assets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) => SizedBox(
          width: 226,
          child: MediaImage(
            asset: assets[index],
            transform: MediaTransform.thumbnail,
            borderRadius: BorderRadius.zero,
          ),
        ),
      ),
    );
  }
}

class _RoomSection extends ConsumerWidget {
  const _RoomSection({required this.hotel, required this.offers});

  final Hotel hotel;
  final List<RoomOffer> offers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final RoomType room = offers.first.roomType;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(room.name, style: theme.textTheme.titleMedium),
              if (room.description.isNotEmpty) ...<Widget>[
                const SizedBox(height: 6),
                Text(room.description, style: theme.textTheme.bodySmall),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  <String>[
                    if (room.sizeSqm != null) '${room.sizeSqm} m²',
                    if (room.bedding.isNotEmpty) room.bedding,
                    'Sleeps ${room.maxOccupancy}',
                  ].join(' · '),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              const Divider(height: 24),
              ...offers.map(
                (RoomOffer offer) => _OfferRow(hotel: hotel, offer: offer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfferRow extends ConsumerWidget {
  const _OfferRow({required this.hotel, required this.offer});

  final Hotel hotel;
  final RoomOffer offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Cart cart = ref.watch(cartProvider);
    final bool inCart = cart.items.any(
      (CartItem item) => item.offer.offerId == offer.offerId,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        offer.ratePlanName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (offer.isMemberRate) ...<Widget>[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.workspace_premium_rounded,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ],
                ),
                Text(offer.mealPlan.label, style: theme.textTheme.bodySmall),
                Text(
                  offer.cancellationPolicy.shortLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: offer.cancellationPolicy.isNonRefundable
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
                if (offer.inclusions.isNotEmpty)
                  Text(
                    offer.inclusions.join(' · '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(offer.total.format(), style: theme.textTheme.titleLarge),
              Text(
                'total · ${offer.stay.nights} night'
                '${offer.stay.nights == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall,
              ),
              const SizedBox(height: 6),
              FilledButton.tonal(
                onPressed: inCart
                    ? null
                    : () {
                        ref
                            .read(cartProvider.notifier)
                            .add(hotel: hotel, offer: offer);
                        showAppSnackBar(context, 'Added to your cart');
                      },
                child: Text(inCart ? 'In cart' : 'Select'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

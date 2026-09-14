import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error/failure.dart';
import '../../core/result.dart';
import '../../data/hotel_repository.dart';
import '../account/session_controller.dart';
import '../search/search_controller.dart';

/// Detail for one property, keyed by hotel id.
///
/// A `FutureProvider.family` rather than a hand-rolled controller: the screen
/// is read-only, so all it needs is "fetch this, cache it, expose loading and
/// error". `autoDispose` keeps a 400-property catalogue from accumulating in
/// memory as the guest browses.
final hotelDetailProvider = FutureProvider.autoDispose
    .family<HotelDetail, String>((Ref ref, String hotelId) async {
      final Result<HotelDetail> result = await ref
          .watch(hotelRepositoryProvider)
          .detail(
            hotelId: hotelId,
            query: ref.watch(searchProvider).query,
            membershipNumber: ref.watch(sessionProvider).membershipNumber,
          );
      return result.fold<HotelDetail>(
        (HotelDetail detail) => detail,
        (Failure failure) => throw failure,
      );
    });

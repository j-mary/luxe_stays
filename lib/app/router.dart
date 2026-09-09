import 'package:flutter/material.dart';

import '../domain/search.dart';
import '../features/booking/checkout_screen.dart';
import '../features/booking/confirmation_screen.dart';
import '../features/cart/cart_screen.dart';
import '../features/hotel/hotel_detail_screen.dart';
import '../features/loyalty/loyalty_screen.dart';
import '../features/search/search_screen.dart';
import '../webview/booking_engine_webview_screen.dart';
import '../webview/cms_content_webview_screen.dart';

/// Route names, in one place so a typo is a compile error at the call site
/// rather than a blank screen in production.
abstract final class Routes {
  static const String search = '/search';
  static const String hotelDetail = '/hotel';
  static const String cart = '/cart';
  static const String checkout = '/checkout';
  static const String confirmation = '/confirmation';
  static const String loyalty = '/loyalty';
  static const String bookingEngine = '/booking-engine';
  static const String cmsPage = '/page';
}

/// Typed route arguments.
///
/// Navigator 1.0 hands arguments across as `Object?`. Wrapping each route's
/// arguments in a small class means the cast happens once, here, with a clear
/// failure if a caller passes the wrong thing - instead of a `type 'String' is
/// not a subtype of 'HotelDetailArgs'` three frames into a build method.
class HotelDetailArgs {
  const HotelDetailArgs({required this.hotelId, required this.hotelName});

  final String hotelId;
  final String hotelName;
}

class BookingEngineArgs {
  const BookingEngineArgs({
    required this.hotelId,
    required this.hotelName,
    required this.query,
    this.roomTypeCode,
    this.ratePlanCode,
    this.membershipNumber,
  });

  final String hotelId;
  final String hotelName;
  final SearchQuery query;
  final String? roomTypeCode;
  final String? ratePlanCode;
  final String? membershipNumber;
}

class CmsPageArgs {
  const CmsPageArgs({
    required this.slug,
    required this.title,
    this.fallbackUrl,
  });

  final String slug;
  final String title;
  final String? fallbackUrl;
}

/// Why Navigator 1.0 and not go_router here: the app is a small, mostly linear
/// stack (search → detail → cart → checkout → confirmation) with two modal
/// WebView routes that *return values*. `Navigator.push<PaymentResult>` gives
/// that for free and with fewer moving parts. A larger app with deep links,
/// web URLs and nested shells would justify the router package - the trade is
/// discussed in `docs/01-ARCHITECTURE.md`.
class AppRouter {
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case Routes.search:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const SearchScreen(),
        );

      case Routes.hotelDetail:
        final HotelDetailArgs args = _args<HotelDetailArgs>(settings);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => HotelDetailScreen(args: args),
        );

      case Routes.cart:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const CartScreen(),
        );

      case Routes.checkout:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const CheckoutScreen(),
        );

      case Routes.confirmation:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const ConfirmationScreen(),
        );

      case Routes.loyalty:
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => const LoyaltyScreen(),
        );

      case Routes.bookingEngine:
        final BookingEngineArgs args = _args<BookingEngineArgs>(settings);
        return MaterialPageRoute<Object?>(
          settings: settings,
          fullscreenDialog: true,
          builder: (_) => BookingEngineWebViewScreen(
            hotelId: args.hotelId,
            hotelName: args.hotelName,
            query: args.query,
            roomTypeCode: args.roomTypeCode,
            ratePlanCode: args.ratePlanCode,
            membershipNumber: args.membershipNumber,
          ),
        );

      case Routes.cmsPage:
        final CmsPageArgs args = _args<CmsPageArgs>(settings);
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => CmsContentWebViewScreen(
            slug: args.slug,
            title: args.title,
            fallbackUrl: args.fallbackUrl,
          ),
        );

      default:
        return null;
    }
  }

  static T _args<T>(RouteSettings settings) {
    final Object? arguments = settings.arguments;
    if (arguments is T) {
      return arguments;
    }
    throw ArgumentError(
      'Route ${settings.name} expects $T arguments, got '
      '${arguments.runtimeType}',
    );
  }
}

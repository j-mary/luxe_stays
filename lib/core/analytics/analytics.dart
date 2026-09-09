import '../logging/app_logger.dart';

/// Analytics / crash reporting seam.
///
/// The app never talks to a vendor SDK directly. Swapping the console
/// implementation for `FirebaseAnalytics` (or Segment, or Salesforce Marketing
/// Cloud's `MobilePush` event tracking) means writing one adapter and changing
/// one provider - see `docs/01-ARCHITECTURE.md#seams`.
///
/// The event names below intentionally mirror the GA4 e-commerce vocabulary so
/// that funnel reports work out of the box.
abstract interface class AnalyticsService {
  void screen(String name, {Map<String, Object?> parameters});
  void event(String name, {Map<String, Object?> parameters});
  void purchase({
    required String transactionId,
    required int valueMinor,
    required String currency,
    required int pointsEarned,
  });
  void error(Object error, StackTrace stackTrace, {String? correlationId});
}

/// Canonical funnel event names. Keeping them as constants stops the classic
/// "search_performed" vs "searchPerformed" drift between iOS and Android.
abstract final class AnalyticsEvents {
  static const String searchPerformed = 'search_performed';
  static const String viewItem = 'view_item';
  static const String addToCart = 'add_to_cart';
  static const String beginCheckout = 'begin_checkout';
  static const String paymentWebviewOpened = 'payment_webview_opened';
  static const String paymentWebviewResult = 'payment_webview_result';
  static const String bookingConfirmed = 'booking_confirmed';
  static const String pointsAccrued = 'points_accrued';
  static const String pointsRedeemed = 'points_redeemed';
  static const String webviewBridgeMessage = 'webview_bridge_message';
  static const String webviewNavigationBlocked = 'webview_navigation_blocked';
}

/// Development implementation: writes redacted events through [AppLogger].
class LoggingAnalyticsService implements AnalyticsService {
  LoggingAnalyticsService(this._logger);

  final AppLogger _logger;

  @override
  void screen(String name,
      {Map<String, Object?> parameters = const <String, Object?>{}}) {
    _logger.info('screen:$name', context: parameters);
  }

  @override
  void event(String name,
      {Map<String, Object?> parameters = const <String, Object?>{}}) {
    _logger.info('event:$name', context: parameters);
  }

  @override
  void purchase({
    required String transactionId,
    required int valueMinor,
    required String currency,
    required int pointsEarned,
  }) {
    _logger.info('event:purchase', context: <String, Object?>{
      'transaction_id': transactionId,
      'value_minor': valueMinor,
      'currency': currency,
      'points_earned': pointsEarned,
    });
  }

  @override
  void error(Object error, StackTrace stackTrace, {String? correlationId}) {
    _logger.error(
      'unhandled',
      correlationId: correlationId,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

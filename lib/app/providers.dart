import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/analytics/analytics.dart';
import '../core/config/app_config.dart';
import '../core/error/error_mapper.dart';
import '../core/logging/app_logger.dart';
import '../core/network/api_client.dart';
import '../core/network/interceptors/auth_interceptor.dart';
import '../core/storage/token_store.dart';
import '../data/booking_repository.dart';
import '../data/hotel_repository.dart';
import '../domain/loyalty.dart';
import '../integrations/cms/cms_client.dart';
import '../integrations/cms/cms_repository.dart';
import '../integrations/leonardo/leonardo_ai_client.dart';
import '../integrations/leonardo/leonardo_client.dart';
import '../integrations/leonardo/leonardo_media_provider.dart';
import '../integrations/leonardo/media_provider.dart';
import '../integrations/payments/payment_api.dart';
import '../integrations/salesforce/salesforce_api.dart';
import '../integrations/salesforce/salesforce_auth.dart';
import '../integrations/salesforce/salesforce_repository.dart';
import '../integrations/synxis/synxis_api.dart';
import '../integrations/synxis/synxis_booking_engine.dart';
import '../integrations/synxis/synxis_repository.dart';

/// The dependency graph, expressed as Riverpod providers.
///
/// This file is the composition root. Read top to bottom it is a map of the
/// system: config → logger → one HTTP client per vendor → one repository per
/// vendor → the two cross-vendor repositories the UI actually talks to.
///
/// Every node is overridable, which is the point. A widget test overrides
/// [mediaProviderProvider] with a fixture and gets deterministic images; an
/// integration test overrides [appConfigProvider] to point at the local mock
/// server; a golden test overrides [loyaltyRulesProvider] to pin the earn rate.
/// No mocking framework required for any of it.

// ---------------------------------------------------------------------------
// Foundation
// ---------------------------------------------------------------------------

final Provider<AppConfig> appConfigProvider = Provider<AppConfig>((Ref ref) {
  return AppConfig.fromEnvironment();
});

final Provider<AppLogger> loggerProvider = Provider<AppLogger>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return AppLogger(
    minimumLevel: config.isProd ? LogLevel.info : LogLevel.debug,
  );
});

final Provider<AnalyticsService> analyticsProvider =
    Provider<AnalyticsService>((Ref ref) {
  // Swap for a FirebaseAnalytics adapter here; nothing else changes.
  return LoggingAnalyticsService(ref.watch(loggerProvider));
});

final Provider<TokenStore> tokenStoreProvider = Provider<TokenStore>((Ref ref) {
  return SecureTokenStore();
});

final Provider<LoyaltyProgramRules> loyaltyRulesProvider =
    Provider<LoyaltyProgramRules>((Ref ref) {
  // In production these come from a remote config / the CMS so the programme
  // can change earn rates without an app release.
  return const LoyaltyProgramRules();
});

// ---------------------------------------------------------------------------
// Salesforce
// ---------------------------------------------------------------------------

final Provider<SalesforceAuthService> salesforceAuthProvider =
    Provider<SalesforceAuthService>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return SalesforceAuthService(
    // A bare Dio: the auth service must not go through AuthInterceptor, or
    // refreshing a token would require a token.
    dio: Dio(BaseOptions(connectTimeout: const Duration(seconds: 10))),
    store: ref.watch(tokenStoreProvider),
    logger: ref.watch(loggerProvider),
    clientId: config.salesforceClientId,
    redirectUri: 'luxestays://oauth/callback',
    loginBaseUrl: config.salesforceBaseUrl,
  );
});

final Provider<ApiClient> salesforceClientProvider =
    Provider<ApiClient>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  final AppLogger logger = ref.watch(loggerProvider);
  final SalesforceAuthService auth = ref.watch(salesforceAuthProvider);

  final ApiClient client = ApiClient.build(
    baseUrl: config.salesforceBaseUrl,
    integration: 'salesforce',
    config: config,
    logger: logger,
    errorMapper: ErrorMapper.salesforce(),
    authInterceptor: AuthInterceptor(
      store: ref.watch(tokenStoreProvider),
      tokenKey: TokenKeys.salesforce,
      refresher: auth.refresh,
      logger: logger,
    ),
  );
  ref.onDispose(client.close);
  return client;
});

final Provider<SalesforceApi> salesforceApiProvider =
    Provider<SalesforceApi>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return SalesforceApi(
    client: ref.watch(salesforceClientProvider),
    apiVersion: config.salesforceApiVersion,
    loyaltyProgramName: config.salesforceLoyaltyProgram,
  );
});

final Provider<SalesforceRepository> salesforceRepositoryProvider =
    Provider<SalesforceRepository>((Ref ref) {
  return SalesforceRepository(
    api: ref.watch(salesforceApiProvider),
    logger: ref.watch(loggerProvider),
    rules: ref.watch(loyaltyRulesProvider),
  );
});

// ---------------------------------------------------------------------------
// SynXis
// ---------------------------------------------------------------------------

final Provider<ApiClient> synxisClientProvider = Provider<ApiClient>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  final ApiClient client = ApiClient.build(
    baseUrl: config.synxisBaseUrl,
    integration: 'synxis',
    config: config,
    logger: ref.watch(loggerProvider),
    errorMapper: ErrorMapper.synxis(),
    // The CRS is the slowest and most rate-limited dependency: a shop request
    // prices every rate plan for every property. Generous receive timeout,
    // conservative retry budget.
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    maxRetryAttempts: 2,
  );
  ref.onDispose(client.close);
  return client;
});

final Provider<SynxisApi> synxisApiProvider = Provider<SynxisApi>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return SynxisApi(
    client: ref.watch(synxisClientProvider),
    chainId: config.synxisChainId,
  );
});

final Provider<SynxisRepository> synxisRepositoryProvider =
    Provider<SynxisRepository>((Ref ref) {
  return SynxisRepository(
    api: ref.watch(synxisApiProvider),
    logger: ref.watch(loggerProvider),
  );
});

final Provider<SynxisBookingEngine> bookingEngineProvider =
    Provider<SynxisBookingEngine>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return SynxisBookingEngine(
    baseUrl: config.synxisBookingEngineUrl,
    chainId: config.synxisChainId,
  );
});

// ---------------------------------------------------------------------------
// CMS
// ---------------------------------------------------------------------------

final Provider<ApiClient> cmsClientProvider = Provider<ApiClient>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  final ApiClient client = ApiClient.build(
    baseUrl: config.cmsBaseUrl,
    integration: 'cms',
    config: config,
    logger: ref.watch(loggerProvider),
    errorMapper: ErrorMapper.cms(),
    headers: const <String, String>{
      // Read-only delivery token. Safe to ship; grants published content only.
      'Authorization': 'Bearer cda-delivery-token-placeholder',
    },
    // CDN-fronted and cacheable: fast, and worth retrying.
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 10),
  );
  ref.onDispose(client.close);
  return client;
});

final Provider<CmsRepository> cmsRepositoryProvider =
    Provider<CmsRepository>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  return CmsRepository(
    client: CmsClient(
      client: ref.watch(cmsClientProvider),
      spaceId: config.cmsSpaceId,
      environment: config.cmsEnvironment,
    ),
    logger: ref.watch(loggerProvider),
  );
});

// ---------------------------------------------------------------------------
// Leonardo
// ---------------------------------------------------------------------------

final Provider<MediaProvider> mediaProviderProvider =
    Provider<MediaProvider>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  final AppLogger logger = ref.watch(loggerProvider);

  final ApiClient mediaClient = ApiClient.build(
    baseUrl: config.leonardoBaseUrl,
    integration: 'leonardo',
    config: config,
    logger: logger,
    errorMapper: ErrorMapper.leonardo(),
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 12),
  );
  ref.onDispose(mediaClient.close);

  final ApiClient aiClient = ApiClient.build(
    baseUrl: config.leonardoAiBaseUrl,
    integration: 'leonardo-ai',
    config: config,
    logger: logger,
    errorMapper: ErrorMapper.leonardo(),
    // Generation is slow by nature; a long receive timeout here does not
    // matter because nothing user-blocking waits on it.
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 30),
  );
  ref.onDispose(aiClient.close);

  return LeonardoMediaProvider(
    client: LeonardoClient(client: mediaClient),
    aiClient: LeonardoAiClient(client: aiClient, logger: logger),
    logger: logger,
  );
});

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

final Provider<PaymentApi> paymentApiProvider = Provider<PaymentApi>((Ref ref) {
  final AppConfig config = ref.watch(appConfigProvider);
  final ApiClient client = ApiClient.build(
    baseUrl: config.apiBaseUrl,
    integration: 'payments',
    config: config,
    logger: ref.watch(loggerProvider),
    // Payment intent creation must not be retried blindly; the idempotency key
    // on the request is what makes the single permitted retry safe.
    maxRetryAttempts: 2,
  );
  ref.onDispose(client.close);
  return PaymentApi(client: client);
});

// ---------------------------------------------------------------------------
// Cross-vendor repositories - what the UI actually depends on
// ---------------------------------------------------------------------------

final Provider<HotelRepository> hotelRepositoryProvider =
    Provider<HotelRepository>((Ref ref) {
  return HotelRepository(
    synxis: ref.watch(synxisRepositoryProvider),
    cms: ref.watch(cmsRepositoryProvider),
    media: ref.watch(mediaProviderProvider),
    logger: ref.watch(loggerProvider),
  );
});

final Provider<BookingRepository> bookingRepositoryProvider =
    Provider<BookingRepository>((Ref ref) {
  return BookingRepository(
    synxis: ref.watch(synxisRepositoryProvider),
    payments: ref.watch(paymentApiProvider),
    salesforce: ref.watch(salesforceRepositoryProvider),
    analytics: ref.watch(analyticsProvider),
    logger: ref.watch(loggerProvider),
  );
});

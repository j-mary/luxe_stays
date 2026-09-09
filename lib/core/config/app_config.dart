/// Build-time configuration.
///
/// Every value is a `const String.fromEnvironment`, i.e. supplied with
/// `--dart-define` (or `--dart-define-from-file`). Because the values are
/// compile-time constants they are tree-shaken into the binary and there is no
/// `.env` file to accidentally ship. See `docs/11-SECURITY.md` for what may and
/// may not live here.
library;

enum Flavor { dev, staging, prod }

class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.synxisBaseUrl,
    required this.synxisChainId,
    required this.synxisBookingEngineUrl,
    required this.salesforceBaseUrl,
    required this.salesforceApiVersion,
    required this.salesforceClientId,
    required this.salesforceLoyaltyProgram,
    required this.cmsBaseUrl,
    required this.cmsSpaceId,
    required this.cmsEnvironment,
    required this.leonardoBaseUrl,
    required this.leonardoAiBaseUrl,
    required this.pspHostedPageUrl,
  });

  /// Reads the configuration the app was compiled with.
  factory AppConfig.fromEnvironment() {
    return AppConfig(
      flavor: _flavorOf(
        const String.fromEnvironment('FLAVOR', defaultValue: 'dev'),
      ),
      apiBaseUrl: const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://localhost:8080',
      ),
      synxisBaseUrl: const String.fromEnvironment(
        'SYNXIS_BASE_URL',
        defaultValue: 'http://localhost:8080/synxis',
      ),
      synxisChainId: const String.fromEnvironment(
        'SYNXIS_CHAIN_ID',
        defaultValue: '12345',
      ),
      synxisBookingEngineUrl: const String.fromEnvironment(
        'SYNXIS_BOOKING_ENGINE_URL',
        defaultValue: 'http://localhost:8080/be',
      ),
      salesforceBaseUrl: const String.fromEnvironment(
        'SALESFORCE_BASE_URL',
        defaultValue: 'http://localhost:8080/salesforce',
      ),
      salesforceApiVersion: const String.fromEnvironment(
        'SALESFORCE_API_VERSION',
        defaultValue: 'v62.0',
      ),
      salesforceClientId: const String.fromEnvironment(
        'SALESFORCE_CLIENT_ID',
        defaultValue: 'luxestays_mobile_connected_app',
      ),
      salesforceLoyaltyProgram: const String.fromEnvironment(
        'SALESFORCE_LOYALTY_PROGRAM',
        defaultValue: 'LuxeStaysRewards',
      ),
      cmsBaseUrl: const String.fromEnvironment(
        'CMS_BASE_URL',
        defaultValue: 'http://localhost:8080/cms',
      ),
      cmsSpaceId: const String.fromEnvironment(
        'CMS_SPACE_ID',
        defaultValue: 'luxestays',
      ),
      cmsEnvironment: const String.fromEnvironment(
        'CMS_ENVIRONMENT',
        defaultValue: 'master',
      ),
      leonardoBaseUrl: const String.fromEnvironment(
        'LEONARDO_BASE_URL',
        defaultValue: 'http://localhost:8080/leonardo',
      ),
      leonardoAiBaseUrl: const String.fromEnvironment(
        'LEONARDO_AI_BASE_URL',
        defaultValue: 'http://localhost:8080/leonardo-ai',
      ),
      pspHostedPageUrl: const String.fromEnvironment(
        'PSP_HOSTED_PAGE_URL',
        defaultValue: 'http://localhost:8080/pay',
      ),
    );
  }

  final Flavor flavor;

  /// Our own Backend-for-Frontend. Anything that needs a vendor *secret* is
  /// proxied through here rather than called directly from the handset.
  final String apiBaseUrl;

  // Sabre SynXis (hospitality CRS / booking engine).
  final String synxisBaseUrl;
  final String synxisChainId;
  final String synxisBookingEngineUrl;

  // Salesforce (CRM + Loyalty Management + Service Cloud).
  final String salesforceBaseUrl;
  final String salesforceApiVersion;
  final String salesforceClientId;
  final String salesforceLoyaltyProgram;

  // Headless CMS (Contentful-shaped Content Delivery API).
  final String cmsBaseUrl;
  final String cmsSpaceId;
  final String cmsEnvironment;

  // Leonardo (hotel media) + Leonardo.Ai (generative imagery).
  final String leonardoBaseUrl;
  final String leonardoAiBaseUrl;

  // Payment service provider hosted page, opened in a WebView.
  final String pspHostedPageUrl;

  bool get isProd => flavor == Flavor.prod;

  /// Verbose network logging is *never* enabled in production builds: request
  /// bodies contain guest PII and payment intents.
  bool get verboseNetworkLogging => flavor != Flavor.prod;

  /// Origins the hybrid WebViews are allowed to navigate to. Anything else is
  /// blocked by `NavigationDelegate.onNavigationRequest`.
  List<String> get webViewAllowedOrigins => <String>[
        Uri.parse(apiBaseUrl).origin,
        Uri.parse(synxisBookingEngineUrl).origin,
        Uri.parse(pspHostedPageUrl).origin,
        Uri.parse(cmsBaseUrl).origin,
      ];

  static Flavor _flavorOf(String raw) {
    switch (raw) {
      case 'prod':
        return Flavor.prod;
      case 'staging':
        return Flavor.staging;
      default:
        return Flavor.dev;
    }
  }
}

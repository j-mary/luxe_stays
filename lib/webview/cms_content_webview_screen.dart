import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:luxe_stays/webview/bridge/webview_bridge.dart';

import '../app/providers.dart';
import '../app/router.dart';
import 'bridge/bridge_message.dart';
import 'hybrid_webview.dart';

/// CMS-authored content in a WebView: terms, loyalty programme rules,
/// destination guides, itinerary pages.
///
/// The alternative - fetching rich text from the CMS and rendering it natively -
/// means owning a rich-text renderer, an image-embed strategy, a table layout,
/// and a per-locale typography pass. For content that changes weekly and is
/// authored by people who preview it on the web, rendering the web page is the
/// cheaper and more accurate answer. Native rendering is reserved for content
/// the app *interacts with* (hotel descriptions, amenity lists), which is why
/// those come through `CmsRepository` as structured data instead.
class CmsContentWebViewScreen extends ConsumerStatefulWidget {
  const CmsContentWebViewScreen({
    required this.slug,
    required this.title,
    this.fallbackUrl,
    super.key,
  });

  final String slug;
  final String title;
  final String? fallbackUrl;

  @override
  ConsumerState<CmsContentWebViewScreen> createState() =>
      _CmsContentWebViewScreenState();
}

class _CmsContentWebViewScreenState
    extends ConsumerState<CmsContentWebViewScreen> {
  late Future<String?> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = ref.read(cmsRepositoryProvider).pageUrl(widget.slug);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _urlFuture,
      builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final String? url = snapshot.data ?? widget.fallbackUrl;
        if (url == null) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This page is not available right now.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return HybridWebView(
          initialUri: Uri.parse(url),
          title: widget.title,
          handlers: <BridgeMessageType, BridgeHandler>{
            // Content pages can ask the host to navigate natively, e.g. a
            // "browse hotels in Kyoto" call-to-action inside a destination
            // guide. The host decides whether to honour it - the page cannot
            // push arbitrary routes.
            BridgeMessageType.navigate: (BridgeMessage message) {
              final String? route = message.stringField('route');
              if (route == null || !_allowedRoutes.contains(route)) {
                return;
              }
              _leaveWebViewFor(route);
            },
          },
        );
      },
    );
  }

  static const Set<String> _allowedRoutes = <String>{
    Routes.search,
    Routes.loyalty,
    Routes.cart,
  };

  void _leaveWebViewFor(String route) {
    if (!mounted) return;
    navigateFromCmsWebView(Navigator.of(context), route);
  }
}

/// Leaves CMS web content for an allowlisted native route.
///
/// Kept outside the widget so its stack semantics can be tested without
/// constructing a platform WebView.
void navigateFromCmsWebView(NavigatorState navigator, String route) {
  if (route == Routes.search) {
    // Search is the app's existing root route. Unwind the checkout,
    // confirmation and CMS WebView instead of placing a second SearchScreen
    // above them. Back can no longer reveal the itinerary WebView.
    navigator.popUntil(
      (Route<dynamic> candidate) =>
          candidate.settings.name == Routes.search || candidate.isFirst,
    );
    return;
  }

  // Other allowlisted native destinations take the WebView's place. This
  // preserves the screen that opened the CMS page while ensuring Back never
  // returns to stale web content.
  navigator.pushReplacementNamed(route);
}

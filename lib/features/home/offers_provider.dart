import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../integrations/cms/cms_models.dart';
import '../account/session_controller.dart';

/// Live merchandising offers from the CMS.
///
/// This is the cheapest, clearest demonstration of why a CMS is in the stack:
/// marketing publishes an entry with a `promotionCode`, the app picks it up on
/// the next launch, and tapping it puts that code into the SynXis availability
/// request. A campaign goes live with no release, no store review, and no
/// engineer.
final FutureProvider<List<CmsOffer>> offersProvider =
    FutureProvider<List<CmsOffer>>((Ref ref) async {
      final bool isMember = ref.watch(sessionProvider).isSignedIn;
      final List<CmsOffer> offers = await ref
          .watch(cmsRepositoryProvider)
          .offers();
      // Member-only campaigns are hidden from signed-out guests, exactly as the
      // CMS entry declares.
      return offers
          .where((CmsOffer offer) => isMember || !offer.memberOnly)
          .toList(growable: false);
    });

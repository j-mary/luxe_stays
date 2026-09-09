# 14 — Code tour

A map of the codebase: each capability, and the file that implements it. Useful
for finding your way in, or for picking up a thread after time away.

## Application concerns

| Concern | Where |
|---|---|
| Architecture, state management, widget composition | [`lib/app/providers.dart`](../lib/app/providers.dart) · [`lib/features/`](../lib/features) · [01 — Architecture](01-ARCHITECTURE.md) |
| Performance optimisation | [`shared/widgets/media_image.dart`](../lib/shared/widgets/media_image.dart) (rendition sizing, `memCacheWidth`) · [`leonardo_media_provider.dart`](../lib/integrations/leonardo/leonardo_media_provider.dart) (cache + request coalescing) · [05](05-INTEGRATION-LEONARDO.md) |
| Async Dart: `Future`s, `Stream`s, parallelism | [`hotel_repository.dart`](../lib/data/hotel_repository.dart) (parallel fan-out) · [`leonardo_ai_client.dart`](../lib/integrations/leonardo/leonardo_ai_client.dart) (poll with timeout) · [`auth_interceptor.dart`](../lib/core/network/interceptors/auth_interceptor.dart) (single-flight refresh) |
| REST integration, JSON serialisation | [`core/network/api_client.dart`](../lib/core/network/api_client.dart) · every `*_models.dart` |
| API errors and edge cases | [`core/error/failure.dart`](../lib/core/error/failure.dart) · [`error_mapper.dart`](../lib/core/error/error_mapper.dart) · [`test/core/error_mapper_test.dart`](../test/core/error_mapper_test.dart) |
| Production maintenance concerns | Idempotency keys, correlation ids, retry with jitter, graceful degradation — [07](07-BOOKING-PAYMENT-FLOW.md) |
| CI/CD | [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) · [10 — CI/CD](10-CI-CD.md) |
| Unit / widget / integration tests | [`test/`](../test) · [`integration_test/`](../integration_test) · [09 — Testing](09-TESTING.md) |
| Performance, debugging, logging, troubleshooting | [`core/logging/app_logger.dart`](../lib/core/logging/app_logger.dart) · [13 — Runbook](13-RUNBOOK.md) |
| **WebView functionality and hybrid architecture** | [`lib/webview/`](../lib/webview) · [02 — WebView bridge](02-WEBVIEW-BRIDGE.md) |
| Design rationale | The trade-off sections in every document — including what was deliberately left out |

## Domain and platform concerns

| Concern | Where |
|---|---|
| Travel / hospitality / booking domain | The whole domain model: perishable quotes, per-night rates, cancellation deadlines, multi-property carts |
| Payment flows | [07 — Booking & payment](07-BOOKING-PAYMENT-FLOW.md) · [`payment_webview_screen.dart`](../lib/webview/payment_webview_screen.dart) |
| Booking systems | [03 — SynXis](03-INTEGRATION-SYNXIS.md) |
| Loyalty programmes | [08 — Loyalty](08-LOYALTY.md) · [`domain/loyalty.dart`](../lib/domain/loyalty.dart) |
| CMS integration | [06 — CMS](06-INTEGRATION-CMS.md) · Contentful link resolution |
| **Salesforce** | [04 — Salesforce](04-INTEGRATION-SALESFORCE.md) — PKCE, Loyalty Management, program processes, Service Cloud |
| **SynXis** | [03 — SynXis](03-INTEGRATION-SYNXIS.md) — shopping, re-quote, idempotent booking, booking engine |
| **Leonardo** | [05 — Leonardo](05-INTEGRATION-LEONARDO.md) — media library *and* the generative-AI namesake |
| Hybrid WebView architecture | [02 — WebView bridge](02-WEBVIEW-BRIDGE.md) |
| Firebase / analytics | [`core/analytics/analytics.dart`](../lib/core/analytics/analytics.dart) — the seam, with GA4-shaped event names |
| Automated store releases | [10 — CI/CD](10-CI-CD.md) |
| Application security | [11 — Security](11-SECURITY.md) — PCI scope, secrets, WebView hardening, redaction |
| AI-assisted engineering | [12 — AI-assisted engineering](12-AI-ASSISTED-WORKFLOW.md) |

## Five decisions worth reading

If you only have time for a few, these carry the most design reasoning.

**1. Why the app is hybrid at all, and where the line is.**
Native where the product competes, web where a vendor or another department owns
the change — and the payment page for a third reason: PCI scope. The line is
drawn by who owns the change, not by what is easier to build.
→ [02](02-WEBVIEW-BRIDGE.md)

**2. The bridge's origin check.**
A `JavaScriptChannel` belongs to the WebView, not to a page. If the page
navigates, the new origin can post to the same channel. So every inbound message
re-checks the WebView's live URL before dispatch. This is the control most hybrid
implementations are missing.
→ [`webview_bridge.dart`](../lib/webview/bridge/webview_bridge.dart)

**3. Re-quote before payment.**
Hotel pricing is perishable. `RateChangedFailure` carries both the old and the
new total so the guest confirms the change rather than being silently charged a
different amount. It is a trust decision expressed as a type.
→ [07](07-BOOKING-PAYMENT-FLOW.md)

**4. Loyalty must never fail a booking.**
By the time points are posted, the reservation exists and the card is charged. A
Salesforce outage queues the accrual and says "about 4,500 points are on their
way" — it does not fail the booking or lie about the balance.
→ [`salesforce_repository.dart`](../lib/integrations/salesforce/salesforce_repository.dart)

**5. Content is never load-bearing.**
`CmsRepository` degrades to empty on every failure. One fixture property
deliberately has no CMS entry, and there is a widget test asserting its card
still renders and is bookable. The rule is enforced, not just documented.
→ [06](06-INTEGRATION-CMS.md)

## Known limitations

Stated plainly, because a codebase that claims completeness is not credible:

* **SynXis and Leonardo contracts are modelled, not copied** — both are
  partner-distributed. The shapes follow documented concepts and OTA
  conventions, the mock server matches them exactly, and the swap surface is one
  DTO file plus one mapper per vendor. Each integration document says which
  parts are verified.
* **No persistence.** Cart and session are in-memory. Real, and it does not
  change any of the shapes.
* **No localisation.** Strings are English and inline. The locale is already
  plumbed to the WebView bridge, which is the part teams forget.
* **The deferred-accrual outbox is in memory.** Production wants a persisted
  outbox plus server-side reconciliation.
* **No certificate pinning.** Deliberate: pinning without a rotation plan and a
  kill switch turns a certificate renewal into an outage no app update can fix
  quickly.

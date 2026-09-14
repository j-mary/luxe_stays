# API audit — 14 September 2026

## Scope and evidence

This is a local, in-memory demonstration, not a certified vendor integration. All people, properties, prices, payment references and credentials are synthetic. The application uses the existing feature/repository/client structure. Class names containing Synxis are retained for compatibility, but their shopping and booking payloads are **LuxeStays BFF contracts**, not vendor wire formats. Changing a base URL cannot turn this demo into a production client.

Sources checked:

- [SynXis Property Hub Reservation reference](https://developer.synxis.com/pms/property_hub/reservation/reference-documentation), displayed revision **4.29.0**. The linked [public OpenAPI YAML](https://developer.synxis.com/sites/default/files/public/apidoc_specs/sphReservation4.29.0.yaml) was successfully downloaded and inspected. Its `info.version` is `v1.0.0`; that differs from the portal release label.
- [Reservation overview](https://developer.synxis.com/pms/property_hub/reservation): requested, but the fetch timed out. The public YAML is the contract evidence; no claims are inferred from the inaccessible overview.
- [Contentful CDA overview](https://www.contentful.com/developers/docs/references/content-delivery-api/overview/) and [linked entries/assets](https://www.contentful.com/developers/docs/references/content-delivery-api/links/).
- [Salesforce Loyalty integration guide](https://developer.salesforce.com/docs/industries/loyalty/guide/get-started.html). This guide does not certify this app's bespoke program processes or DTOs.
- [Leonardo Worldwide media distribution](https://www.leonardoworldwide.com/dl/Leo_Info_VscapeMedia_17.0322.pdf). Public material establishes the product role, not our endpoint/field schema.
- [Leonardo.Ai generation reference](https://docs.leonardo.ai/reference/creategeneration): currently describes a v2 asynchronous generation operation. Our optional legacy v1-shaped illustration demo is explicitly an assumed BFF adapter, not a claim of current vendor compatibility.

## SynXis: two different boundaries

The official Property Hub API is a PMS integration. The public document does **not** provide the hotel's shopping, payment or reservation-create/cancel contract. We do not manufacture those operations under `/sph`.

The implemented official retrieval subset is:

`POST /v1/sph/reservations/outbound/data/reservations-details`

It uses the documented `tenantId` header (1 or 2), JSON request body with `client`, integer `hotelId`/`chainId`, `startDateTime`, `endDateTime`, `delta`, `updateDelta`; and a lower-camelCase response including `errors`, `currencyCode`, `status`, `reservations`, `total`. The fictional fixture supplies only documented reservation fields. Its IDs are integers, unlike the app's opaque demo hotel IDs.

The YAML declares OAuth2 client credentials. No real token is requested or credential embedded. Authentication is bypassed for local development; `x-mock-fail: 401` and `403` simulate failures. This header belongs to the test harness, never SynXis. Retrieval error responses have documented status codes but no inline body schema, so the route uses empty 400 responses instead of inventing a provider error body. The outer harness uses its own clearly labelled error envelope for malformed JSON and injected failures.

**Retrieval limitations/assumptions:** requiring integer IDs and ordered timestamps is local validation; the schema omits property-level `required` lists. Hotel 1234 returns one synthetic reservation, other hotels return an empty list. Date filtering, persistent delta cursors, full optional fields, tenant permissions and update operations are not simulated. `nextDeltaStartTime` is omitted rather than fabricated. This endpoint is a separate contract demonstration; the mobile booking flow still uses the demo BFF.

The separate `/synxis/v1/api/...` gateway supports hotel/room lists, availability, re-quote, create, retrieve and cancel. Every endpoint, PascalCase field, quote token, idempotency header and `Errors` envelope on that boundary is a **local assumption**. A future server-side adapter must map it to the actual contracted CRS APIs. Public Property Hub retrieval is not a substitute for that agreement.

## Gateway behavior and scenarios

- Search returns fictional properties, generated local PNGs and matching rooms. Unknown destination/hotel IDs give empty search results. H-CPT-002 is unavailable on Monday arrivals.
- Quotes preserve the complete stay, occupancy, promotion and price. Four-night STAY4 includes a free fourth night. Quotes exist only until the server restarts. `x-mock-rate-change: 1` on re-quote adds $10 to fees and exercises price-drift handling.
- Supported demo pricing is USD, stays 1–30 nights and one room per search. There is no exchange-rate engine. Occupancy must fit a room. Refundable/member filters apply before results are returned.
- Create requires a valid quote, guest name/email, matching price/currency, authorized demo payment and idempotency key. The same key/body replays the original reservation; a changed body gets 409. Retrieval returns 404 when missing and 403 on a supplied last-name mismatch. Cancellation updates the stored status and can be repeated. There is no amendment UI.
- All routes support `x-mock-fail: 401`, `403`, `429`, or `503`; these are synthetic harness failures, not vendor-specific authentication responses. Start with `--latency 25000` to exceed the client timeout; stop the server for a connection failure. `--fail-rate` demonstrates random intermittent service loss. Test deterministic failures first.
- Invalid JSON yields a local 400; incorrect field types yield 422. CORS preflight works for browser testing. Mocks contain no authentication boundary and should be bound to trusted development environments only.

## Other integrations: what is and is not verified

| Integration | Files audited | Contract / deliberate limitation |
| --- | --- | --- |
| Contentful | cms_client/models/repository, cms_routes, fixtures, cms_links_test | REST entry collections, `sys` links and `includes.Asset` are the correct CDA pattern. Content types, fields and hosted `/pages` are application-owned. No GraphQL API is used. Pagination, full locale resolution, real CDA tokens and management operations are outside this POC. |
| Salesforce | salesforce_api/auth/models/repository, salesforce_routes, fixtures | Versioned REST/SOQL and loyalty concepts demonstrate the adapter pattern. Program names, process names, rewards, membership sign-in shortcut and response selections are local assumptions. v62.0 is the explicit demo contract version, not a claim to the newest Salesforce version. Partner/org configuration must determine a live version and permissions. Mock OAuth is not production identity verification. |
| Leonardo Worldwide | leonardo_client/media_provider, leonardo_routes, png | Asset catalogue, license metadata, room mappings and rendition URL parameters are assumed application gateway fields. Images are generated gradients, not hotel photography. Width/height are bounded; the mock always returns PNG and does not implement quality/format conversion. Licensed vendor media needs a real contracted adapter. |
| Leonardo.Ai | leonardo_ai_client, leonardoAiRouter | Optional adapter demonstrates submit/poll/failure/timeout structure. Its legacy generation job schema is not the current v2 contract; no AI request or billing occurs. No UI feature depends on it. Keep disabled for live usage until an explicit model contract is implemented. |
| Payments | payment_api, payment_routes, web_pages, checkout | Fully synthetic hosted authorization, verification and void operations. No real PSP or card data. On total booking failure the app now actually requests a void and reports when it cannot confirm compensation. Partial booking, capture, refunds, reconciliation, webhook verification and durable transaction recovery still need a server-side workflow before handling money. |
| Analytics | analytics.dart | Logging adapter only; no Firebase project or live analytics ingestion. |

## Security and transaction limits

`--dart-define` values are compiled into the app and are extractable. Put only public URLs/identifiers there; provider secrets belong on a server. Keychain/platform secure storage protects issued tokens, not embedded secrets. Debug WebView/HTTP allowances support local mocks and are not production transport policy. A WebView does not establish PCI compliance or SAQ eligibility.

The POC has no durable database, session authorization, inventory locking, payment capture or distributed transaction coordinator. A payment authorization is a simulation, and local price checking is not a production fraud boundary. Loyalty rules/vouchers are demonstrations; monetary settlement, partial bookings and voucher redemption must be reconciled server-side before launch. No automated release or store publishing is claimed. These limits are visible so the code can be evaluated honestly.

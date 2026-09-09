# LuxeStays

A working Flutter proof-of-concept for a **luxury-hotel OTA**: 400+ properties,
flexible search, a multi-property cart, a booking and payment flow, and a
loyalty programme that stacks member rates with an internal points currency.

It is built as a **hybrid app** — native where the product competes, WebView
where the vendor owns the flow — and it integrates four external systems:

| System | Role in the product | Code |
|---|---|---|
| **Sabre SynXis** | Central reservation system: inventory, rates, reservations, and the booking-engine web flow | [`lib/integrations/synxis/`](lib/integrations/synxis) |
| **Salesforce** | CRM identity, Loyalty Management (balances, tiers, vouchers, accrual/redemption), Service Cloud cases | [`lib/integrations/salesforce/`](lib/integrations/salesforce) |
| **Leonardo** | Hotel media library — the system of record for photography (plus a Leonardo.Ai adapter for destination imagery) | [`lib/integrations/leonardo/`](lib/integrations/leonardo) |
| **Headless CMS** | Editorial copy, merchandising offers and legal pages, changed without an app release | [`lib/integrations/cms/`](lib/integrations/cms) |

Everything runs locally against a **mock back end** that stands in for all four
vendors plus the payment provider — including the two real HTML pages the app
loads in WebViews. No credentials, no network, no vendor sandbox required.

---

## Run it

The Android, iOS and web host projects are committed, so there is no
`flutter create` step — clone and fetch dependencies:

```bash
flutter pub get
```

Then, in two terminals:

```bash
# 1 — the mock SynXis / Salesforce / CMS / Leonardo / PSP back end
dart run tool/mock_server/server.dart

# 2 — the app
flutter run \
  --dart-define=API_BASE_URL=http://localhost:8080 \
  --dart-define=SYNXIS_BASE_URL=http://localhost:8080/synxis \
  --dart-define=SYNXIS_BOOKING_ENGINE_URL=http://localhost:8080/be \
  --dart-define=SALESFORCE_BASE_URL=http://localhost:8080/salesforce \
  --dart-define=CMS_BASE_URL=http://localhost:8080/cms \
  --dart-define=LEONARDO_BASE_URL=http://localhost:8080/leonardo \
  --dart-define=LEONARDO_AI_BASE_URL=http://localhost:8080/leonardo-ai \
  --dart-define=PSP_HOSTED_PAGE_URL=http://localhost:8080/pay
```

Or just `make mock` and `make run`.

**On Android, `localhost` is the handset, not your Mac.** Use
`make adb-reverse` once for a USB device (then plain `make run`),
`make run-emulator` for an emulator, or `make run-lan` over Wi-Fi. Full
setup notes and troubleshooting are in
**[docs/13-RUNBOOK.md](docs/13-RUNBOOK.md)**.

Sign in on the Rewards tab with **`LS-100042`** (Gold), **`LS-100077`**
(Platinum) or **`LS-100901`** (Silver) to see member rates, points and
redemption appear.

---

## What to look at first

If you have ten minutes, read these four files in order — they are the spine of
the whole thing:

1. **[`lib/app/providers.dart`](lib/app/providers.dart)** — the dependency graph
   in one screen: config → logger → one HTTP client per vendor → one repository
   per vendor → the two cross-vendor repositories the UI talks to.
2. **[`lib/data/hotel_repository.dart`](lib/data/hotel_repository.dart)** — where
   SynXis, the CMS and Leonardo are actually composed into a search result, and
   which of them are allowed to fail.
3. **[`lib/data/booking_repository.dart`](lib/data/booking_repository.dart)** —
   the three-phase checkout: re-quote → pay in a WebView → verify, book, accrue.
4. **[`lib/webview/bridge/webview_bridge.dart`](lib/webview/bridge/webview_bridge.dart)** —
   the native half of the JavaScript bridge, and the origin check that makes it
   safe.

---

## Documentation

| Document | What it covers |
|---|---|
| [01 — Architecture](docs/01-ARCHITECTURE.md) | Layers, the composition root, state management, and the trade-offs behind each choice |
| [02 — WebView bridge](docs/02-WEBVIEW-BRIDGE.md) | The hybrid split, the message protocol, origin enforcement, and how to add a new hybrid screen |
| [03 — SynXis](docs/03-INTEGRATION-SYNXIS.md) | The CRS: shopping, re-quoting, idempotent booking, the booking engine, and links to Sabre's documentation |
| [04 — Salesforce](docs/04-INTEGRATION-SALESFORCE.md) | OAuth with PKCE, Loyalty Management resources, program processes, Service Cloud, and links to Salesforce's documentation |
| [05 — Leonardo](docs/05-INTEGRATION-LEONARDO.md) | Hotel media, renditions and caching, plus the Leonardo.Ai adapter and where generative imagery is and is not acceptable |
| [06 — CMS](docs/06-INTEGRATION-CMS.md) | Contentful-shaped delivery API, link resolution, and the "content is never load-bearing" rule |
| [07 — Booking & payment](docs/07-BOOKING-PAYMENT-FLOW.md) | The full sequence, every failure mode, and what happens to the guest's money in each |
| [08 — Loyalty](docs/08-LOYALTY.md) | Tiers, member rates, earn/burn maths, and why Salesforce is the only authority |
| [09 — Testing](docs/09-TESTING.md) | The test pyramid used here, what each layer is for, and how to run it |
| [10 — CI/CD](docs/10-CI-CD.md) | Pipeline, flavours, signing, contract checks and store release automation |
| [11 — Security](docs/11-SECURITY.md) | PCI scope, secrets, token storage, WebView hardening, logging and PII |
| [12 — AI-assisted engineering](docs/12-AI-ASSISTED-WORKFLOW.md) | How AI tooling was used to build this, with the guardrails that make it safe |
| [13 — Runbook](docs/13-RUNBOOK.md) | Running, debugging, fault injection, and common problems |
| [14 — Code tour](docs/14-CODE-TOUR.md) | A map of the codebase: each capability and the file that implements it |

---

## Repository layout

```
lib/
  app/            composition root, router, theme
  core/           config, HTTP + interceptors, error taxonomy, logging, money, storage
  domain/         hotels, rates, cart, booking, loyalty, media — no vendor types
  integrations/   one folder per vendor: transport → DTOs → repository
    synxis/       CRS: availability, re-quote, reservations, booking engine URLs
    salesforce/   OAuth (PKCE), Loyalty Management, Service Cloud
    leonardo/     media library, renditions, Leonardo.Ai adapter
    cms/          Contentful-shaped delivery client and link resolution
    payments/     payment intents (the app never touches card data)
  data/           cross-vendor composition: HotelRepository, BookingRepository
  webview/        the bridge protocol and the three hybrid screens
  features/       search, hotel, cart, booking, loyalty, account
  shared/         widgets used across features
tool/
  mock_server/    the four vendors + the PSP, in one Dart process
  contract_check.sh   vendor contract smoke test, run in CI
test/             unit + widget tests
integration_test/ on-device end-to-end smoke test
docs/             the documentation table above
```

---

## The visual system

[`lib/app/theme.dart`](lib/app/theme.dart) is the whole of it. Four rules:

| Rule | Why |
|---|---|
| **Serif for voice, sans for work** | Display sizes, section headings, property names and prices are set in a serif; body copy, labels and anything dense stays in the platform sans, which is what keeps a rate list legible at 12.5px. The break sits at `titleSmall`. |
| **Gold is the accent, deep gold is the action** | A true gold cannot carry white text at body size, so the filled-button colour is a deepened antique gold that clears 4.5:1 against white (~4.9:1), and the brighter gold is spent on marks, rules and overlines where the contrast requirement is lighter. |
| **Corners are nearly square** | 2px on controls and panels, none on imagery. Rounded elevated cards read as software; a hairline rule and a sharp edge read as print. |
| **Emphasis comes from a rule, not a fill** | Section breaks are a letterspaced overline plus a rule to the margin ([`SectionHeading`](lib/shared/widgets/section_heading.dart)); grouping is a hairline border ([`AppPanel`](lib/shared/widgets/app_panel.dart)); the one saturated surface in the app is the ink plate behind the membership panel. |

Two consequences worth knowing before editing it.

`ColorScheme.fromSeed` tints *every* container from the seed hue, so all the
container roles are overridden back to a neutral warm grey and `surfaceTint` is
set to transparent — otherwise a gold wash appears over scrolled-under app bars
and every tonal surface.

The serif is resolved from fonts already on the device (`Georgia`, falling back
through `Times New Roman` and `Noto Serif`), so there is no bundled binary and
no runtime download; the exact face differs slightly between iOS and Android by
design. `AppTheme.serif(...)` exposes the family plus its fallback chain for the
occasional one-off size, such as the masthead.

`cardTheme`, `appBarTheme` and `inputDecorationTheme` are deliberately *not*
set: those data classes were re-typed in the Flutter 3.32 theme migration, so
setting them pins the project to one side of that change. `AppPanel` composes
the same result from a `Container`, which does not.

---

## Status and honesty about the mocks

This is a proof of concept, and it says so where it matters:

* **SynXis and Leonardo contracts are modelled, not copied.** Both vendors
  distribute their API specifications to contracted partners rather than
  publishing them openly. The request and response shapes here follow their
  documented concepts and OTA conventions, and the mock server matches them
  exactly. Swapping in the real contract means editing the DTO file and the
  mapper for that vendor — nothing above them changes. Each integration
  document is explicit about which parts are verified and which are modelled.
* **Salesforce and Contentful shapes follow their public documentation**, which
  is linked from the relevant document.
* **The platform host projects are committed**, with the two WebView-related
  settings already applied: cleartext to `localhost` in the Android *debug*
  manifest only, and an ATS exception plus the `luxestays://` URL scheme on iOS.
  `tool/patch_platforms.sh` re-applies them if you ever regenerate the hosts.

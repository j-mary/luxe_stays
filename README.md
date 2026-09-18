# LuxeStays

[![CI](https://github.com/j-mary/luxe_stays/actions/workflows/ci.yml/badge.svg)](https://github.com/j-mary/luxe_stays/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/j-mary/luxe_stays/branch/main/graph/badge.svg)](https://codecov.io/gh/j-mary/luxe_stays)

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

**Validated SDK:** Flutter 3.47.4 / Dart 3.13.3. `.fvmrc` and CI pin the SDK;
`pubspec.lock` pins package resolution.

---

## Run it

```bash
fvm use 3.47.4
make bootstrap
```

Then, in two terminals:

```bash
# 1 — the mock SynXis / Salesforce / CMS / Leonardo / PSP back end
make mock

# 2 — Android emulator
make run-emulator

# Or, for an iOS simulator
make run-ios
```

`make run-emulator` targets `emulator-5554` directly, so Flutter does not ask
you to choose between Android, iOS and Chrome. If your emulator has another ID,
use `make run-emulator ANDROID_DEVICE=<device-id>`. `make run-ios` selects the
first booted iOS simulator. Run `fvm flutter devices` to see available IDs.
The first command run with a newly installed Flutter SDK may download its
platform artifacts once before building the app.

**On Android, `localhost` is the handset, not your Mac.** Use
`make adb-reverse` once for a USB device (then `make run DEVICE=<device-id>`),
`make run-emulator` for an emulator, or `make run-lan` over Wi-Fi. Full
setup notes and troubleshooting are in
**[docs/13-RUNBOOK.md](docs/13-RUNBOOK.md)**.

Sign in on the Rewards tab with **`LS-100042`** (Gold), **`LS-100077`**
(Platinum) or **`LS-100901`** (Silver) to see member rates, points and
redemption appear.

If FVM is unavailable, pass matching Flutter and Dart commands to Make, for
example `make bootstrap FLUTTER=flutter DART=dart`.

### Build apps that use the mock back end

Keep `make mock` running while using these debug builds:

```bash
# APK configured for an Android emulator (host alias 10.0.2.2)
make build-emulator

# APK for a physical Android device connected over USB
make adb-reverse
make build-android-usb

# .app configured for a booted iOS simulator (localhost)
make build-ios-simulator

# APK for a physical device on the same Wi-Fi
make build-apk HOST=192.168.1.25
```

CI publishes two clearly named Android artifacts:

- `luxestays-android-emulator.apk` uses `10.0.2.2` and works only in an Android
  emulator whose host computer is running `make mock`.
- `luxestays-android-usb.apk` uses `localhost`; before opening it on a physical
  USB-connected device, run `make mock` and `make adb-reverse` on the computer.

The iOS artifact uses `localhost` and connects from the simulator to
`make mock` on the same Mac. A physical device over Wi-Fi needs an APK built
with a reachable LAN address, as shown above. These local HTTP settings are
limited to debug builds; production endpoints should use HTTPS.

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
| [15 — API audit](docs/15-API-AUDIT.md) | Verified provider contracts, mock assumptions, supported scenarios and production boundaries |
| [16 — Job requirements](docs/16-JOB-REQUIREMENTS.md) | Traceability from the role requirements to code, tests and documentation |
| [17 — Implementation report](docs/17-IMPLEMENTATION-REPORT.md) | Modernization changes, dependency versions, verification evidence and limitations |
| [Build handbook](docs/LuxeStays-Build-Handbook.html) | A standalone, incremental course for rebuilding the application from scratch |

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

The serif uses device fonts (`Georgia`, then `Times New Roman`, `Noto Serif`
and the platform serif), so it needs no bundled binary or runtime download.
`AppTheme.serif(...)` exposes the same fallback chain for occasional one-off
sizes such as the masthead.

---

## Status and honesty about the mocks

This is a proof of concept, and it says so where it matters:

* **The mobile shopping and booking routes are application-owned BFF
  contracts.** They demonstrate SynXis integration boundaries but are not
  presented as public SynXis wire formats. The separately implemented Property
  Hub reservation-retrieval subset follows the public 4.29.0 OpenAPI document.
  The exact evidence and assumptions are recorded in the
  [API audit](docs/15-API-AUDIT.md).
* **Leonardo endpoints are modelled adapter contracts.** Public material
  establishes Leonardo's media-distribution role but does not verify the local
  endpoint and field schema. The optional Leonardo.Ai flow is a disabled legacy
  demonstration, not a current v2 integration.
* **Salesforce and Contentful shapes follow their public documentation**, which
  is linked from the relevant documents; program names, content types and
  organisation-specific fields remain explicit local assumptions.
* **The platform host projects are committed**, with the two WebView-related
  settings already applied: cleartext to `localhost` in the Android *debug*
  manifest only, and an ATS exception plus the `luxestays://` URL scheme on iOS.
  `tool/patch_platforms.sh` re-applies them if you ever regenerate the hosts.
* **Payments and operational services are simulated.** No real money moves;
  the mocks have no durable inventory, payment reconciliation, production
  identity, Firebase deployment, signing or store release. A WebView alone does
  not establish PCI eligibility.

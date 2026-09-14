# LuxeStays

A Flutter hotel-booking proof of concept with local mock services. Search/filter hotels and rooms, build a cart, review prices, authorize a simulated hosted payment and receive a reservation. Rewards, CMS pages and a booking-engine WebView demonstrate additional integration boundaries.

**Validated SDK:** Flutter 3.47.4 / Dart 3.13.3. `.fvmrc` and CI pin the SDK; `pubspec.lock` pins package resolution. All direct/dev dependencies are current compatible stable releases as checked on 14 September 2026. Two transitive packages remain pinned by Flutter: material_color_utilities and test_api.

## Start

Install Flutter/FVM and a native emulator. In this folder:

```sh
fvm use 3.47.4
make bootstrap
make mock
```

Keep the mock server running. In another terminal:

```sh
make run-emulator             # Android, host computer at 10.0.2.2
make run HOST=localhost       # iOS simulator
```

Use only synthetic guest data. The hosted payment page simulates authorization/decline; no real money moves. Member examples: LS-100042, LS-100077, LS-100901. `STAY4` makes the fourth night free. Prices are demo USD; one room per search, up to 30 nights. Add separate offers for a multi-property cart.

If FVM is unavailable, set `FLUTTER` and `DART` when calling make to the matching SDK commands. Dart ships with Flutter. Android physical devices can use `make adb-reverse` or a trusted LAN host address.

## Verify

```sh
make format analyze test
bash tool/contract_check.sh http://localhost:8080
make integration HOST=10.0.2.2   # select Android emulator
make integration HOST=localhost # select iOS simulator
fvm flutter build apk --debug
fvm flutter build ios --simulator --debug
```

The device integration test runs search → cart → hosted mock payment → server verification → confirmed reservation. It invokes the same JavaScript function as the page's authorize action. It does not test a real bank/3DS provider.

The local suite covers models, money, cart, loyalty rules, CMS links, widgets, bridge parsing/redaction, a four-night promotional booking lifecycle, replay conflicts, validation, auth failure scenarios and Property Hub retrieval. Start mocks with `--latency 25000` for receive-timeout behavior, `--fail-rate 0.15` for intermittent failures; stop the server for connection failure. `x-mock-fail` is a test harness header.

## Beginner build course

Open `../LuxeStays-Build-Handbook.html` locally. A tracked copy is in `docs/LuxeStays-Build-Handbook.html`. The standalone HTML contains 25 progressive stages and all source files needed for the app, mocks and tests. It starts with a welcome screen, builds independent layers, then connects native search and checkout.

```sh
python3 tool/build_handbook.py
python3 tool/check_handbook.py
python3 tool/check_handbook_stages.py /absolute/path/to/flutter/bin/flutter
```

The generator reads project source to prevent documentation drift. The checker validates embedded-source equality and internal links; the stage checker reconstructs and analyzes intermediate implementations. Normal readers need only the generated HTML and Flutter tools, not these generator scripts.

## Contract truth and production boundaries

Read [API audit](docs/15-API-AUDIT.md), [job-ad traceability](docs/16-JOB-REQUIREMENTS.md) and [implementation report](docs/17-IMPLEMENTATION-REPORT.md).

The `/synxis/v1/api` shopping/create/cancel routes are **application-owned demo BFF contracts**, not the public SynXis API. The official Property Hub 4.29.0 retrieval subset is separately demonstrated at `/v1/sph/reservations/outbound/data/reservations-details`. Its OpenAPI document does not define shopping or reservation creation/cancellation. No live SynXis credentials or invented vendor mechanisms are used.

CMS fields, Salesforce program processes, Leonardo media endpoints and payment operations have explicitly documented local assumptions. The optional Leonardo.Ai legacy adapter is a simulation, not a current v2 production integration. Mocks are in-memory and unauthenticated. There is no durable inventory locking, payment capture/reconciliation, live identity, production media license, Firebase deployment, signing or store release. A WebView alone does not establish PCI eligibility.

Public URLs and identifiers can use dart-defines; secrets cannot. Secure storage protects issued tokens. Never commit real provider credentials, signing material or guest/payment data.

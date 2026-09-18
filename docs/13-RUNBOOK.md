# 13 — Runbook

## First run

The Android, iOS and web host projects are committed, so there is no
`flutter create` step:

```bash
cd luxe_stays
flutter pub get
```

Two platform settings a WebView-based app needs are already applied and
committed:

* Android: a **debug-only** manifest allowing cleartext to `localhost`
  (`android/app/src/debug/AndroidManifest.xml`). Release builds are unaffected.
* iOS: an ATS exception for `localhost`, and registration of the `luxestays://`
  URL scheme so the payment provider and booking engine can redirect back
  (`ios/Runner/Info.plist`).

`tool/patch_platforms.sh` re-applies both, should you ever regenerate the host
projects from scratch.

Then, in two terminals:

```bash
dart run tool/mock_server/server.dart     # terminal 1
make run                                  # terminal 2
```

Open <http://localhost:8080/> in a browser for a map of every mock endpoint.

## Reaching the mock server from a device

**This is the failure everyone hits once.** The mock server is running in a
terminal on your Mac, the app says "We could not reach LuxeStays", and nothing
looks wrong. On Android, `localhost` is *the handset* — not your Mac. The app
is faithfully connecting to port 8080 on the phone, where nothing is listening.

`make run` now prints the URL it is about to use, and the app logs a loud
CONFIGURATION error at startup if an Android build points at `localhost`.

Pick the row that matches how you are running:

| Target | Command | Base URL used |
|---|---|---|
| **Android, USB** (best) | `make adb-reverse` once, then `make run` | `localhost` — tunnelled to your Mac |
| Android emulator | `make run-emulator` | `10.0.2.2` |
| Android on Wi-Fi | `make run-lan` | your Mac's LAN IP (`make ip`) |
| iOS simulator, macOS, Chrome | `make run` | `localhost` |
| Anything else | `make run HOST=192.168.1.20` | whatever you pass |

### Why `adb reverse` is the best answer for a physical Android device

```bash
adb reverse tcp:8080 tcp:8080     # or: make adb-reverse
```

It tunnels the *device's* `localhost:8080` to your Mac's `localhost:8080` over
the USB cable. Nothing else has to change: no LAN IP that breaks when you move
desks, no dependency on the phone and the Mac being on the same subnet, and no
macOS firewall prompt. It has to be re-run after a device reconnect.

### If you are on Wi-Fi and it still fails

Build with `make build-lan`; it detects the Mac's current address rather than
relying on an example IP that may belong to a different subnet. Rebuild whenever
that address changes, because the URL is compiled into the APK.

1. Confirm the server is actually up and reachable off-loopback with
   `make check-lan`. Then open the same `/health` URL printed by `make mock` in
   the phone's browser. This separates network/firewall trouble from app code.
2. macOS firewall: System Settings → Network → Firewall may be blocking
   incoming connections to the `dart` process. Allow it, or use `adb reverse`.
3. Phone and Mac must be on the same network — guest Wi-Fi and "client
   isolation" on many corporate/hotel networks block device-to-device traffic.

The base URLs also feed `AppConfig.webViewAllowedOrigins`, so a mismatch shows
up as **"blocked webview navigation"** in the logs rather than a blank page.
That log line is the first thing to check if a WebView appears empty.

## Test data

| Membership | Tier | Points | Notes |
|---|---|---|---|
| `LS-100042` | Gold | 48,250 | Suggested on the sign-in screen |
| `LS-100077` | Platinum | 132,900 | 2× earn, largest balance |
| `LS-100901` | Silver | 6,400 | Just above the redemption minimum |

Seven properties across Paris, Kyoto, New York, Dubai and Cape Town. Two
fixtures exist to exercise unhappy paths on every run:

* **`H-CPT-002` has no CMS entry** — its card renders with no headline and is
  still bookable ("content is never load-bearing").
* **Every property returns one media asset with a lapsed licence** — filtered
  client-side, and the drop is logged.
* `H-CPT-002` is also **sold out for stays starting on a Monday**, so the
  no-availability path is reachable without editing fixtures.

Promotion codes that do something: `STAY4` (fourth night free), `SUITE25` (25%
off suites), `MEMKYO` (member-only, Kyoto).

## Fault injection

The whole point of the mock server. A back end that always returns 200 in 5 ms
teaches you nothing about the code paths that exist for failure.

```bash
# Every response delayed by 800 ms — watch timeouts, spinners and the
# progress bar in the WebViews.
dart run tool/mock_server/server.dart --latency 800

# 25% of requests fail with 503 — watch the retry interceptor's
# exponential backoff with full jitter, and the degradation rules.
dart run tool/mock_server/server.dart --fail-rate 0.25

# Both.
dart run tool/mock_server/server.dart --latency 400 --fail-rate 0.15
```

Per-request, from anywhere:

```bash
# Force a specific status on one call
curl -H 'x-mock-fail: 503' http://localhost:8080/synxis/v1/api/hotels

# Force a price change on re-quote — the most important unhappy path
curl -X POST http://localhost:8080/synxis/v1/api/availability/requote \
  -H 'content-type: application/json' -H 'x-mock-rate-change: 1' \
  -d '{"HotelId":"H-PAR-001","QuoteToken":"qt_H-PAR-001_DLX_BAR_2026-11-12"}'
```

To see the rate-change path **inside the app**, add the header to the SynXis
client in `providers.dart`:

```dart
headers: const <String, String>{'x-mock-rate-change': '1'},
```

then check out — the flow stops before payment and shows the guest the new
price.

## Things that go wrong, and what they mean

| Symptom | Cause | Fix |
|---|---|---|
| Search spins forever | Mock server not running, or wrong host for the platform | `curl http://localhost:8080/health`; use `10.0.2.2` on the Android emulator |
| Images are grey boxes | Leonardo base URL unreachable, or cleartext blocked | Check the base URL; on Android confirm `android/app/src/debug/AndroidManifest.xml` is present |
| WebView is blank | Origin not in the allowlist | Look for `blocked webview navigation` in the log; the origin must match a configured base URL exactly, including port |
| Payment page loads, buttons do nothing | Bridge shim not injected, or the origin check failed | Look for `webview bridge: handshake complete`; if absent, check `onPageFinished` fired |
| `Add` does nothing on a card | The offer is already in the cart | By design — `CartController.contains` de-duplicates by offer id |
| No member rates | Not signed in | Member rate plans are returned by the CRS *only* when the request carries a membership number |
| Points slider disabled | Balance below the 2,000-point minimum | Sign in as `LS-100042` |
| `flutter run` fails on Android with a minSdk error | `webview_flutter` needs 24+, `flutter_secure_storage` needs 23+ | Raise `minSdkVersion` in `android/app/build.gradle` |
| Cleartext HTTP blocked on iOS | ATS | Confirm the `NSExceptionDomains` entry for `localhost` in `ios/Runner/Info.plist` |

## Reading the logs

Every log line can carry a correlation id (`cid=ls_…`), which is the same value
sent to every vendor as `X-Correlation-Id`.

```
[INFO] LuxeStays starting {flavor: dev, synxis: http://localhost:8080/synxis, …}
[DEBUG] → POST http://localhost:8080/synxis/v1/api/availability cid=ls_m4x9_1a2b3c4d
[INFO] ← 200 POST …/availability cid=ls_m4x9_1a2b3c4d {durationMs: 143}
[INFO] search complete {destination: PAR, properties: 2, available: 2, afterFilters: 2, withContent: 1, ms: 356}
[WARN] leonardo: dropped 1 asset(s) with an expired licence {hotelId: H-PAR-001}
[INFO] webview bridge: handshake complete, flushing 1 queued message(s)
```

`search complete` is the line to watch while developing: `properties` vs
`available` vs `afterFilters` tells you immediately whether an empty screen is
the CRS, the filters, or a bug — and `withContent` tells you whether the CMS
answered.

Bodies are only logged in dev/staging, and everything passes through
`AppLogger.redact` first.

## Useful commands

```bash
make help          # every target
make analyze       # static analysis
make test          # unit + widget
make coverage      # writes coverage/lcov.info
make integration   # on-device end-to-end (needs the mock server and a device)
make format        # dart format
make ci            # exactly what CI runs

bash tool/contract_check.sh http://localhost:8080   # vendor contract smoke test
curl http://localhost:8080/health                    # mock server status
```

## Resetting state

The mock server holds reservations, payment intents, loyalty balances and
idempotency keys **in memory**. Restart it to reset everything — including a
member's points balance after you have spent them.

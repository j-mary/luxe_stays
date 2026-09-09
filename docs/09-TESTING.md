# 09 — Testing

## The shape of the suite

```
        ▲  integration_test/    1 test    on-device, needs the mock server
       ╱ ╲  widget tests        6 tests   render + interaction, no network
      ╱   ╲ unit tests         40+ tests  maths, mapping, protocol, state
     ╱─────╲
```

The bias is deliberate. In an integration-heavy app the expensive bugs are not
in layout — they are in **mapping, money, protocol and state transitions**, and
all four are cheap to test without a widget tree.

## Running it

```bash
flutter test                    # unit + widget
flutter test --coverage         # writes coverage/lcov.info
flutter test test/integrations  # one directory
make ci                         # what CI runs: format + analyze + test
```

Integration test (needs the mock server up):

```bash
dart run tool/mock_server/server.dart   # terminal 1
make integration                        # terminal 2 — needs a booted device
```

Contract check (also runs in CI):

```bash
bash tool/contract_check.sh http://localhost:8080
```

## What each layer is for

### Unit — the maths and the mapping

| File | Guards |
|---|---|
| [`test/core/money_test.dart`](../test/core/money_test.dart) | Integer money: three nights at 333.33 totalling 999.99, half-up percentage rounding, vendor amounts arriving as numbers *and* strings, formatting and grouping |
| [`test/core/redaction_test.dart`](../test/core/redaction_test.dart) | No token, card number or email reaches a log — at any nesting depth, inside lists, case-insensitively |
| [`test/core/error_mapper_test.dart`](../test/core/error_mapper_test.dart) | Each vendor's error envelope maps to the right `Failure`; `RATE_CHANGED` is promoted to its own type with both totals; `Retry-After` is honoured; 5xx is retryable and 4xx is not |
| [`test/integrations/synxis_mapper_test.dart`](../test/integrations/synxis_mapper_test.dart) | DTO → domain: nightly rates, taxes, totals, deterministic offer ids, cancellation policy, member savings — and that a missing field raises a `ContractFailure` **naming the field** |
| [`test/integrations/cms_links_test.dart`](../test/integrations/cms_links_test.dart) | Contentful link resolution, including an unpublished reference resolving to `null` instead of throwing |
| [`test/integrations/loyalty_rules_test.dart`](../test/integrations/loyalty_rules_test.dart) | Earn floors rather than rounds; redemption respects minimum, increment and basket cap; expired and minimum-spend vouchers discount nothing |
| [`test/webview/bridge_message_test.dart`](../test/webview/bridge_message_test.dart) | Malformed page input returns `null` and never throws; host-only message types are rejected; a newer protocol version still parses; **wire names are pinned** |
| [`test/features/cart_controller_test.dart`](../test/features/cart_controller_test.dart) | Multi-property totals, de-duplication, revision bumps (which feed idempotency keys), blocked lines preventing checkout, an oversized voucher clamping at zero |

Two of those deserve calling out.

**The contract test with a named field.** When a vendor changes a schema, the
failure should say `missing required string "RatePlanCode"`, not
`type 'Null' is not a subtype of 'String'` three frames into a build method.
That test is what keeps `JsonRead` honest.

**Pinned wire names.** `payment.result`, `booking.result`, `LuxeStaysBridge` and
`protocolVersion: 1` are a published contract with the web team. A rename must
break a test, because it is a protocol version bump.

### Widget — render and interact, no network

[`test/widgets/hotel_card_test.dart`](../test/widgets/hotel_card_test.dart) runs
with `mediaProviderProvider` overridden by a `StaticMediaProvider`. That
override is only possible because widgets depend on the `MediaProvider`
*interface* rather than on a Leonardo client — the seam pays for itself here.

The cases are chosen to be behavioural, not cosmetic:

* renders name, location and the lead-in nightly price;
* **renders correctly with no CMS content** — the "content is never
  load-bearing" rule, asserted rather than asserted-in-prose;
* shows the CMS headline once content has resolved;
* badges member rates and low inventory;
* shows the saving against the public rate;
* handles a property with no availability.

### Integration — the fan-out on a real device

[`integration_test/app_test.dart`](../integration_test/app_test.dart) drives
search → detail → cart against the mock server. What it protects is that the
multi-vendor composition really works on a device, with real plugins and real
async timing.

It deliberately **stops short of the payment WebView**. Driving a WebView from
`integration_test` is possible but slow and flaky, and the value is low compared
with the bridge unit tests plus a scripted manual pass. Being explicit about
what you chose not to automate, and why, is part of a test strategy.

### Contract — the early-warning system

`tool/contract_check.sh` calls every vendor and asserts that every field the
Dart clients decode is still present. Pointed at the mock server it is a fast
CI gate; pointed at real sandboxes (SynXis CERT, a Salesforce scratch org, the
CMS preview environment) it is what tells you a vendor changed something **on
the day it happened** rather than on release day.

It also asserts the idempotency contract — replaying a key must return the
original intent — because that behaviour is what makes the retry interceptor
safe, and it is invisible in any unit test.

## Fault injection

The mock server takes `--latency` and `--fail-rate`, and honours an
`x-mock-fail: 503` header per request. A mock that only ever returns 200 in 5 ms
teaches you nothing about the behaviour the retry, timeout and degradation logic
exists for. See [13 — Runbook](13-RUNBOOK.md).

## What is not tested, and why

* **Golden/screenshot tests.** Valuable for a design-system-heavy app; they need
  a stable font environment and a review workflow to be worth their maintenance
  cost. The hook (`StaticMediaProvider`) is already in place.
* **The payment WebView end to end.** As above — a scripted manual pass against
  the PSP's sandbox is the better tool.
* **Performance regression tests.** `flutter test --profile` with timeline
  assertions on the search list would be the next addition, given how
  image-heavy the scroll is.

## Conventions

* No mocking framework for anything a provider override can do. `mocktail` is
  available for the few cases where behaviour verification is genuinely needed.
* Fixtures are typed constructors, not JSON files, so a domain change breaks the
  test at compile time rather than at run time.
* Every test name states a behaviour, not a method: "refuses to add the same
  offer twice", not "test add".

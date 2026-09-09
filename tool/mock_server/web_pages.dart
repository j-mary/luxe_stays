/// The two hybrid web surfaces the app embeds: the PSP hosted payment page and
/// the SynXis booking engine.
///
/// Both are deliberately written the way a real vendor page would be - plain
/// HTML with a small script that talks to the host over the JavaScript bridge,
/// and a redirect fallback for hosts that do not inject a bridge at all. Read
/// them alongside `docs/02-WEBVIEW-BRIDGE.md`.
library;

const String _bridgeClient = '''
<script>
  // Vendor-side helper. Mirrors the shim the Flutter host injects, and degrades
  // to a deep-link redirect when there is no host (e.g. opened in a browser).
  var Host = {
    ready: false,
    init: null,
    send: function (type, payload) {
      if (window.LuxeStaysBridge && window.LuxeStaysBridge.post) {
        window.LuxeStaysBridge.post(type, payload);
        return true;
      }
      return false;
    },
    redirect: function (url) { window.location.href = url; },
    onInit: function (fn) {
      if (window.LuxeStaysBridge && window.LuxeStaysBridge.on) {
        window.LuxeStaysBridge.on('init', function (payload) {
          Host.ready = true;
          Host.init = payload;
          fn(payload);
        });
      }
    },
  };
</script>
''';

String hostedPaymentPage({
  required String intentId,
  required int amountMinor,
  required String currency,
}) {
  final String amount = (amountMinor / 100).toStringAsFixed(2);
  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Secure payment</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 16px/1.5 -apple-system, "Segoe UI", Roboto, sans-serif;
         margin: 0; padding: 24px 20px 40px; max-width: 560px; }
  .lock { font-size: 13px; color: #2e7d32; margin-bottom: 6px; }
  h1 { font-size: 20px; margin: 0 0 2px; }
  .amount { font-size: 32px; font-weight: 700; margin: 12px 0 20px; }
  label { display: block; font-size: 13px; margin: 14px 0 4px; color: #555; }
  input { width: 100%; box-sizing: border-box; padding: 12px;
          font-size: 16px; border: 1px solid #ccc; border-radius: 10px; }
  .row { display: flex; gap: 12px; }
  .row > div { flex: 1; }
  button { width: 100%; padding: 14px; font-size: 16px; font-weight: 600;
           border: 0; border-radius: 12px; margin-top: 20px; cursor: pointer; }
  .pay { background: #14342B; color: #fff; }
  .alt { background: transparent; color: #b3261e; margin-top: 8px;
         border: 1px solid #b3261e; }
  .note { font-size: 12px; color: #777; margin-top: 18px; }
  .three-ds { display: none; padding: 16px; border: 1px dashed #888;
              border-radius: 12px; margin-top: 16px; }
</style>
</head>
<body>
  <div class="lock">&#128274; Secure page hosted by the payment provider</div>
  <h1>Complete your payment</h1>
  <div class="amount">$currency $amount</div>

  <label for="pan">Card number</label>
  <input id="pan" inputmode="numeric" value="4242 4242 4242 4242" autocomplete="cc-number">
  <div class="row">
    <div>
      <label for="exp">Expiry</label>
      <input id="exp" value="12/29" autocomplete="cc-exp">
    </div>
    <div>
      <label for="cvc">CVC</label>
      <input id="cvc" value="123" autocomplete="cc-csc">
    </div>
  </div>

  <div class="three-ds" id="threeds">
    <strong>Your bank needs to check it is you.</strong>
    <p>This stands in for a 3-D Secure step-up. In production the issuer's own
    page renders here - which is precisely why this flow is a WebView.</p>
    <button class="pay" onclick="finish('authorize', true)">I have approved it</button>
  </div>

  <button class="pay" onclick="startAuthorize()">Pay $currency $amount</button>
  <button class="alt" onclick="finish('decline', false)">Simulate a decline</button>
  <button class="alt" onclick="finish('cancel', false)">Cancel</button>

  <p class="note">Card details never leave this page. The LuxeStays app receives
  only an intent id and the outcome, which is what keeps the mobile app outside
  PCI-DSS scope.</p>

$_bridgeClient
<script>
  var INTENT = ${_jsString(intentId)};

  Host.onInit(function (payload) {
    // The host tells us its locale, theme and safe-area insets. A real vendor
    // page would use them to match the app's chrome.
    document.body.style.paddingTop =
      ((payload && payload.safeArea && payload.safeArea.top) || 0) + 24 + 'px';
    Host.send('log', { level: 'info', message: 'payment page ready' });
  });

  function startAuthorize() {
    // Half the time, pretend the issuer wants a step-up.
    if (Math.random() < 0.5) {
      document.getElementById('threeds').style.display = 'block';
      window.scrollTo(0, document.body.scrollHeight);
      return;
    }
    finish('authorize', false);
  }

  function finish(outcome, threeDs) {
    fetch('/payments/intents/' + INTENT + '/authorize', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ outcome: outcome, threeDs: threeDs }),
    })
      .then(function (r) { return r.json(); })
      .then(function (result) {
        var sent = Host.send('payment.result', {
          intentId: result.intentId,
          status: result.status,
          authorizationCode: result.authorizationCode,
          declineReason: result.declineReason,
          last4: result.last4,
          brand: result.brand,
          threeDsPerformed: result.threeDsPerformed,
        });
        if (!sent) {
          // No bridge: fall back to the deep link the host intercepts.
          var host = result.status === 'authorized' ? 'payment-success'
                   : result.status === 'cancelled' ? 'payment-cancel'
                   : 'payment-failure';
          Host.redirect('luxestays://' + host + '?intent=' + result.intentId +
            '&auth=' + (result.authorizationCode || '') +
            '&last4=' + (result.last4 || '') +
            '&brand=' + (result.brand || '') +
            '&threeds=' + (result.threeDsPerformed ? 'true' : 'false'));
        }
      })
      .catch(function (e) {
        Host.send('error', { message: String(e), source: 'payment' });
      });
  }
</script>
</body>
</html>
''';
}

String bookingEnginePage({
  required String hotelId,
  required String hotelName,
  required String arrive,
  required String depart,
  required String currency,
  required int nightlyMinor,
  String? promotionCode,
  String? membershipNumber,
}) {
  final String nightly = (nightlyMinor / 100).toStringAsFixed(2);
  return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$hotelName</title>
<style>
  :root { color-scheme: light dark; }
  body { font: 16px/1.5 -apple-system, "Segoe UI", Roboto, sans-serif;
         margin: 0; padding: 20px 18px 40px; max-width: 640px; }
  h1 { font-size: 20px; margin: 0 0 2px; }
  .sub { color: #777; font-size: 13px; margin-bottom: 18px; }
  .card { border: 1px solid #ddd; border-radius: 14px; padding: 16px;
          margin-bottom: 12px; }
  .card h2 { font-size: 16px; margin: 0 0 4px; }
  .price { float: right; font-weight: 700; }
  label { display: block; margin-top: 10px; font-size: 14px; }
  button { width: 100%; padding: 14px; font-size: 16px; font-weight: 600;
           border: 0; border-radius: 12px; margin-top: 16px;
           background: #14342B; color: #fff; cursor: pointer; }
  .ghost { background: transparent; color: #14342B; border: 1px solid #14342B; }
  .banner { background: #EEF4F0; border-radius: 10px; padding: 10px 12px;
            font-size: 13px; margin-bottom: 14px; }
</style>
</head>
<body>
  <h1>$hotelName</h1>
  <div class="sub">$arrive &rarr; $depart · booking engine (SynXis) · property $hotelId</div>

  ${promotionCode == null ? '' : '<div class="banner">Offer <strong>$promotionCode</strong> applied by the app.</div>'}
  ${membershipNumber == null ? '' : '<div class="banner">Member rates unlocked for <strong>$membershipNumber</strong>.</div>'}

  <div class="banner">These packages and add-ons are configured by the property
  in the CRS. They change without an app release - which is the reason this
  step is web rather than native.</div>

  <div class="card">
    <span class="price">$currency $nightly</span>
    <h2>Deluxe room</h2>
    <div>Room only · free cancellation</div>
    <label><input type="checkbox" id="addBreakfast"> Add breakfast (+$currency 42.00 / night)</label>
    <label><input type="checkbox" id="addSpa"> Spa credit (+$currency 120.00)</label>
    <label><input type="checkbox" id="addTransfer"> Airport transfer (+$currency 95.00)</label>
  </div>

  <button onclick="complete()">Confirm booking</button>
  <button class="ghost" onclick="cancel()">Back to the app</button>

$_bridgeClient
<script>
  var HOTEL = ${_jsString(hotelId)};
  var CURRENCY = ${_jsString(currency)};
  var NIGHTLY = $nightlyMinor;

  Host.onInit(function (payload) {
    Host.send('log', { level: 'info', message: 'booking engine ready for ' + HOTEL });
  });

  function total() {
    var t = NIGHTLY;
    if (document.getElementById('addBreakfast').checked) { t += 4200; }
    if (document.getElementById('addSpa').checked) { t += 12000; }
    if (document.getElementById('addTransfer').checked) { t += 9500; }
    return t;
  }

  function reference() {
    var a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789', s = 'LX';
    for (var i = 0; i < 6; i++) { s += a[Math.floor(Math.random() * a.length)]; }
    return s;
  }

  function complete() {
    var ref = reference(), amount = total();
    var sent = Host.send('booking.result', {
      status: 'completed',
      confirmationNumber: ref,
      hotelId: HOTEL,
      totalMinor: amount,
      currency: CURRENCY,
    });
    if (!sent) {
      Host.redirect('luxestays://booking-complete?confirmation=' + ref +
        '&hotel=' + HOTEL + '&totalMinor=' + amount + '&currency=' + CURRENCY);
    }
  }

  function cancel() {
    if (!Host.send('booking.result', { status: 'cancelled' })) {
      Host.redirect('luxestays://booking-cancelled');
    }
  }
</script>
</body>
</html>
''';
}

/// Emits a safely-quoted JavaScript string literal. Interpolating a raw value
/// into a script tag is how you get an injection bug the first time a hotel
/// name contains an apostrophe.
String _jsString(String value) {
  final String escaped = value
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      // Prevents a value containing "</script>" from closing the tag early.
      .replaceAll('</', '<\\/');
  return "'$escaped'";
}

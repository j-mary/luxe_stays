#!/usr/bin/env bash
# Local demo gateway smoke test. Not a vendor conformance suite.
#
# Asserts that every field the Dart clients decode is still present in the
# responses. Run against the mock server locally, or against the vendors'
# sandbox environments in CI to catch a breaking upstream change on the day it
# lands rather than on release day.
#
#   bash tool/contract_check.sh http://localhost:8080
set -euo pipefail

BASE="${1:-http://localhost:8080}"
FAILED=0

check() {
  local label="$1"; shift
  local body="$1"; shift
  for field in "$@"; do
    if ! grep -q "\"$field\"" <<<"$body"; then
      echo "  ✗ $label: missing field \"$field\""
      FAILED=1
    fi
  done
  if [ "$FAILED" -eq 0 ]; then
    echo "  ✓ $label"
  fi
}

echo "SynXis"
HOTELS=$(curl -sf "$BASE/synxis/v1/api/hotels?chainId=12345")
check "hotels" "$HOTELS" Hotels HotelId HotelName City CountryCode Rating

AVAIL=$(curl -sf -X POST "$BASE/synxis/v1/api/availability" \
  -H 'content-type: application/json' \
  -d '{"ChainId":"12345","HotelIds":["H-PAR-001"],"Stay":{"Arrival":"2026-11-12","Departure":"2026-11-14"},"Occupancy":{"Adults":2,"ChildAges":[],"Rooms":1},"Currency":"USD"}')
check "availability" "$AVAIL" HotelAvailability Offers RatePlanCode NightlyRates TaxesAndFees QuoteToken

echo "Salesforce"
MEMBER=$(curl -sf "$BASE/salesforce/services/data/v62.0/connect/loyalty/programs/LuxeStaysRewards/members?membershipNumber=LS-100042")
check "loyalty member" "$MEMBER" members loyaltyProgramMemberId membershipNumber memberCurrencies memberTiers

echo "CMS"
ENTRIES=$(curl -sf "$BASE/cms/spaces/luxestays/environments/master/entries?content_type=hotelContent&fields.hotelId%5Bin%5D=H-PAR-001&include=2")
check "hotel content" "$ENTRIES" items fields hotelId headline includes

echo "Leonardo"
MEDIA=$(curl -sf "$BASE/leonardo/v1/properties/H-PAR-001/media")
check "media" "$MEDIA" assets mediaId deliveryUrl category

RENDITION=$(curl -sfI "$BASE/leonardo/img/H-PAR-001-hero.png?w=720&h=480")
if grep -qi 'content-type: image/png' <<<"$RENDITION"; then
  echo "  ✓ rendition serves a PNG"
else
  echo "  ✗ rendition did not serve a PNG"
  FAILED=1
fi

echo "Payments"
INTENT=$(curl -sf -X POST "$BASE/payments/intents" \
  -H 'content-type: application/json' -H 'idempotency-key: contract-check' \
  -d '{"amountMinor":65000,"currency":"USD","cartId":"cart_contract","returnUrl":"luxestays://payment-success"}')
check "payment intent" "$INTENT" intentId hostedPageUrl amountMinor expiresAt

# Replaying the same idempotency key must not create a second intent.
REPLAY=$(curl -sf -X POST "$BASE/payments/intents" \
  -H 'content-type: application/json' -H 'idempotency-key: contract-check' \
  -d '{"amountMinor":65000,"currency":"USD","cartId":"cart_contract","returnUrl":"luxestays://payment-success"}')
if [ "$INTENT" = "$REPLAY" ]; then
  echo "  ✓ idempotency key replays the original intent"
else
  echo "  ✗ idempotent replay produced a different intent"
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo
  echo "Contract check FAILED - a vendor response no longer matches what the app decodes."
  exit 1
fi
echo
echo "All local demo contracts OK."

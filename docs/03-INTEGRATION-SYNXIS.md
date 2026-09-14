# SynXis integration boundary

Read [the dated API audit](15-API-AUDIT.md) for exact public evidence, mock scenarios and limitations.

The Flutter `SynxisApi` class calls the application-owned `/synxis/v1/api` demo gateway. Its PascalCase DTOs, quote tokens, create/retrieve/cancel operations and idempotency header are not documented Property Hub contracts. They must not be sent to a live SynXis origin.

The mock separately implements the public Property Hub 4.29.0 retrieval subset at `POST /v1/sph/reservations/outbound/data/reservations-details`. It uses `tenantId`, integer IDs and the documented lower-camelCase envelope. No live authentication or persistent delta cursor is simulated. Official shopping and booking contracts must come from the actual CRS agreement; the public Property Hub document does not supply them.

Run `flutter test test/integrations/mock_booking_flow_test.dart` with the pinned SDK for documented retrieval-shape and demo booking-lifecycle tests. These are local contract tests, not vendor certification.

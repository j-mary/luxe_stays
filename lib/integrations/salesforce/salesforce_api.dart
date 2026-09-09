import '../../core/network/api_client.dart';
import '../../core/result.dart';
import '../../core/utils/money.dart';
import '../../domain/booking.dart';
import 'salesforce_models.dart';

/// Transport for Salesforce.
///
/// Three distinct Salesforce capabilities are used, all over the same REST
/// base (`/services/data/{version}/...`):
///
/// | Capability | Used for | Resource |
/// |---|---|---|
/// | Loyalty Management | balances, tiers, vouchers, accrual/redemption | `/connect/loyalty/...` |
/// | Platform REST/SOQL | points ledger history | `/query?q=...` |
/// | Service Cloud | in-app support cases | `/sobjects/Case` |
///
/// The API version is pinned in [AppConfig.salesforceApiVersion]. Salesforce
/// keeps three releases a year and deprecates versions slowly, so pinning -
/// rather than following "latest" - is what stops a Salesforce release weekend
/// from breaking a shipped app binary.
class SalesforceApi {
  SalesforceApi({
    required ApiClient client,
    required String apiVersion,
    required String loyaltyProgramName,
  })  : _client = client,
        _apiVersion = apiVersion,
        _programName = loyaltyProgramName;

  final ApiClient _client;
  final String _apiVersion;
  final String _programName;

  String get _data => '/services/data/$_apiVersion';
  String get _loyalty => '$_data/connect/loyalty/programs/$_programName';

  /// Member lookup by membership number.
  Future<Result<SalesforceMemberDto>> memberByNumber(String membershipNumber) {
    return _client.getJson<SalesforceMemberDto>(
      '$_loyalty/members',
      query: <String, Object?>{'membershipNumber': membershipNumber},
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        // The Connect API returns a collection even for a unique lookup.
        final Object? members =
            root['members'] ?? root['loyaltyProgramMembers'];
        if (members == null) {
          return SalesforceMemberDto.fromJson(root);
        }
        final List<Map<String, Object?>> list =
            JsonRead.objectList(members, 'members');
        if (list.isEmpty) {
          throw StateError('no member for $membershipNumber');
        }
        return SalesforceMemberDto.fromJson(list.first);
      },
    );
  }

  Future<Result<SalesforceMemberDto>> member(String memberId) {
    return _client.getJson<SalesforceMemberDto>(
      '$_loyalty/members/$memberId',
      decode: (Object? json) =>
          SalesforceMemberDto.fromJson(JsonRead.object(json, 'root')),
    );
  }

  Future<Result<List<SalesforceVoucherDto>>> vouchers(String memberId) {
    return _client.getJson<List<SalesforceVoucherDto>>(
      '$_loyalty/members/$memberId/vouchers',
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return JsonRead.objectList(root['vouchers'], 'vouchers')
            .map(SalesforceVoucherDto.fromJson)
            .toList(growable: false);
      },
    );
  }

  /// Points history, read with SOQL against `LoyaltyLedger`.
  ///
  /// SOQL rather than a Connect resource because the ledger is exactly the kind
  /// of "give me the last 50 rows ordered by date" query the Connect endpoints
  /// do not expose. The query is parameterised through the query string, and
  /// the member id is a Salesforce 18-char id - never free guest input - so
  /// there is no injection surface. Anything guest-supplied would be escaped in
  /// the BFF instead of here.
  Future<Result<List<SalesforceLedgerEntryDto>>> ledger(
    String memberId, {
    int limit = 50,
  }) {
    final String soql = 'SELECT Id, EventDate, Points, Description, EventType, '
        'JournalReference, HotelName FROM LoyaltyLedger '
        "WHERE LoyaltyProgramMemberId = '$memberId' "
        'ORDER BY EventDate DESC LIMIT $limit';
    return _client.getJson<List<SalesforceLedgerEntryDto>>(
      '$_data/query',
      query: <String, Object?>{'q': soql},
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        return JsonRead.objectList(root['records'], 'records')
            .map(SalesforceLedgerEntryDto.fromJson)
            .toList(growable: false);
      },
    );
  }

  /// Posts an accrual for a completed booking.
  ///
  /// Runs a **Loyalty Program Process** rather than inserting a ledger row
  /// directly: the process is where the business configures earn rates, tier
  /// multipliers and promotion stacking, and it is owned by the loyalty team in
  /// Salesforce - not by us. The app supplies facts (spend, nights, property),
  /// Salesforce decides the points.
  Future<Result<SalesforceProcessResult>> accrue({
    required String membershipNumber,
    required Reservation reservation,
    required Money eligibleSpend,
    required String idempotencyKey,
  }) {
    return _client.postJson<SalesforceProcessResult>(
      '$_loyalty/program-processes/AccrueStayPoints',
      idempotencyKey: idempotencyKey,
      body: <String, Object?>{
        'processParameters': <Map<String, Object?>>[
          <String, Object?>{
            'MembershipNumber': membershipNumber,
            'TransactionJournalType': 'Accrual',
            'ActivityDate': reservation.createdAt.toUtc().toIso8601String(),
            'BookingReference': reservation.confirmationNumber,
            'HotelId': reservation.hotelId,
            'HotelName': reservation.hotelName,
            'Nights': reservation.offer.stay.nights,
            'EligibleAmount': eligibleSpend.asDouble,
            'CurrencyIsoCode': eligibleSpend.currency,
            'Channel': 'Mobile App',
          },
        ],
      },
      decode: (Object? json) =>
          SalesforceProcessResult.fromJson(JsonRead.object(json, 'root')),
    );
  }

  /// Burns points, returning the voucher Salesforce issued in exchange.
  Future<Result<SalesforceProcessResult>> redeem({
    required String membershipNumber,
    required int points,
    required String currency,
    required String idempotencyKey,
    String? cartId,
  }) {
    return _client.postJson<SalesforceProcessResult>(
      '$_loyalty/program-processes/RedeemPointsForVoucher',
      idempotencyKey: idempotencyKey,
      body: <String, Object?>{
        'processParameters': <Map<String, Object?>>[
          <String, Object?>{
            'MembershipNumber': membershipNumber,
            'TransactionJournalType': 'Redemption',
            'Points': points,
            'CurrencyIsoCode': currency,
            if (cartId != null) 'ExternalReference': cartId,
            'Channel': 'Mobile App',
          },
        ],
      },
      decode: (Object? json) =>
          SalesforceProcessResult.fromJson(JsonRead.object(json, 'root')),
    );
  }

  /// Enrols a new member (sign-up inside the app).
  Future<Result<SalesforceMemberDto>> enrol({
    required String firstName,
    required String lastName,
    required String email,
    bool marketingOptIn = false,
  }) {
    return _client.postJson<SalesforceMemberDto>(
      '$_loyalty/individual-member-enrollments',
      body: <String, Object?>{
        'enrollmentDate': DateTime.now().toUtc().toIso8601String(),
        'membershipNumber': null,
        'associatedContactDetails': <String, Object?>{
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'allowSolicitation': marketingOptIn,
        },
        'memberStatus': 'Active',
      },
      decode: (Object? json) =>
          SalesforceMemberDto.fromJson(JsonRead.object(json, 'root')),
    );
  }

  /// Raises a Service Cloud case from the in-app "Need help?" flow.
  ///
  /// Attaching the correlation id of the failed request means the agent opens
  /// the case already holding the thread that ties the guest's problem to our
  /// logs and to the vendor's.
  Future<Result<String>> createCase({
    required String subject,
    required String description,
    String? contactId,
    String? bookingReference,
    String? correlationId,
    String priority = 'Medium',
    String origin = 'Mobile App',
  }) {
    return _client.postJson<String>(
      '$_data/sobjects/Case',
      body: <String, Object?>{
        'Subject': subject,
        'Description': description,
        'Priority': priority,
        'Origin': origin,
        if (contactId != null) 'ContactId': contactId,
        if (bookingReference != null) 'BookingReference__c': bookingReference,
        if (correlationId != null) 'CorrelationId__c': correlationId,
      },
      decode: (Object? json) =>
          JsonRead.string(JsonRead.object(json, 'root'), 'id'),
    );
  }
}

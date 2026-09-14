import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result.dart';
import '../../core/utils/money.dart';
import '../../domain/booking.dart';
import '../../domain/loyalty.dart';
import 'salesforce_api.dart';
import 'salesforce_models.dart';

/// Domain-facing Salesforce operations for the loyalty programme.
///
/// The important design decision lives in [postAccrual]: **loyalty must never
/// fail a booking.** The reservation is already made and the guest is already
/// charged by the time we post points. If Salesforce is down, we record the
/// intent locally, tell the guest their points are "on the way", and let a
/// retry (or a nightly server-side reconciliation) settle it. Blocking the
/// confirmation screen on a CRM write would be trading a real revenue event for
/// a cosmetic one.
class SalesforceRepository {
  SalesforceRepository({
    required this._api,
    required this._logger,
    this._rules = const LoyaltyProgramRules(),
  });

  final SalesforceApi _api;
  final AppLogger _logger;
  final LoyaltyProgramRules _rules;

  /// Accruals that could not be posted. In production this is a persisted
  /// outbox drained by a background isolate / WorkManager job; here it is
  /// in-memory and drained by [retryDeferredAccruals].
  final List<DeferredAccrual> _deferredAccruals = <DeferredAccrual>[];

  LoyaltyProgramRules get rules => _rules;

  List<DeferredAccrual> get deferredAccruals =>
      List<DeferredAccrual>.unmodifiable(_deferredAccruals);

  /// Loads the full member view: profile, vouchers and ledger, in parallel.
  ///
  /// The member profile is required; vouchers and ledger are best-effort. A
  /// loyalty screen that renders a balance with an empty history is far better
  /// than one that renders an error because a secondary call timed out.
  Future<Result<LoyaltyMemberView>> memberView(String membershipNumber) async {
    final Result<SalesforceMemberDto> memberResult = await _api.memberByNumber(
      membershipNumber,
    );

    return memberResult.fold<Future<Result<LoyaltyMemberView>>>((
      SalesforceMemberDto dto,
    ) async {
      // Fired together, awaited separately: two round trips in the time of
      // one, without losing the static types that Future.wait would erase.
      final Future<Result<List<SalesforceVoucherDto>>> voucherFuture = _api
          .vouchers(dto.memberId);
      final Future<Result<List<SalesforceLedgerEntryDto>>> ledgerFuture = _api
          .ledger(dto.memberId);
      final Result<List<SalesforceVoucherDto>> voucherResult =
          await voucherFuture;
      final Result<List<SalesforceLedgerEntryDto>> ledgerResult =
          await ledgerFuture;

      final List<LoyaltyVoucher> vouchers =
          voucherResult.valueOrNull
              ?.map((SalesforceVoucherDto v) => v.toDomain())
              .toList(growable: false) ??
          const <LoyaltyVoucher>[];
      final List<PointsLedgerEntry> ledger =
          ledgerResult.valueOrNull
              ?.map((SalesforceLedgerEntryDto e) => e.toDomain())
              .toList(growable: false) ??
          const <PointsLedgerEntry>[];

      if (voucherResult.failureOrNull != null) {
        _logger.warn(
          'salesforce: vouchers unavailable, degrading gracefully',
          correlationId: voucherResult.failureOrNull?.correlationId,
        );
      }

      return Ok<LoyaltyMemberView>(
        LoyaltyMemberView(
          member: dto.toDomain(vouchers: vouchers),
          ledger: ledger,
          ledgerAvailable: ledgerResult.isOk,
          vouchersAvailable: voucherResult.isOk,
        ),
      );
    }, (Failure failure) async => Err<LoyaltyMemberView>(failure));
  }

  /// Posts points for a completed reservation. Never throws.
  Future<AccrualOutcome> postAccrual({
    required String membershipNumber,
    required Reservation reservation,
    required Money eligibleSpend,
  }) async {
    final String idempotencyKey = 'accrual_${reservation.confirmationNumber}';
    final Result<SalesforceProcessResult> result = await _api.accrue(
      membershipNumber: membershipNumber,
      reservation: reservation,
      eligibleSpend: eligibleSpend,
      idempotencyKey: idempotencyKey,
    );

    return result.fold<AccrualOutcome>(
      (SalesforceProcessResult process) {
        if (!process.isSuccess) {
          _logger.warn(
            'salesforce: accrual process returned ${process.status}',
            context: <String, Object?>{
              'confirmation': reservation.confirmationNumber,
            },
          );
          return AccrualOutcome.deferred(
            estimatedPoints: _rules.estimateAccrual(
              eligibleSpend: eligibleSpend,
              tier: LoyaltyTier.classic,
            ),
          );
        }
        return AccrualOutcome.posted(
          points: process.pointsChange,
          newBalance: process.newBalance,
          journalId: process.transactionJournalId,
        );
      },
      (Failure failure) {
        _logger.error(
          'salesforce: accrual failed, deferring',
          correlationId: failure.correlationId,
          context: <String, Object?>{
            'confirmation': reservation.confirmationNumber,
            'retryable': failure.isRetryable,
          },
          error: failure,
        );
        _deferredAccruals.add(
          DeferredAccrual(
            membershipNumber: membershipNumber,
            reservation: reservation,
            eligibleSpend: eligibleSpend,
            queuedAt: DateTime.now(),
            lastFailure: failure.developerMessage,
          ),
        );
        return AccrualOutcome.deferred(
          estimatedPoints: _rules.estimateAccrual(
            eligibleSpend: eligibleSpend,
            tier: LoyaltyTier.classic,
          ),
        );
      },
    );
  }

  /// Drains the outbox. Safe to call repeatedly: every accrual carries the same
  /// idempotency key, so a duplicate post is a no-op server side.
  Future<int> retryDeferredAccruals() async {
    if (_deferredAccruals.isEmpty) {
      return 0;
    }
    final List<DeferredAccrual> pending = List<DeferredAccrual>.from(
      _deferredAccruals,
    );
    int posted = 0;
    for (final DeferredAccrual accrual in pending) {
      final Result<SalesforceProcessResult> result = await _api.accrue(
        membershipNumber: accrual.membershipNumber,
        reservation: accrual.reservation,
        eligibleSpend: accrual.eligibleSpend,
        idempotencyKey: 'accrual_${accrual.reservation.confirmationNumber}',
      );
      if (result.isOk) {
        _deferredAccruals.remove(accrual);
        posted++;
      }
    }
    _logger.info(
      'salesforce: drained $posted deferred accrual(s), '
      '${_deferredAccruals.length} remaining',
    );
    return posted;
  }

  /// Burns points and returns the voucher Salesforce issued.
  Future<Result<LoyaltyVoucher>> redeemPoints({
    required String membershipNumber,
    required int points,
    required String currency,
    required String cartId,
  }) async {
    if (points < _rules.minimumRedemption) {
      return Err<LoyaltyVoucher>(
        ClientFailure(
          userMessage:
              'You need at least '
              '${_rules.minimumRedemption} points to redeem.',
          developerMessage: 'redeem below minimum: $points',
          statusCode: 422,
        ),
      );
    }

    final Result<SalesforceProcessResult> result = await _api.redeem(
      membershipNumber: membershipNumber,
      points: points,
      currency: currency,
      cartId: cartId,
      idempotencyKey: 'redeem_${cartId}_$points',
    );

    return result.fold<Result<LoyaltyVoucher>>((
      SalesforceProcessResult process,
    ) {
      final SalesforceVoucherDto? voucher = process.voucher;
      if (!process.isSuccess || voucher == null) {
        return Err<LoyaltyVoucher>(
          ServerFailure(
            userMessage:
                'We could not redeem your points right now. '
                'Your balance has not changed.',
            developerMessage:
                'redeem returned ${process.status}: ${process.message}',
            statusCode: 200,
          ),
        );
      }
      return Ok<LoyaltyVoucher>(voucher.toDomain());
    }, Err<LoyaltyVoucher>.new);
  }

  Future<Result<String>> raiseSupportCase({
    required String subject,
    required String description,
    String? contactId,
    String? bookingReference,
    String? correlationId,
  }) {
    return _api.createCase(
      subject: subject,
      description: description,
      contactId: contactId,
      bookingReference: bookingReference,
      correlationId: correlationId,
    );
  }
}

/// Everything the loyalty screen needs, with per-section availability flags so
/// the UI can degrade rather than fail.
class LoyaltyMemberView {
  const LoyaltyMemberView({
    required this.member,
    this.ledger = const <PointsLedgerEntry>[],
    this.ledgerAvailable = true,
    this.vouchersAvailable = true,
  });

  final LoyaltyMember member;
  final List<PointsLedgerEntry> ledger;
  final bool ledgerAvailable;
  final bool vouchersAvailable;
}

class DeferredAccrual {
  const DeferredAccrual({
    required this.membershipNumber,
    required this.reservation,
    required this.eligibleSpend,
    required this.queuedAt,
    this.lastFailure,
  });

  final String membershipNumber;
  final Reservation reservation;
  final Money eligibleSpend;
  final DateTime queuedAt;
  final String? lastFailure;
}

class AccrualOutcome {
  const AccrualOutcome._({
    required this.isPosted,
    required this.points,
    this.newBalance,
    this.journalId,
  });

  factory AccrualOutcome.posted({
    required int points,
    int? newBalance,
    String? journalId,
  }) => AccrualOutcome._(
    isPosted: true,
    points: points,
    newBalance: newBalance,
    journalId: journalId,
  );

  /// Salesforce was unreachable. [points] is our local *estimate*, clearly
  /// labelled as such in the UI ("~4,500 points pending").
  factory AccrualOutcome.deferred({required int estimatedPoints}) =>
      AccrualOutcome._(isPosted: false, points: estimatedPoints);

  final bool isPosted;
  final int points;
  final int? newBalance;
  final String? journalId;
}

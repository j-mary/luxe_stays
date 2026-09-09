import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/error/failure.dart';
import '../../core/result.dart';
import '../../domain/loyalty.dart';
import '../../integrations/salesforce/salesforce_repository.dart';

/// Who is signed in, and what their loyalty standing is.
///
/// Held in one place because it changes the behaviour of nearly every other
/// screen: search asks SynXis for member rates, the cart offers points
/// redemption, checkout posts an accrual. Passing a nullable member down
/// through five widget constructors would be the alternative.
class SessionState {
  const SessionState({
    this.member,
    this.ledger = const <PointsLedgerEntry>[],
    this.isLoading = false,
    this.failure,
  });

  final LoyaltyMember? member;
  final List<PointsLedgerEntry> ledger;
  final bool isLoading;
  final Failure? failure;

  bool get isSignedIn => member != null;
  String? get membershipNumber => member?.membershipNumber;
  LoyaltyTier get tier => member?.tier ?? LoyaltyTier.classic;

  SessionState copyWith({
    LoyaltyMember? member,
    List<PointsLedgerEntry>? ledger,
    bool? isLoading,
    Failure? failure,
    bool clearFailure = false,
    bool signOut = false,
  }) {
    return SessionState(
      member: signOut ? null : (member ?? this.member),
      ledger: signOut ? const <PointsLedgerEntry>[] : (ledger ?? this.ledger),
      isLoading: isLoading ?? this.isLoading,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class SessionController extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState();

  /// Signs in by membership number.
  ///
  /// The POC stops short of a full OAuth round trip on this path - see
  /// `SalesforceAuthService` for the PKCE implementation and
  /// `docs/04-INTEGRATION-SALESFORCE.md` for how the two connect. What matters
  /// here is the shape: identity comes from Salesforce, and everything
  /// downstream keys off it.
  Future<void> signIn(String membershipNumber) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    final SalesforceRepository repository =
        ref.read(salesforceRepositoryProvider);
    final Result<LoyaltyMemberView> result =
        await repository.memberView(membershipNumber);

    state = result.fold<SessionState>(
      (LoyaltyMemberView view) => SessionState(
        member: view.member,
        ledger: view.ledger,
      ),
      (Failure failure) => state.copyWith(isLoading: false, failure: failure),
    );
  }

  Future<void> refresh() async {
    final String? number = state.membershipNumber;
    if (number == null) {
      return;
    }
    await signIn(number);
  }

  /// Applies a locally-known balance change without a round trip, so the UI
  /// reacts immediately after a redemption. The authoritative value replaces it
  /// on the next [refresh].
  void applyPointsDelta(int delta) {
    final LoyaltyMember? member = state.member;
    if (member == null) {
      return;
    }
    state = state.copyWith(
      member: member.copyWith(pointsBalance: member.pointsBalance + delta),
    );
  }

  void signOut() {
    state = state.copyWith(signOut: true, clearFailure: true);
  }
}

final NotifierProvider<SessionController, SessionState> sessionProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

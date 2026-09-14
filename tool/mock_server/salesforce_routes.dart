import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'fixtures.dart';
import 'support.dart';

/// Mock **Salesforce**: OAuth token endpoint, Loyalty Management Connect
/// resources, a SOQL endpoint for the points ledger, and Service Cloud cases.
///
/// Error bodies use Salesforce's own shape - a *list* of
/// `{errorCode, message}` - so `ErrorMapper.salesforce()` is exercised for real.
Router salesforceRouter() {
  final Router router = Router();

  // Mutable balances so a redemption visibly changes the member's points.
  final Map<String, int> balances = <String, int>{
    for (final MockMember m in mockMembers) m.membershipNumber: m.points,
  };
  final Map<String, List<Map<String, Object?>>> vouchers =
      <String, List<Map<String, Object?>>>{
        for (final MockMember m in mockMembers)
          m.membershipNumber: <Map<String, Object?>>[
            <String, Object?>{
              'voucherId': 'vch_${m.membershipNumber}_welcome',
              'voucherCode': 'WELCOME10',
              'voucherDefinitionName': 'Welcome reward',
              'type': 'Discount',
              'discountPercent': 10,
              'status': 'Issued',
              'expirationDate': DateTime.now()
                  .add(const Duration(days: 120))
                  .toIso8601String(),
              'currencyIsoCode': 'USD',
            },
          ],
      };
  final Map<String, List<Map<String, Object?>>> ledgers =
      <String, List<Map<String, Object?>>>{
        for (final MockMember m in mockMembers)
          m.memberId: <Map<String, Object?>>[
            <String, Object?>{
              'Id': 'led_${m.memberId}_1',
              'EventDate': DateTime.now()
                  .subtract(const Duration(days: 26))
                  .toIso8601String(),
              'Points': 7800,
              'Description': 'Stay at Maison Rivoli',
              'EventType': 'Accrual',
              'JournalReference': 'LXQ4TR9',
              'HotelName': 'Maison Rivoli',
            },
            <String, Object?>{
              'Id': 'led_${m.memberId}_2',
              'EventDate': DateTime.now()
                  .subtract(const Duration(days: 54))
                  .toIso8601String(),
              'Points': -5000,
              'Description': 'Redeemed for a suite upgrade',
              'EventType': 'Redemption',
            },
            <String, Object?>{
              'Id': 'led_${m.memberId}_3',
              'EventDate': DateTime.now()
                  .subtract(const Duration(days: 88))
                  .toIso8601String(),
              'Points': 2500,
              'Description': 'Tier bonus - ${m.tier}',
              'EventType': 'TierBonus',
            },
          ],
      };

  Map<String, Object?> memberBody(MockMember m) => <String, Object?>{
    'loyaltyProgramMemberId': m.memberId,
    'membershipNumber': m.membershipNumber,
    'firstName': m.firstName,
    'lastName': m.lastName,
    'contactId': m.contactId,
    'email': m.email,
    'mobilePhone': m.phone,
    'enrollmentDate': DateTime.now()
        .subtract(const Duration(days: 900))
        .toIso8601String(),
    'lifetimePoints': m.lifetime,
    'qualifyingNights': m.nights,
    'memberCurrencies': <Map<String, Object?>>[
      <String, Object?>{
        'loyaltyMemberCurrencyName': 'Reward Points',
        'pointsBalance': balances[m.membershipNumber] ?? m.points,
        'escrowPointsBalance': m.pending,
      },
    ],
    'memberTiers': <Map<String, Object?>>[
      <String, Object?>{
        'loyaltyMemberTierName': m.tier,
        'tierGroupName': 'LuxeStays Rewards Tiers',
      },
    ],
    'memberBenefits': <Map<String, Object?>>[
      <String, Object?>{'benefitName': 'Late check-out'},
      <String, Object?>{'benefitName': 'Room upgrade if available'},
      if (m.tier == 'Platinum')
        <String, Object?>{'benefitName': 'Airport transfer'},
    ],
  };

  // Salesforce returns errors as a JSON *array* of {errorCode, message}.
  Response notFound(String message) => jsonResponse(<Map<String, String>>[
    <String, String>{'errorCode': 'NOT_FOUND', 'message': message},
  ], status: 404);

  // --- OAuth ---------------------------------------------------------------
  router.post('/services/oauth2/token', (Request request) async {
    return jsonResponse(<String, Object?>{
      'access_token': 'mock_access_${DateTime.now().millisecondsSinceEpoch}',
      'refresh_token': 'mock_refresh_token',
      'instance_url': '${originOf(request)}/salesforce',
      'token_type': 'Bearer',
      'expires_in': 7200,
      'scope': 'api refresh_token openid',
    });
  });

  // --- Loyalty Management --------------------------------------------------
  router.get(
    '/services/data/<version>/connect/loyalty/programs/<program>/members',
    (Request request, String version, String program) {
      final String? number = request.url.queryParameters['membershipNumber'];
      final Iterable<MockMember> matches = mockMembers.where(
        (MockMember m) =>
            number == null ||
            m.membershipNumber.toUpperCase() == number.toUpperCase(),
      );
      if (matches.isEmpty) {
        return notFound('No member with membership number $number');
      }
      return jsonResponse(<String, Object?>{
        'members': matches.map(memberBody).toList(),
      });
    },
  );

  router.get(
    '/services/data/<version>/connect/loyalty/programs/<program>/members/<memberId>',
    (Request request, String version, String program, String memberId) {
      final Iterable<MockMember> matches = mockMembers.where(
        (MockMember m) => m.memberId == memberId,
      );
      if (matches.isEmpty) {
        return notFound('No member $memberId');
      }
      return jsonResponse(memberBody(matches.first));
    },
  );

  router.get(
    '/services/data/<version>/connect/loyalty/programs/<program>/members/<memberId>/vouchers',
    (Request request, String version, String program, String memberId) {
      final Iterable<MockMember> matches = mockMembers.where(
        (MockMember m) => m.memberId == memberId,
      );
      if (matches.isEmpty) {
        return notFound('No member $memberId');
      }
      return jsonResponse(<String, Object?>{
        'vouchers':
            vouchers[matches.first.membershipNumber] ??
            <Map<String, Object?>>[],
      });
    },
  );

  /// Loyalty program processes: accrual and redemption.
  router.post(
    '/services/data/<version>/connect/loyalty/programs/<program>/program-processes/<processName>',
    (
      Request request,
      String version,
      String program,
      String processName,
    ) async {
      final String? rawKey = request.headers['idempotency-key'];
      final String? key = rawKey == null
          ? null
          : 'loyalty:$processName:$rawKey';
      final Object? replay = idempotency.get(key);
      if (replay != null) {
        return jsonResponse(
          replay,
          headers: <String, String>{'x-idempotent-replay': '1'},
        );
      }

      final Map<String, Object?> body = await readJson(request);
      final List<Object?> params =
          (body['processParameters'] as List<Object?>?) ?? <Object?>[];
      final Map<String, Object?> input = params.isEmpty
          ? <String, Object?>{}
          : (params.first as Map<String, Object?>? ?? <String, Object?>{});
      final String membershipNumber =
          (input['MembershipNumber'] as String?) ?? '';
      if (!mockMembers.any(
        (MockMember m) => m.membershipNumber == membershipNumber,
      )) {
        return notFound('Unknown demo membership');
      }
      final MockMember member = mockMembers.firstWhere(
        (MockMember m) => m.membershipNumber == membershipNumber,
        orElse: () => mockMembers.first,
      );

      if (processName == 'AccrueStayPoints') {
        final double eligible =
            (input['EligibleAmount'] as num?)?.toDouble() ?? 0;
        if (eligible < 0 || !eligible.isFinite) {
          return mockError(
            422,
            'INVALID_AMOUNT',
            'Eligible spend must be non-negative.',
          );
        }
        final double multiplier = switch (member.tier) {
          'Platinum' => 2.0,
          'Gold' => 1.5,
          'Silver' => 1.25,
          _ => 1.0,
        };
        final int points = (eligible.floor() * 10 * multiplier).floor();
        balances[member.membershipNumber] =
            (balances[member.membershipNumber] ?? member.points) + points;
        ledgers[member.memberId]?.insert(0, <String, Object?>{
          'Id': 'led_${DateTime.now().millisecondsSinceEpoch}',
          'EventDate': DateTime.now().toIso8601String(),
          'Points': points,
          'Description': 'Stay at ${input['HotelName'] ?? 'a LuxeStays hotel'}',
          'EventType': 'Accrual',
          'JournalReference': input['BookingReference'],
          'HotelName': input['HotelName'],
        });
        final Map<String, Object?> payload = <String, Object?>{
          'status': 'Success',
          'outputParameters': <String, Object?>{
            'transactionJournalId':
                'a0X${DateTime.now().millisecondsSinceEpoch}',
            'points': points,
            'newBalance': balances[member.membershipNumber],
            'message': 'Accrual posted',
          },
        };
        idempotency.put(key, payload);
        return jsonResponse(payload);
      }

      if (processName == 'RedeemPointsForVoucher') {
        final int points = (input['Points'] as num?)?.toInt() ?? 0;
        final int balance = balances[member.membershipNumber] ?? member.points;
        if (points <= 0 || points > balance) {
          return jsonResponse(<Map<String, String>>[
            <String, String>{
              'errorCode': 'INSUFFICIENT_POINTS',
              'message': 'Member has $balance points, requested $points',
            },
          ], status: 400);
        }
        balances[member.membershipNumber] = balance - points;
        final Map<String, Object?> voucher = <String, Object?>{
          'voucherId': 'vch_${DateTime.now().millisecondsSinceEpoch}',
          'voucherCode': reference('RW'),
          'voucherDefinitionName': 'Points reward',
          'type': 'Value',
          'faceValue': points / 100,
          'currencyIsoCode': (input['CurrencyIsoCode'] as String?) ?? 'USD',
          'status': 'Issued',
          'expirationDate': DateTime.now()
              .add(const Duration(days: 365))
              .toIso8601String(),
        };
        vouchers[member.membershipNumber]?.add(voucher);
        ledgers[member.memberId]?.insert(0, <String, Object?>{
          'Id': 'led_${DateTime.now().millisecondsSinceEpoch}',
          'EventDate': DateTime.now().toIso8601String(),
          'Points': -points,
          'Description': 'Redeemed for a reward voucher',
          'EventType': 'Redemption',
        });
        final Map<String, Object?> payload = <String, Object?>{
          'status': 'Success',
          'outputParameters': <String, Object?>{
            'transactionJournalId':
                'a0X${DateTime.now().millisecondsSinceEpoch}',
            'points': -points,
            'newBalance': balances[member.membershipNumber],
            'voucher': voucher,
          },
        };
        idempotency.put(key, payload);
        return jsonResponse(payload);
      }

      return jsonResponse(<Map<String, String>>[
        <String, String>{
          'errorCode': 'PROCESS_NOT_FOUND',
          'message': 'Unknown program process $processName',
        },
      ], status: 404);
    },
  );

  router.post(
    '/services/data/<version>/connect/loyalty/programs/<program>/individual-member-enrollments',
    (Request request, String version, String program) async {
      final Map<String, Object?> body = await readJson(request);
      final Map<String, Object?> contact =
          (body['associatedContactDetails'] as Map<String, Object?>?) ??
          <String, Object?>{};
      return jsonResponse(<String, Object?>{
        'loyaltyProgramMemberId':
            '0lM5j${DateTime.now().millisecondsSinceEpoch}',
        'membershipNumber': reference('LS-'),
        'firstName': contact['firstName'],
        'lastName': contact['lastName'],
        'memberCurrencies': <Map<String, Object?>>[
          <String, Object?>{
            'loyaltyMemberCurrencyName': 'Reward Points',
            'pointsBalance': 0,
            'escrowPointsBalance': 0,
          },
        ],
        'memberTiers': <Map<String, Object?>>[
          <String, Object?>{'loyaltyMemberTierName': 'Classic'},
        ],
      }, status: 201);
    },
  );

  // --- SOQL (points ledger) ------------------------------------------------
  router.get('/services/data/<version>/query', (
    Request request,
    String version,
  ) {
    final String soql = request.url.queryParameters['q'] ?? '';
    final RegExpMatch? match = RegExp(r"LoyaltyProgramMemberId\s*=\s*'([^']+)'")
        .firstMatch(soql);
    final String memberId = match?.group(1) ?? '';
    final List<Map<String, Object?>> records =
        ledgers[memberId] ?? <Map<String, Object?>>[];
    return jsonResponse(<String, Object?>{
      'totalSize': records.length,
      'done': true,
      'records': records,
    });
  });

  // --- Service Cloud -------------------------------------------------------
  router.post('/services/data/<version>/sobjects/Case', (
    Request request,
    String version,
  ) async {
    final Map<String, Object?> body = await readJson(request);
    return jsonResponse(<String, Object?>{
      'id': '500${DateTime.now().millisecondsSinceEpoch}',
      'success': true,
      'errors': <Object?>[],
      'echo': body['Subject'],
    }, status: 201);
  });

  return router;
}

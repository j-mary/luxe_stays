import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/router.dart';
import '../../core/utils/date_x.dart';
import '../../domain/loyalty.dart';
import '../../shared/widgets/app_states.dart';
import '../account/session_controller.dart';

/// LuxeStays Rewards.
///
/// Every number on this screen originates in Salesforce Loyalty Management.
/// The only thing computed on the device is the *preview* of what a stay would
/// earn - and it is labelled as an estimate wherever it appears.
class LoyaltyScreen extends ConsumerWidget {
  const LoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SessionState session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LuxeStays Rewards'),
        actions: <Widget>[
          if (session.isSignedIn)
            IconButton(
              tooltip: 'Sign out',
              onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              icon: const Icon(Icons.logout_rounded),
            ),
        ],
      ),
      body: session.isSignedIn
          ? _MemberView(session: session)
          : const _SignInView(),
    );
  }
}

class _SignInView extends ConsumerStatefulWidget {
  const _SignInView();

  @override
  ConsumerState<_SignInView> createState() => _SignInViewState();
}

class _SignInViewState extends ConsumerState<_SignInView> {
  final TextEditingController _controller =
      TextEditingController(text: 'LS-100042');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SessionState session = ref.watch(sessionProvider);
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 24),
        Icon(Icons.workspace_premium_rounded,
            size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'Members stay for less',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Lower rates at every property, points on every stay, and benefits '
          'that grow with your tier.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Membership number',
            border: OutlineInputBorder(),
            helperText: 'Try LS-100042 (Gold) or LS-100077 (Platinum)',
          ),
        ),
        const SizedBox(height: 12),
        if (session.failure != null)
          Text(
            session.failure!.userMessage,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: session.isLoading
              ? null
              : () => ref
                  .read(sessionProvider.notifier)
                  .signIn(_controller.text.trim()),
          child: session.isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Sign in'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.of(context).pushNamed(
            Routes.cmsPage,
            arguments: const CmsPageArgs(
              slug: 'rewards-terms',
              title: 'Programme terms',
            ),
          ),
          child: const Text('Programme terms'),
        ),
      ],
    );
  }
}

class _MemberView extends ConsumerWidget {
  const _MemberView({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LoyaltyMember member = session.member!;
    final LoyaltyProgramRules rules = ref.watch(loyaltyRulesProvider);
    final ThemeData theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => ref.read(sessionProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _TierCard(member: member, rules: rules),
          const SizedBox(height: 16),
          if (member.usableVouchers.isNotEmpty) ...<Widget>[
            Text('Your rewards', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...member.usableVouchers.map(
              (LoyaltyVoucher voucher) => Card(
                child: ListTile(
                  leading: const Icon(Icons.confirmation_number_outlined),
                  title: Text(voucher.name),
                  subtitle: Text(
                    '${voucher.valueLabel} · expires '
                    '${formatShortDate(voucher.expiresAt)}',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: <Widget>[
              Text('Points activity', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (session.ledger.isEmpty)
                Text('No activity yet', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          ...session.ledger.map(
            (PointsLedgerEntry entry) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: entry.isAccrual
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: Icon(
                  entry.isAccrual ? Icons.add_rounded : Icons.remove_rounded,
                  size: 18,
                ),
              ),
              title: Text(entry.description),
              subtitle: Text(
                <String>[
                  formatShortDate(entry.occurredAt),
                  if (entry.hotelName != null) entry.hotelName!,
                  if (entry.bookingReference != null) entry.bookingReference!,
                ].join(' · '),
                style: theme.textTheme.labelSmall,
              ),
              trailing: Text(
                '${entry.isAccrual ? '+' : ''}${entry.points}',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: entry.isAccrual
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          if (session.ledger.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: EmptyView(
                title: 'No points activity',
                message: 'Your accruals and redemptions will appear here.',
                icon: Icons.history_rounded,
              ),
            ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.member, required this.rules});

  final LoyaltyMember member;
  final LoyaltyProgramRules rules;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? toNext = member.nightsToNextTier;

    return Card(
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              member.displayName,
              style: theme.textTheme.titleLarge
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            Text(
              '${member.tier.label} · ${member.membershipNumber}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  '${member.pointsBalance}',
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'points',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                ),
              ],
            ),
            Text(
              'Worth about '
              '${rules.pointsToMoney(member.pointsBalance, 'USD').format()}'
              '${member.pendingPoints > 0 ? ' · ${member.pendingPoints} pending' : ''}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
            if (toNext != null && member.tier.next != null) ...<Widget>[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: member.progressToNextTier,
                backgroundColor:
                    theme.colorScheme.onPrimaryContainer.withAlpha(40),
              ),
              const SizedBox(height: 8),
              Text(
                toNext == 0
                    ? '${member.tier.next!.label} unlocked on your next stay'
                    : '$toNext more night${toNext == 1 ? '' : 's'} to '
                        '${member.tier.next!.label}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
            ],
            if (member.benefits.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: member.benefits
                    .map(
                      (String benefit) => Chip(
                        label: Text(benefit),
                        visualDensity: VisualDensity.compact,
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

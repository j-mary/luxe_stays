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

/// The membership panel — the one place the app is allowed to be emphatic.
///
/// Rendered as a dark plate with brass accents rather than a tinted container,
/// because tier status is the single moment in the product where a visual
/// flourish is earned. Everywhere else the accent is spent on actions only.
class _TierCard extends StatelessWidget {
  const _TierCard({required this.member, required this.rules});

  final LoyaltyMember member;
  final LoyaltyProgramRules rules;

  static const Color _brass = Color(0xFFC9A876);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isLight = theme.brightness == Brightness.light;
    final Color panel = isLight ? const Color(0xFF14201B) : const Color(0xFF20241F);
    const Color onPanel = Color(0xFFF4F3EF);
    final Color onPanelMuted = onPanel.withAlpha(150);
    final int? toNext = member.nightsToNextTier;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.workspace_premium_outlined,
                  size: 14, color: _brass),
              const SizedBox(width: 7),
              Text(
                '${member.tier.label.toUpperCase()} MEMBER',
                style: theme.textTheme.labelSmall?.copyWith(color: _brass),
              ),
              const Spacer(),
              Text(
                member.membershipNumber,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: onPanelMuted,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            member.displayName,
            style: theme.textTheme.headlineSmall?.copyWith(color: onPanel),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                _grouped(member.pointsBalance),
                style: theme.textTheme.displaySmall?.copyWith(color: onPanel),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  'POINTS',
                  style: theme.textTheme.labelSmall?.copyWith(color: _brass),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Worth about '
            '${rules.pointsToMoney(member.pointsBalance, 'USD').format()}'
            '${member.pendingPoints > 0 ? ' · ${_grouped(member.pendingPoints)} pending' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: onPanelMuted),
          ),
          if (toNext != null && member.tier.next != null) ...<Widget>[
            const SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: member.progressToNextTier,
                minHeight: 3,
                backgroundColor: onPanel.withAlpha(38),
                valueColor: const AlwaysStoppedAnimation<Color>(_brass),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              toNext == 0
                  ? '${member.tier.next!.label} unlocked on your next stay'
                  : '$toNext more night${toNext == 1 ? '' : 's'} to '
                      '${member.tier.next!.label}',
              style: theme.textTheme.bodySmall?.copyWith(color: onPanelMuted),
            ),
          ],
          if (member.benefits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: member.benefits
                  .map(
                    (String benefit) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: onPanel.withAlpha(46)),
                      ),
                      child: Text(
                        benefit,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: onPanel, fontSize: 12),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }

  /// Thousands separators, because a six-figure balance is the whole point of
  /// the panel and "132900" does not read as an achievement.
  static String _grouped(int value) {
    final String digits = value.abs().toString();
    final StringBuffer out = StringBuffer(value < 0 ? '-' : '');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) {
        out.write(',');
      }
      out.write(digits[i]);
    }
    return out.toString();
  }
}

/// Turns a failure into something a person can act on.
///
/// The taxonomy in [PuterErrorKind] is for the program; this is for the human
/// holding the phone. Two rules shape every string here.
///
/// **No internals.** The previous copy named the transport protocol, printed
/// HTTP status codes, blamed "client-side" and echoed raw server messages.
/// A user cannot act on any of that, and it makes a normal condition look like
/// a defect.
///
/// **Retry is offered only when retrying could work.** Three kinds are
/// permanent — a full account, exhausted credit, a revoked key — and offering
/// Retry for them teaches the user that the app is broken rather than that
/// their account needs attention. The worst case is `authInvalid`: a retry loop
/// on authentication walks into the ten-failures-in-fifteen-minutes lockout.
library;

import 'package:flutter/material.dart';

import 'puter_exception.dart';

/// Copy and affordances for one failure.
class ErrorPresentation {
  const ErrorPresentation({
    required this.title,
    required this.message,
    required this.icon,
    this.canRetry = false,
    this.actionLabel,
    this.actionUrl,
  });

  final String title;
  final String message;
  final IconData icon;

  /// Whether offering Retry is honest for this failure.
  final bool canRetry;

  /// Optional label for an outbound action.
  final String? actionLabel;

  /// Where that action leads.
  final String? actionUrl;

  /// A one-line form, for inline banners where only a sentence fits.
  String get shortMessage => message;
}

/// Maps errors to [ErrorPresentation].
abstract final class ErrorPresenter {
  static ErrorPresentation describe(Object error) {
    if (error is! PuterException) {
      return const ErrorPresentation(
        title: 'Something went wrong',
        message: 'That did not work. Try again in a moment.',
        icon: Icons.error_outline_rounded,
        canRetry: true,
      );
    }

    return switch (error.kind) {
      PuterErrorKind.authInvalid => const ErrorPresentation(
          title: 'Access key no longer works',
          message: 'Puter did not accept the saved key. It may have been '
              'revoked from your account page. Add a new one to continue.',
          icon: Icons.key_off_rounded,
        ),
      PuterErrorKind.permissionDenied => ErrorPresentation(
          title: 'Not allowed',
          message: 'Your Puter account does not allow changes to '
              '“${error.path ?? 'this item'}”.',
          icon: Icons.block_rounded,
        ),
      PuterErrorKind.notFound => ErrorPresentation(
          title: 'That item has gone',
          message: '“${error.path ?? 'It'}” is no longer in your Puter account. '
              'It may have been moved or deleted somewhere else.',
          icon: Icons.search_off_rounded,
        ),
      PuterErrorKind.alreadyExists => ErrorPresentation(
          title: 'That name is taken',
          message: 'There is already something called '
              '“${error.path ?? 'that'}” in this folder.',
          icon: Icons.content_copy_rounded,
        ),
      PuterErrorKind.rateLimited => const ErrorPresentation(
          title: 'Puter is busy',
          message: 'Too many requests are in flight right now. The app is '
              'pausing briefly and will pick up where it left off.',
          icon: Icons.hourglass_bottom_rounded,
          canRetry: true,
        ),
      PuterErrorKind.insufficientFunds => const ErrorPresentation(
          title: 'Monthly allowance used up',
          message: 'This Puter account has used its allowance for the month. '
              'Saving is paused until it resets or the plan changes. You can '
              'still browse your files.',
          icon: Icons.account_balance_wallet_outlined,
          actionLabel: 'Open Puter',
        ),
      PuterErrorKind.subscriptionRequired => const ErrorPresentation(
          title: 'Needs a paid Puter plan',
          message: 'Puter only offers this on a paid plan. Nothing is wrong '
              'with your account — this one feature is not available.',
          icon: Icons.workspace_premium_outlined,
          actionLabel: 'See plans',
        ),
      PuterErrorKind.storageLimitReached => const ErrorPresentation(
          title: 'Your Puter storage is full',
          message: 'There is no room left to save anything new. Delete '
              'something in the Puter app or on the website, then try again.',
          icon: Icons.sd_card_alert_outlined,
        ),
      PuterErrorKind.network => const ErrorPresentation(
          title: 'No connection',
          message: 'Puter could not be reached. Check your internet — folders '
              'you have already opened are still available.',
          icon: Icons.wifi_off_rounded,
          canRetry: true,
        ),
      PuterErrorKind.protocol => const ErrorPresentation(
          title: 'Unexpected response',
          message: 'Puter sent something this app did not understand. Trying '
              'again often clears it.',
          icon: Icons.help_outline_rounded,
          canRetry: true,
        ),
      PuterErrorKind.badRequest => ErrorPresentation(
          title: 'That did not work',
          message: error.message,
          icon: Icons.report_gmailerrorred_outlined,
        ),
      PuterErrorKind.partialFailure => ErrorPresentation(
          title: 'Some items could not load',
          message: error.failedItems.isEmpty
              ? 'Part of this folder could not be read.'
              : '${error.failedItems.length} of the items here could not be '
                  'read. Pull down to try again.',
          icon: Icons.warning_amber_rounded,
          canRetry: true,
        ),
      PuterErrorKind.unsupported => const ErrorPresentation(
          title: 'Not available here',
          message: 'Puter does not offer this in the browser view of your '
              'account. It may be possible on the Puter website.',
          icon: Icons.do_not_disturb_alt_outlined,
        ),
      PuterErrorKind.unknown => const ErrorPresentation(
          title: 'Something went wrong',
          message: 'That did not work. Try again in a moment.',
          icon: Icons.error_outline_rounded,
          canRetry: true,
        ),
    };
  }

  /// A compact label for a failed transfer, where a full card is too much.
  static String transferLabel(Object error) {
    if (error is! PuterException) return 'Did not finish';
    return switch (error.kind) {
      PuterErrorKind.storageLimitReached => 'Storage full',
      PuterErrorKind.insufficientFunds => 'Monthly allowance used up',
      PuterErrorKind.subscriptionRequired => 'Needs a paid plan',
      PuterErrorKind.authInvalid => 'Access key rejected',
      PuterErrorKind.network => 'Connection lost',
      PuterErrorKind.rateLimited => 'Puter was busy',
      PuterErrorKind.notFound => 'Missing from Puter',
      PuterErrorKind.permissionDenied => 'Not allowed',
      PuterErrorKind.alreadyExists => 'Name already used',
      _ => 'Did not finish',
    };
  }
}

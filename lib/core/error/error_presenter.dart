/// Turns a failure into something a user can act on.
///
/// The taxonomy in [PuterErrorKind] is for the program; this is for the person
/// holding the phone. The distinction matters because three of those kinds are
/// permanent — retrying a `413`, a `402` or a revoked token changes nothing —
/// and offering a Retry button for them teaches the user that the app is
/// broken rather than that their account needs attention.
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

  /// Optional label for an outbound action, e.g. "Open Puter dashboard".
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
        message: 'The operation could not be completed. Try again.',
        icon: Icons.error_outline,
        canRetry: true,
      );
    }

    return switch (error.kind) {
      PuterErrorKind.authInvalid => const ErrorPresentation(
          title: 'Sign-in expired',
          message: 'Puter rejected the stored token. Sign in again with a new '
              'token to continue.',
          icon: Icons.lock_outline,
        ),
      PuterErrorKind.permissionDenied => ErrorPresentation(
          title: 'Not permitted',
          message: 'Your Puter account does not allow this operation on '
              '“${error.path ?? 'this item'}”.',
          icon: Icons.block_outlined,
        ),
      PuterErrorKind.notFound => ErrorPresentation(
          title: 'No longer there',
          message: '“${error.path ?? 'That item'}” does not exist. It may have '
              'been moved or deleted, here or in the Puter web app.',
          icon: Icons.search_off,
        ),
      PuterErrorKind.alreadyExists => ErrorPresentation(
          title: 'Already exists',
          message: '“${error.path ?? 'That name'}” is already taken in this '
              'folder. Choose a different name.',
          icon: Icons.content_copy_outlined,
        ),
      PuterErrorKind.rateLimited => const ErrorPresentation(
          title: 'Too many requests',
          message: 'Puter is throttling this account. The app will slow down '
              'and try again in a moment.',
          icon: Icons.hourglass_empty,
          canRetry: true,
        ),
      PuterErrorKind.insufficientFunds => const ErrorPresentation(
          title: 'Usage credit exhausted',
          message: 'This Puter account has used its monthly allowance. '
              'Uploads and changes are paused until it resets or the plan '
              'is upgraded. Browsing still works.',
          icon: Icons.account_balance_wallet_outlined,
          actionLabel: 'Open Puter dashboard',
        ),
      PuterErrorKind.subscriptionRequired => const ErrorPresentation(
          title: 'Paid plan required',
          message: 'Puter restricts this feature to paid plans. Nothing in '
              'your account is wrong — the operation is simply not available.',
          icon: Icons.workspace_premium_outlined,
          actionLabel: 'See plans',
        ),
      PuterErrorKind.storageLimitReached => const ErrorPresentation(
          title: 'Storage full',
          message: 'Your Puter account is out of space, so nothing new can be '
              'written. Free space in the Puter web app, then try again.',
          icon: Icons.sd_card_alert_outlined,
        ),
      PuterErrorKind.network => const ErrorPresentation(
          title: 'No connection',
          message: 'Puter could not be reached. Check your connection — '
              'folders you have already opened are still browsable.',
          icon: Icons.wifi_off_outlined,
          canRetry: true,
        ),
      PuterErrorKind.protocol => ErrorPresentation(
          title: 'Unexpected reply',
          message: 'Puter sent a response this app could not read. This is a '
              'client-side problem. ${error.message}',
          icon: Icons.help_outline,
          canRetry: true,
        ),
      PuterErrorKind.badRequest => ErrorPresentation(
          title: 'Request rejected',
          message: error.message,
          icon: Icons.report_gmailerrorred_outlined,
        ),
      PuterErrorKind.partialFailure => ErrorPresentation(
          title: 'Partly completed',
          message: error.failedItems.isEmpty
              ? error.message
              : '${error.failedItems.length} item(s) could not be read: '
                  '${error.failedItems.map((f) => f.path).take(3).join(', ')}',
          icon: Icons.warning_amber_outlined,
          canRetry: true,
        ),
      PuterErrorKind.unsupported => const ErrorPresentation(
          title: 'Not supported',
          message: 'Puter does not offer this over WebDAV. It may be available '
              'in the Puter web app.',
          icon: Icons.do_not_disturb_alt_outlined,
        ),
      PuterErrorKind.unknown => ErrorPresentation(
          title: 'Something went wrong',
          message: error.message,
          icon: Icons.error_outline,
          canRetry: true,
        ),
    };
  }

  /// A compact label for a failed transfer, where a full card is too much.
  static String transferLabel(Object error) {
    if (error is! PuterException) return 'Failed';
    return switch (error.kind) {
      PuterErrorKind.storageLimitReached => 'Storage full',
      PuterErrorKind.insufficientFunds => 'Usage credit exhausted',
      PuterErrorKind.subscriptionRequired => 'Paid plan required',
      PuterErrorKind.authInvalid => 'Sign-in expired',
      PuterErrorKind.network => 'Connection lost',
      PuterErrorKind.rateLimited => 'Rate limited',
      PuterErrorKind.notFound => 'Missing on server',
      PuterErrorKind.permissionDenied => 'Not permitted',
      _ => 'Failed',
    };
  }
}

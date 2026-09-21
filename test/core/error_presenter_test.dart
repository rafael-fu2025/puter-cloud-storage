/// Tests for the error taxonomy and the copy built from it.
///
/// The retry affordance is the part worth testing. Three of the error kinds are
/// permanent — a full quota, exhausted usage credit, a revoked token — and
/// offering Retry for them teaches the user that the app is broken rather than
/// that their account needs attention. The worst case is `authInvalid`: a retry
/// loop on authentication walks into WebDAV's ten-failures-in-fifteen-minutes
/// lockout and locks the account out of its own storage.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:puter_cloud_storage/core/error/error_presenter.dart';
import 'package:puter_cloud_storage/core/error/puter_exception.dart';

void main() {
  group('PuterException', () {
    test('only transient kinds are retryable', () {
      expect(
        const PuterException(PuterErrorKind.network, 'x').isRetryable,
        isTrue,
      );
      expect(
        const PuterException(PuterErrorKind.rateLimited, 'x').isRetryable,
        isTrue,
      );
      expect(
        const PuterException(PuterErrorKind.unknown, 'x').isRetryable,
        isTrue,
      );

      // Permanent, and retrying each one spends request budget for nothing.
      for (final PuterErrorKind kind in <PuterErrorKind>[
        PuterErrorKind.authInvalid,
        PuterErrorKind.storageLimitReached,
        PuterErrorKind.insufficientFunds,
        PuterErrorKind.subscriptionRequired,
        PuterErrorKind.notFound,
        PuterErrorKind.alreadyExists,
        PuterErrorKind.permissionDenied,
        PuterErrorKind.badRequest,
        PuterErrorKind.unsupported,
      ]) {
        expect(
          PuterException(kind, 'x').isRetryable,
          isFalse,
          reason: '${kind.name} must never be retried automatically',
        );
      }
    });

    test('authInvalid is not retryable, by deliberate exclusion', () {
      // The single most important classification in the app: retrying a 401 can
      // trip the server's failed-sign-in lockout.
      expect(
        const PuterException(PuterErrorKind.authInvalid, 'x').isRetryable,
        isFalse,
      );
    });

    test('kinds needing the user to act are identified', () {
      for (final PuterErrorKind kind in <PuterErrorKind>[
        PuterErrorKind.insufficientFunds,
        PuterErrorKind.subscriptionRequired,
        PuterErrorKind.storageLimitReached,
        PuterErrorKind.authInvalid,
      ]) {
        expect(PuterException(kind, 'x').requiresUserAction, isTrue);
      }
      expect(
        const PuterException(PuterErrorKind.network, 'x').requiresUserAction,
        isFalse,
      );
    });

    test('toString carries no credential material by construction', () {
      // TokenCredential redacts itself; this asserts the exception does not
      // reintroduce a leak through its message or path.
      const PuterException error = PuterException(
        PuterErrorKind.authInvalid,
        'Token rejected.',
        statusCode: 401,
        path: '/Documents',
      );
      expect(error.toString(), contains('authInvalid'));
      expect(error.toString(), contains('/Documents'));
    });
  });

  group('ErrorMapper', () {
    test('classifies the statuses that matter', () {
      expect(ErrorMapper.fromHttpStatus(401), PuterErrorKind.authInvalid);
      expect(ErrorMapper.fromHttpStatus(403), PuterErrorKind.permissionDenied);
      expect(ErrorMapper.fromHttpStatus(404), PuterErrorKind.notFound);
      expect(ErrorMapper.fromHttpStatus(409), PuterErrorKind.alreadyExists);
      expect(ErrorMapper.fromHttpStatus(412), PuterErrorKind.unknown);
      expect(ErrorMapper.fromHttpStatus(413),
          PuterErrorKind.storageLimitReached);
      expect(ErrorMapper.fromHttpStatus(402),
          PuterErrorKind.insufficientFunds);
      expect(ErrorMapper.fromHttpStatus(429), PuterErrorKind.rateLimited);
      expect(ErrorMapper.fromHttpStatus(500), PuterErrorKind.network);
    });

    test('a server code outranks the status alone', () {
      // 402 covers both "out of credit" and "paid plan required", and the
      // distinction decides what the user is told to do about it.
      expect(
        ErrorMapper.fromHttpStatus(402, code: 'subscription_required'),
        PuterErrorKind.subscriptionRequired,
      );
      expect(
        ErrorMapper.fromHttpStatus(402, code: 'insufficient_funds'),
        PuterErrorKind.insufficientFunds,
      );
      expect(
        ErrorMapper.fromHttpStatus(429, code: 'storage_limit_reached'),
        PuterErrorKind.storageLimitReached,
      );
    });
  });

  group('ErrorPresenter', () {
    test('every kind produces copy with a title and a body', () {
      for (final PuterErrorKind kind in PuterErrorKind.values) {
        final ErrorPresentation presentation =
            ErrorPresenter.describe(PuterException(kind, 'detail'));
        expect(presentation.title, isNotEmpty, reason: kind.name);
        expect(presentation.message, isNotEmpty, reason: kind.name);
        expect(presentation.icon, isNotNull, reason: kind.name);
      }
    });

    test('offers Retry only when a retry could work', () {
      expect(
        ErrorPresenter.describe(
          const PuterException(PuterErrorKind.network, 'x'),
        ).canRetry,
        isTrue,
      );
      // None of these get a Retry button, because none of them can be fixed by
      // pressing it.
      for (final PuterErrorKind kind in <PuterErrorKind>[
        PuterErrorKind.storageLimitReached,
        PuterErrorKind.insufficientFunds,
        PuterErrorKind.subscriptionRequired,
        PuterErrorKind.authInvalid,
      ]) {
        expect(
          ErrorPresenter.describe(PuterException(kind, 'x')).canRetry,
          isFalse,
          reason: '${kind.name} must not offer Retry',
        );
      }
    });

    test('a full quota says what to do, not merely that it failed', () {
      final ErrorPresentation presentation = ErrorPresenter.describe(
        const PuterException(PuterErrorKind.storageLimitReached, 'x'),
      );
      // The user has to be told the way out, not just the symptom.
      final String copy =
          '${presentation.title} ${presentation.message}'.toLowerCase();
      expect(copy, contains('storage'));
      expect(copy, contains('delete'));
      expect(
        presentation.canRetry,
        isFalse,
        reason: 'no amount of retrying frees space',
      );
    });

    test('no user-facing copy leaks the transport protocol', () {
      // "WebDAV" is an implementation detail. A user cannot act on it, and
      // seeing it makes a normal condition look like a defect.
      for (final PuterErrorKind kind in PuterErrorKind.values) {
        final ErrorPresentation presentation =
            ErrorPresenter.describe(PuterException(kind, 'detail'));
        final String copy =
            '${presentation.title} ${presentation.message}'.toLowerCase();
        expect(copy, isNot(contains('webdav')), reason: kind.name);
        expect(copy, isNot(contains('token')), reason: kind.name);
        expect(copy, isNot(contains('http')), reason: kind.name);
        expect(copy, isNot(contains('transport')), reason: kind.name);
      }
    });

    test('names the path in a not-found message', () {
      final ErrorPresentation presentation = ErrorPresenter.describe(
        const PuterException(
          PuterErrorKind.notFound,
          'gone',
          path: '/Documents/report.pdf',
        ),
      );
      expect(presentation.message, contains('/Documents/report.pdf'));
    });

    test('an unknown failure still produces something actionable', () {
      final ErrorPresentation presentation =
          ErrorPresenter.describe(StateError('boom'));
      expect(presentation.title, isNotEmpty);
      expect(presentation.canRetry, isTrue);
    });

    test('transfer labels stay short enough for a list row', () {
      for (final PuterErrorKind kind in PuterErrorKind.values) {
        final String label =
            ErrorPresenter.transferLabel(PuterException(kind, 'x'));
        expect(label.length, lessThan(30), reason: kind.name);
      }
    });
  });
}

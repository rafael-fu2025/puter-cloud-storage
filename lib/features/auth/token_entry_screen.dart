/// Token entry — the one screen that spends failed-sign-in budget.
///
/// Everything here is shaped by a single fact from `docs/puter-api-research.md`
/// §5: WebDAV returns `429` after **ten failed sign-ins in fifteen minutes**,
/// and it does so *even for a correct token*. A retry loop therefore does not
/// merely fail — it locks the user out of their own storage.
///
/// So this screen submits **exactly once per tap**: no auto-retry, no
/// debounce-and-resubmit, no background revalidation. On success it returns to
/// the gate; on failure it shows what happened and hands control back to the
/// user.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../core/config/app_config.dart';
import '../../core/error/error_presenter.dart';

class TokenEntryScreen extends ConsumerStatefulWidget {
  const TokenEntryScreen({super.key});

  @override
  ConsumerState<TokenEntryScreen> createState() => _TokenEntryScreenState();
}

class _TokenEntryScreenState extends ConsumerState<TokenEntryScreen> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isValidating = false;
  bool _obscured = true;
  ErrorPresentation? _failure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    setState(() => _failure = null);
  }

  Future<void> _submit() async {
    if (_isValidating) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Trimmed because a copied token routinely arrives with a trailing newline,
    // and a credential that fails for an invisible reason is the worst possible
    // first experience.
    final token = _controller.text.trim();

    setState(() {
      _isValidating = true;
      _failure = null;
    });

    await ref.read(sessionProvider.notifier).signIn(token);
    if (!mounted) return;

    final SessionState? state = ref.read(sessionProvider).valueOrNull;
    setState(() => _isValidating = false);

    switch (state?.status) {
      case SessionStatus.ready:
        // The gate beneath this route now renders the app, so there is nothing
        // left for this screen to do.
        unawaited(Navigator.of(context).maybePop());
      case SessionStatus.failed:
        final error = state?.error;
        if (error != null) {
          setState(() => _failure = ErrorPresenter.describe(error));
        }
      case _:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Enter token')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              'Paste your Puter auth token',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Create it at puter.com/dashboard#account, in the API token '
              'section. It is copied to your clipboard when you tap Create '
              'token.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _controller,
              enabled: !_isValidating,
              obscureText: _obscured,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_failure != null) setState(() => _failure = null);
              },
              decoration: InputDecoration(
                labelText: 'Auth token',
                hintText: 'Paste your token here',
                border: const OutlineInputBorder(),
                errorMaxLines: 3,
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(
                      icon: Icon(
                        _obscured ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscured = !_obscured),
                      tooltip: _obscured ? 'Show token' : 'Hide token',
                    ),
                    IconButton(
                      icon: const Icon(Icons.content_paste),
                      onPressed: _isValidating ? null : _pasteFromClipboard,
                      tooltip: 'Paste from clipboard',
                    ),
                  ],
                ),
              ),
              validator: (String? value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Enter the token from your dashboard.';
                if (text.length < 10) {
                  return 'That looks too short to be a Puter token.';
                }
                return null;
              },
            ),
            if (_failure != null) ...<Widget>[
              const SizedBox(height: 16),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(
                        _failure!.icon,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _failure!.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _failure!.message,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isValidating ? null : _submit,
              child: _isValidating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
            const SizedBox(height: 20),
            const _LockoutNotice(),
          ],
        ),
      ),
    );
  }
}

/// Explains the one strike the app must never earn.
class _LockoutNotice extends StatelessWidget {
  const _LockoutNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                // Expanded so a large font scale wraps the heading rather than
                // overflowing the card.
                Expanded(
                  child: Text(
                    'One attempt per tap',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Puter locks WebDAV access for 15 minutes after ten failed '
              'sign-ins, and returns an error even for a correct token during '
              'that window. So this screen tries once and never retries on its '
              'own. If a token fails, check it on the dashboard first.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SelectableText(
              PuterEndpoints.dashboardAccount,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

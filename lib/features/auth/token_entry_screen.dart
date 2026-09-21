/// Connecting the account.
///
/// Everything here is shaped by one fact from `docs/puter-api-research.md` §5:
/// Puter returns `429` after **ten failed sign-ins in fifteen minutes**, and it
/// does so *even for a correct key*. A retry loop therefore does not merely
/// fail — it locks the user out of their own storage.
///
/// So the screen submits **exactly once per tap**: no auto-retry, no
/// debounce-and-resubmit, no background revalidation. The previous version
/// explained all of that to the user, in a card, in developer terms
/// ("WebDAV", "failed sign-ins", "window"). The rule is still enforced; the
/// user now gets one sentence telling them how to avoid hitting it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/session.dart';
import '../../core/config/app_config.dart';
import '../../core/error/error_presenter.dart';
import '../../core/ui/components.dart';
import '../../core/ui/design.dart';
import '../../data/platform/platform_bridge.dart';

class TokenEntryScreen extends ConsumerStatefulWidget {
  const TokenEntryScreen({super.key});

  @override
  ConsumerState<TokenEntryScreen> createState() => _TokenEntryScreenState();
}

class _TokenEntryScreenState extends ConsumerState<TokenEntryScreen> {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isConnecting = false;
  bool _obscured = true;
  ErrorPresentation? _failure;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    _controller.text = text;
    setState(() => _failure = null);
  }

  Future<void> _submit() async {
    if (_isConnecting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Trimmed because a copied key routinely arrives with a trailing newline,
    // and a credential that fails for an invisible reason is the worst possible
    // first experience.
    final String token = _controller.text.trim();

    setState(() {
      _isConnecting = true;
      _failure = null;
    });

    await ref.read(sessionProvider.notifier).signIn(token);
    if (!mounted) return;

    final SessionState? state = ref.read(sessionProvider).valueOrNull;
    setState(() => _isConnecting = false);

    switch (state?.status) {
      case SessionStatus.ready:
        // The gate beneath this route now renders the app, so there is nothing
        // left for this screen to do.
        unawaited(Navigator.of(context).maybePop());
      case SessionStatus.failed:
        final Object? error = state?.error;
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
      appBar: AppBar(title: const Text('Access key')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.lg,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: <Widget>[
            Text(
              'Paste your access key',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Puter copied it to your clipboard when you tapped Create token.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            TextFormField(
              controller: _controller,
              enabled: !_isConnecting,
              obscureText: _obscured,
              autocorrect: false,
              enableSuggestions: false,
              maxLines: 1,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_failure != null) setState(() => _failure = null);
              },
              // Monospace, because a key is a string of lookalike characters
              // and a proportional font makes `1`/`l`/`I` and `0`/`O`
              // indistinguishable at exactly the moment the user is checking
              // whether they pasted the right thing.
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                letterSpacing: 0.2,
              ),
              decoration: InputDecoration(
                labelText: 'Access key',
                hintText: 'Paste here',
                prefixIcon: const Icon(Icons.key_rounded),
                suffixIcon: IconButton(
                  onPressed: _isConnecting ? null : _pasteFromClipboard,
                  icon: const Icon(Icons.content_paste_rounded),
                  tooltip: 'Paste from clipboard',
                ),
              ),
              validator: (String? value) {
                final String text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return 'Paste the key from your Puter account page.';
                }
                if (text.length < 10) {
                  return 'That looks too short to be an access key.';
                }
                return null;
              },
            ),

            // One tap to hide or reveal, kept as a separate row rather than
            // crammed beside the paste button: two 48dp targets competing for
            // the same edge is how mistaps happen.
            if (_controller.text.isNotEmpty || _obscured)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _obscured = !_obscured),
                  icon: Icon(
                    _obscured
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 18,
                  ),
                  label: Text(_obscured ? 'Show key' : 'Hide key'),
                ),
              ),

            if (_failure != null) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              InlineBanner(
                tone: BannerTone.problem,
                icon: _failure!.icon,
                title: _failure!.title,
                message: _failure!.message,
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              onPressed: _isConnecting ? null : _submit,
              child: _isConnecting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),

            const SizedBox(height: AppSpacing.xl),
            InlineBanner(
              tone: BannerTone.info,
              title: 'Try once, then check',
              message: 'Puter temporarily blocks sign-ins for 15 minutes after '
                  'ten failed attempts — even a correct key. This app tries '
                  'once and stops, so if it does not connect, check the key on '
                  'your Puter page before trying again.',
              action: TextButton.icon(
                onPressed: () => PlatformBridge.openUrl(
                  PuterEndpoints.dashboardAccount,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Open my Puter account page'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

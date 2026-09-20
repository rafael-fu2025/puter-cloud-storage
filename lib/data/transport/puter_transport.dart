/// The transport boundary — the one place in the app that knows Puter exists
/// as a protocol.
///
/// Three implementations sit behind this interface (ADR 0002):
///
/// * [WebDavTransport] — pure Dart, the primary path.
/// * `WebViewTransport` — Puter.js in a WebView, for what WebDAV cannot express.
/// * `RestTransport` — undocumented driver calls, disabled by default.
///
/// A single contract test suite runs against every implementation, so a
/// fallback cannot silently diverge from the primary. That suite is what makes
/// a three-transport design safe rather than aspirational.
///
/// Nothing above the data layer may import a concrete transport.
library;

import 'dart:async';

import '../../domain/entities/remote_node.dart';

/// Credential passed to a transport.
///
/// Wraps the raw token so it is awkward to log by accident and easy to find by
/// grep. Never serialise this, never include it in an error payload.
class TokenCredential {
  const TokenCredential(this.token);

  final String token;

  /// Deliberately redacted — an accidental string interpolation of a
  /// credential is the most common way one leaks.
  @override
  String toString() => 'TokenCredential(***)';
}

/// Which capabilities a transport can actually perform.
///
/// WebDAV and the WebView bridge cover different ground; the UI uses this to
/// hide features rather than fail at the point of use.
class TransportCapabilities {
  const TransportCapabilities({
    this.canList = true,
    this.canStat = true,
    this.canWrite = true,
    this.canRead = true,
    this.canMutate = true,
    this.canResumeUpload = false,
    this.canResumeDownload = false,
    this.canReportUsage = false,
    this.canSignReadUrl = false,
    this.canShare = false,
    this.supportsSearch = false,
  });

  final bool canList;
  final bool canStat;
  final bool canWrite;
  final bool canRead;
  final bool canMutate;

  /// Whether uploads can resume mid-file via ranged requests.
  final bool canResumeUpload;

  /// Whether downloads can resume via `Range`.
  final bool canResumeDownload;

  /// Whether live quota (`capacity` / `used`) is available.
  final bool canReportUsage;

  /// Whether signed temporary read URLs can be generated.
  final bool canSignReadUrl;

  final bool canShare;
  final bool supportsSearch;

  @override
  String toString() => 'TransportCapabilities('
      '${[if (canList) 'list', if (canWrite) 'write', if (canRead) 'read', if (canMutate) 'mutate', if (canResumeUpload) 'resumeUp', if (canResumeDownload) 'resumeDown', if (canReportUsage) 'usage', if (canSignReadUrl) 'sign', if (canShare) 'share'].join(',')})';
}

/// Parameters for an upload.
class UploadRequest {
  const UploadRequest({
    required this.localPath,
    required this.remotePath,
    this.overwrite = false,
    this.createMissingParents = true,
    this.onProgress,
    this.cancelSignal,
  });

  final String localPath;
  final String remotePath;

  /// Defaults to `false`, matching Puter's own default. Overwriting is an
  /// explicit user choice, never an accident.
  final bool overwrite;

  final bool createMissingParents;

  /// Reports bytes written so far.
  final void Function(int bytesDone, int totalBytes)? onProgress;

  /// Cooperative cancellation. Transports must honour this at chunk
  /// boundaries rather than ignoring it.
  final Future<void>? cancelSignal;
}

/// Parameters for a download.
class DownloadRequest {
  const DownloadRequest({
    required this.remotePath,
    required this.localPath,
    this.resumeFromBytes = 0,
    this.onProgress,
    this.cancelSignal,
  });

  final String remotePath;
  final String localPath;

  /// Byte offset to resume from. Non-zero requires `canResumeDownload`.
  final int resumeFromBytes;

  final void Function(int bytesDone, int totalBytes)? onProgress;
  final Future<void>? cancelSignal;
}

/// The Puter filesystem, as the application needs it.
///
/// Deliberately narrow: this models the operations the product requires, not
/// the whole of Puter's surface. Every method throws `PuterException`.
abstract class PuterTransport {
  /// Stable identifier for diagnostics and persisted settings.
  String get name;

  /// What this transport can actually do.
  TransportCapabilities get capabilities;

  /// Establish the session. Called exactly once per token.
  ///
  /// **Must not retry internally.** Ten failed WebDAV sign-ins in 15 minutes
  /// lock the account out of WebDAV for the whole window, including for a
  /// correct token. A transport that retries here can lock the user out of
  /// their own storage — see `docs/security.md` §4.
  Future<void> authenticate(TokenCredential credential);

  /// Identity of the authenticated account.
  Future<PuterIdentity> identity();

  /// List a directory, optionally paged.
  Future<RemoteNodePage> list(ListRequest request);

  /// Metadata for a single path.
  Future<RemoteNode> stat(String path);

  /// Create a directory. Must fail with `alreadyExists` rather than silently
  /// succeeding, so the UI can report the truth.
  Future<void> createDirectory(String path, {bool createParents = true});

  /// Delete a file, or a directory when [recursive] is set.
  Future<void> delete(String path, {bool recursive = false});

  /// Move a node. Used for both move and rename, since WebDAV's `MOVE` covers
  /// both and keeping them separate would be a leaky abstraction.
  Future<void> move(String from, String to, {bool overwrite = false});

  /// Copy a node.
  Future<void> copy(String from, String to, {bool overwrite = false});

  /// Upload one file. Per ADR 0004, never a batch.
  Future<RemoteNode> upload(UploadRequest request);

  /// Download one file, streaming to disk.
  Future<void> download(DownloadRequest request);

  /// Live quota. Throws `unsupported` when `capabilities.canReportUsage` is
  /// false — the caller should fall back to another transport rather than
  /// guessing.
  Future<StorageUsage> usage();

  /// A temporary URL anyone can use to read one file.
  ///
  /// Throws `unsupported` when `capabilities.canSignReadUrl` is false.
  Future<Uri> signedReadUrl(String path, {Duration ttl = const Duration(hours: 1)});

  /// Release resources. Safe to call more than once.
  Future<void> dispose();
}

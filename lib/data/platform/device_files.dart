/// The device side of file handling: picking, exporting, opening.
///
/// Implemented in `MainActivity.kt` over Android's Storage Access Framework
/// rather than through a plugin, for two reasons that both come from the build
/// assessment (docs/build-assessment.md §4.4–4.5):
///
/// 1. The obvious plugins pin `compileSdk 34` against this app's 36. That is a
///    build hazard for a capability that is about eighty lines of Kotlin.
/// 2. SAF needs **no runtime permission** — `ACTION_OPEN_DOCUMENT` and
///    `ACTION_CREATE_DOCUMENT` grant access to exactly the URI the user chose.
///    So there is no permission to request, and no reason for
///    `permission_handler` to be in the dependency list at all.
///
/// Every method degrades rather than throwing: a device that cannot answer
/// returns an empty list or `false`, and the caller says so in the UI. A
/// storage app that crashes because a picker was unavailable is worse than one
/// that explains itself.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A file the user chose to upload.
///
/// [path] is a real filesystem path, not a `content://` URI: the picker copies
/// the selection into the app's cache first, because the transport streams from
/// disk and `dart:io` cannot open a SAF URI.
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  final String path;
  final String name;
  final int sizeBytes;

  /// Best-effort content type, from the extension.
  String? get mimeType => lookupMimeType(name);

  @override
  String toString() => 'PickedFile($name, $sizeBytes bytes)';
}

/// Picking, exporting and opening files on the device.
abstract class DeviceFileService {
  /// Let the user choose one or more files. Empty when they cancel.
  Future<List<PickedFile>> pickFiles();

  /// Write a local file to a destination the user chooses. `false` when they
  /// cancel.
  Future<bool> exportFile({
    required String localPath,
    required String suggestedName,
    String? mimeType,
  });

  /// Hand a local file to whatever app can display it.
  Future<bool> openFile({required String localPath, String? mimeType});

  /// Delete a file this service staged for an upload, once it is no longer
  /// needed.
  ///
  /// A no-op for anything the app did not stage itself. Implementations must
  /// refuse paths outside their own staging area rather than trusting the
  /// argument — this deletes files.
  Future<bool> discardStagedUpload(String localPath);

  /// Where downloads land when the user has not said otherwise.
  Future<Directory> downloadDirectory();
}

/// The real implementation, over a [MethodChannel] into `MainActivity.kt`.
class PlatformDeviceFiles implements DeviceFileService {
  PlatformDeviceFiles({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName =
      'com.putercloud.puter_cloud_storage/files';

  final MethodChannel _channel;

  @override
  Future<List<PickedFile>> pickFiles() async {
    try {
      final result = await _channel.invokeListMethod<dynamic>('pickFiles');
      if (result == null) return const <PickedFile>[];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map(_toPickedFile)
          .whereType<PickedFile>()
          .toList(growable: false);
    } on PlatformException {
      return const <PickedFile>[];
    } on MissingPluginException {
      // Desktop and tests. Reported upward as "nothing was chosen", which the
      // UI already handles.
      return const <PickedFile>[];
    }
  }

  @override
  Future<bool> exportFile({
    required String localPath,
    required String suggestedName,
    String? mimeType,
  }) async {
    try {
      final opened = await _channel.invokeMethod<bool>('exportFile', <String, dynamic>{
        'path': localPath,
        'fileName': suggestedName,
        'mimeType': mimeType ?? lookupMimeType(suggestedName) ?? '*/*',
      });
      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openFile({required String localPath, String? mimeType}) async {
    try {
      final opened = await _channel.invokeMethod<bool>('openFile', <String, dynamic>{
        'path': localPath,
        'mimeType': mimeType ?? lookupMimeType(localPath) ?? '*/*',
      });
      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> discardStagedUpload(String localPath) async {
    try {
      final bool? removed = await _channel.invokeMethod<bool>(
        'discardStagedUpload',
        <String, dynamic>{'path': localPath},
      );
      return removed ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The app-specific external downloads folder.
  ///
  /// Chosen over the public `Downloads` directory because writing there needs
  /// either `MANAGE_EXTERNAL_STORAGE` — which Play Store review rejects for an
  /// app that does not need it — or a SAF grant for every file. The app-specific
  /// folder is visible to any file manager, needs no permission, and is removed
  /// on uninstall along with everything else the app owns.
  ///
  /// Falls back to the private documents directory when external storage is
  /// not mounted, so a download never fails for lack of a place to land.
  @override
  Future<Directory> downloadDirectory() async {
    Directory base;
    try {
      base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } on Object {
      base = await getApplicationDocumentsDirectory();
    }
    final directory = Directory(p.join(base.path, 'Downloads'));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static PickedFile? _toPickedFile(Map<dynamic, dynamic> map) {
    final path = map['path'];
    if (path is! String || path.isEmpty) return null;
    return PickedFile(
      path: path,
      name: map['name'] is String ? map['name'] as String : p.basename(path),
      sizeBytes: map['size'] is int ? map['size'] as int : 0,
    );
  }
}

/// Device integration that does nothing, for widget tests and desktop runs.
///
/// Returns the same "the user chose nothing" answers the platform returns on
/// cancellation, so screens exercise their empty paths rather than their error
/// paths.
class UnavailableDeviceFiles implements DeviceFileService {
  const UnavailableDeviceFiles();

  @override
  Future<List<PickedFile>> pickFiles() async => const <PickedFile>[];

  @override
  Future<bool> exportFile({
    required String localPath,
    required String suggestedName,
    String? mimeType,
  }) async =>
      false;

  @override
  Future<bool> openFile({required String localPath, String? mimeType}) async =>
      false;

  /// Nothing here stages anything, so there is never anything to discard.
  @override
  Future<bool> discardStagedUpload(String localPath) async => false;

  @override
  Future<Directory> downloadDirectory() async =>
      Directory.systemTemp.createTempSync('puter_downloads');
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $RemoteNodesTable extends RemoteNodes
    with TableInfo<$RemoteNodesTable, RemoteNodeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteNodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _modifiedMeta = const VerificationMeta(
    'modified',
  );
  @override
  late final GeneratedColumn<DateTime> modified = GeneratedColumn<DateTime>(
    'modified',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _parentPathMeta = const VerificationMeta(
    'parentPath',
  );
  @override
  late final GeneratedColumn<String> parentPath = GeneratedColumn<String>(
    'parent_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isFolderMeta = const VerificationMeta(
    'isFolder',
  );
  @override
  late final GeneratedColumn<bool> isFolder = GeneratedColumn<bool>(
    'is_folder',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_folder" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _cachedAtMeta = const VerificationMeta(
    'cachedAt',
  );
  @override
  late final GeneratedColumn<DateTime> cachedAt = GeneratedColumn<DateTime>(
    'cached_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _etagMeta = const VerificationMeta('etag');
  @override
  late final GeneratedColumn<String> etag = GeneratedColumn<String>(
    'etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isSharedMeta = const VerificationMeta(
    'isShared',
  );
  @override
  late final GeneratedColumn<bool> isShared = GeneratedColumn<bool>(
    'is_shared',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_shared" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    path,
    name,
    type,
    size,
    modified,
    parentPath,
    isFolder,
    cachedAt,
    mimeType,
    etag,
    isShared,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteNodeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    }
    if (data.containsKey('modified')) {
      context.handle(
        _modifiedMeta,
        modified.isAcceptableOrUnknown(data['modified']!, _modifiedMeta),
      );
    }
    if (data.containsKey('parent_path')) {
      context.handle(
        _parentPathMeta,
        parentPath.isAcceptableOrUnknown(data['parent_path']!, _parentPathMeta),
      );
    }
    if (data.containsKey('is_folder')) {
      context.handle(
        _isFolderMeta,
        isFolder.isAcceptableOrUnknown(data['is_folder']!, _isFolderMeta),
      );
    }
    if (data.containsKey('cached_at')) {
      context.handle(
        _cachedAtMeta,
        cachedAt.isAcceptableOrUnknown(data['cached_at']!, _cachedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedAtMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('etag')) {
      context.handle(
        _etagMeta,
        etag.isAcceptableOrUnknown(data['etag']!, _etagMeta),
      );
    }
    if (data.containsKey('is_shared')) {
      context.handle(
        _isSharedMeta,
        isShared.isAcceptableOrUnknown(data['is_shared']!, _isSharedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {path};
  @override
  RemoteNodeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteNodeRow(
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      modified: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}modified'],
      ),
      parentPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_path'],
      ),
      isFolder: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_folder'],
      )!,
      cachedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}cached_at'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      etag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}etag'],
      ),
      isShared: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_shared'],
      ),
    );
  }

  @override
  $RemoteNodesTable createAlias(String alias) {
    return $RemoteNodesTable(attachedDatabase, alias);
  }
}

class RemoteNodeRow extends DataClass implements Insertable<RemoteNodeRow> {
  /// Absolute remote path including the node's own name, e.g.
  /// `/Documents/report.pdf`.
  final String path;

  /// Display name without the path, e.g. `report.pdf`.
  final String name;

  /// Coarse category — `folder` or `file`.
  final String type;

  /// File size in bytes. `0` for folders.
  final int size;

  /// Last modified time, or `null` when the server did not report one.
  final DateTime? modified;

  /// Parent directory path, or `null` for the root itself. Indexed, because
  /// every folder render is a lookup by this column.
  final String? parentPath;

  /// Whether this node is a folder.
  final bool isFolder;

  /// When this row was last confirmed against the server.
  final DateTime cachedAt;
  final String? mimeType;

  /// Server-side version marker. Used to skip no-op writes on refresh.
  final String? etag;

  /// `null` when unknown, matching the domain's tri-state sharing flag.
  final bool? isShared;
  const RemoteNodeRow({
    required this.path,
    required this.name,
    required this.type,
    required this.size,
    this.modified,
    this.parentPath,
    required this.isFolder,
    required this.cachedAt,
    this.mimeType,
    this.etag,
    this.isShared,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['path'] = Variable<String>(path);
    map['name'] = Variable<String>(name);
    map['type'] = Variable<String>(type);
    map['size'] = Variable<int>(size);
    if (!nullToAbsent || modified != null) {
      map['modified'] = Variable<DateTime>(modified);
    }
    if (!nullToAbsent || parentPath != null) {
      map['parent_path'] = Variable<String>(parentPath);
    }
    map['is_folder'] = Variable<bool>(isFolder);
    map['cached_at'] = Variable<DateTime>(cachedAt);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || etag != null) {
      map['etag'] = Variable<String>(etag);
    }
    if (!nullToAbsent || isShared != null) {
      map['is_shared'] = Variable<bool>(isShared);
    }
    return map;
  }

  RemoteNodesCompanion toCompanion(bool nullToAbsent) {
    return RemoteNodesCompanion(
      path: Value(path),
      name: Value(name),
      type: Value(type),
      size: Value(size),
      modified: modified == null && nullToAbsent
          ? const Value.absent()
          : Value(modified),
      parentPath: parentPath == null && nullToAbsent
          ? const Value.absent()
          : Value(parentPath),
      isFolder: Value(isFolder),
      cachedAt: Value(cachedAt),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      etag: etag == null && nullToAbsent ? const Value.absent() : Value(etag),
      isShared: isShared == null && nullToAbsent
          ? const Value.absent()
          : Value(isShared),
    );
  }

  factory RemoteNodeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteNodeRow(
      path: serializer.fromJson<String>(json['path']),
      name: serializer.fromJson<String>(json['name']),
      type: serializer.fromJson<String>(json['type']),
      size: serializer.fromJson<int>(json['size']),
      modified: serializer.fromJson<DateTime?>(json['modified']),
      parentPath: serializer.fromJson<String?>(json['parentPath']),
      isFolder: serializer.fromJson<bool>(json['isFolder']),
      cachedAt: serializer.fromJson<DateTime>(json['cachedAt']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      etag: serializer.fromJson<String?>(json['etag']),
      isShared: serializer.fromJson<bool?>(json['isShared']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'path': serializer.toJson<String>(path),
      'name': serializer.toJson<String>(name),
      'type': serializer.toJson<String>(type),
      'size': serializer.toJson<int>(size),
      'modified': serializer.toJson<DateTime?>(modified),
      'parentPath': serializer.toJson<String?>(parentPath),
      'isFolder': serializer.toJson<bool>(isFolder),
      'cachedAt': serializer.toJson<DateTime>(cachedAt),
      'mimeType': serializer.toJson<String?>(mimeType),
      'etag': serializer.toJson<String?>(etag),
      'isShared': serializer.toJson<bool?>(isShared),
    };
  }

  RemoteNodeRow copyWith({
    String? path,
    String? name,
    String? type,
    int? size,
    Value<DateTime?> modified = const Value.absent(),
    Value<String?> parentPath = const Value.absent(),
    bool? isFolder,
    DateTime? cachedAt,
    Value<String?> mimeType = const Value.absent(),
    Value<String?> etag = const Value.absent(),
    Value<bool?> isShared = const Value.absent(),
  }) => RemoteNodeRow(
    path: path ?? this.path,
    name: name ?? this.name,
    type: type ?? this.type,
    size: size ?? this.size,
    modified: modified.present ? modified.value : this.modified,
    parentPath: parentPath.present ? parentPath.value : this.parentPath,
    isFolder: isFolder ?? this.isFolder,
    cachedAt: cachedAt ?? this.cachedAt,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    etag: etag.present ? etag.value : this.etag,
    isShared: isShared.present ? isShared.value : this.isShared,
  );
  RemoteNodeRow copyWithCompanion(RemoteNodesCompanion data) {
    return RemoteNodeRow(
      path: data.path.present ? data.path.value : this.path,
      name: data.name.present ? data.name.value : this.name,
      type: data.type.present ? data.type.value : this.type,
      size: data.size.present ? data.size.value : this.size,
      modified: data.modified.present ? data.modified.value : this.modified,
      parentPath: data.parentPath.present
          ? data.parentPath.value
          : this.parentPath,
      isFolder: data.isFolder.present ? data.isFolder.value : this.isFolder,
      cachedAt: data.cachedAt.present ? data.cachedAt.value : this.cachedAt,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      etag: data.etag.present ? data.etag.value : this.etag,
      isShared: data.isShared.present ? data.isShared.value : this.isShared,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteNodeRow(')
          ..write('path: $path, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('size: $size, ')
          ..write('modified: $modified, ')
          ..write('parentPath: $parentPath, ')
          ..write('isFolder: $isFolder, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('mimeType: $mimeType, ')
          ..write('etag: $etag, ')
          ..write('isShared: $isShared')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    path,
    name,
    type,
    size,
    modified,
    parentPath,
    isFolder,
    cachedAt,
    mimeType,
    etag,
    isShared,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteNodeRow &&
          other.path == this.path &&
          other.name == this.name &&
          other.type == this.type &&
          other.size == this.size &&
          other.modified == this.modified &&
          other.parentPath == this.parentPath &&
          other.isFolder == this.isFolder &&
          other.cachedAt == this.cachedAt &&
          other.mimeType == this.mimeType &&
          other.etag == this.etag &&
          other.isShared == this.isShared);
}

class RemoteNodesCompanion extends UpdateCompanion<RemoteNodeRow> {
  final Value<String> path;
  final Value<String> name;
  final Value<String> type;
  final Value<int> size;
  final Value<DateTime?> modified;
  final Value<String?> parentPath;
  final Value<bool> isFolder;
  final Value<DateTime> cachedAt;
  final Value<String?> mimeType;
  final Value<String?> etag;
  final Value<bool?> isShared;
  final Value<int> rowid;
  const RemoteNodesCompanion({
    this.path = const Value.absent(),
    this.name = const Value.absent(),
    this.type = const Value.absent(),
    this.size = const Value.absent(),
    this.modified = const Value.absent(),
    this.parentPath = const Value.absent(),
    this.isFolder = const Value.absent(),
    this.cachedAt = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.etag = const Value.absent(),
    this.isShared = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteNodesCompanion.insert({
    required String path,
    required String name,
    required String type,
    this.size = const Value.absent(),
    this.modified = const Value.absent(),
    this.parentPath = const Value.absent(),
    this.isFolder = const Value.absent(),
    required DateTime cachedAt,
    this.mimeType = const Value.absent(),
    this.etag = const Value.absent(),
    this.isShared = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : path = Value(path),
       name = Value(name),
       type = Value(type),
       cachedAt = Value(cachedAt);
  static Insertable<RemoteNodeRow> custom({
    Expression<String>? path,
    Expression<String>? name,
    Expression<String>? type,
    Expression<int>? size,
    Expression<DateTime>? modified,
    Expression<String>? parentPath,
    Expression<bool>? isFolder,
    Expression<DateTime>? cachedAt,
    Expression<String>? mimeType,
    Expression<String>? etag,
    Expression<bool>? isShared,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (path != null) 'path': path,
      if (name != null) 'name': name,
      if (type != null) 'type': type,
      if (size != null) 'size': size,
      if (modified != null) 'modified': modified,
      if (parentPath != null) 'parent_path': parentPath,
      if (isFolder != null) 'is_folder': isFolder,
      if (cachedAt != null) 'cached_at': cachedAt,
      if (mimeType != null) 'mime_type': mimeType,
      if (etag != null) 'etag': etag,
      if (isShared != null) 'is_shared': isShared,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteNodesCompanion copyWith({
    Value<String>? path,
    Value<String>? name,
    Value<String>? type,
    Value<int>? size,
    Value<DateTime?>? modified,
    Value<String?>? parentPath,
    Value<bool>? isFolder,
    Value<DateTime>? cachedAt,
    Value<String?>? mimeType,
    Value<String?>? etag,
    Value<bool?>? isShared,
    Value<int>? rowid,
  }) {
    return RemoteNodesCompanion(
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      size: size ?? this.size,
      modified: modified ?? this.modified,
      parentPath: parentPath ?? this.parentPath,
      isFolder: isFolder ?? this.isFolder,
      cachedAt: cachedAt ?? this.cachedAt,
      mimeType: mimeType ?? this.mimeType,
      etag: etag ?? this.etag,
      isShared: isShared ?? this.isShared,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (modified.present) {
      map['modified'] = Variable<DateTime>(modified.value);
    }
    if (parentPath.present) {
      map['parent_path'] = Variable<String>(parentPath.value);
    }
    if (isFolder.present) {
      map['is_folder'] = Variable<bool>(isFolder.value);
    }
    if (cachedAt.present) {
      map['cached_at'] = Variable<DateTime>(cachedAt.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (etag.present) {
      map['etag'] = Variable<String>(etag.value);
    }
    if (isShared.present) {
      map['is_shared'] = Variable<bool>(isShared.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RemoteNodesCompanion(')
          ..write('path: $path, ')
          ..write('name: $name, ')
          ..write('type: $type, ')
          ..write('size: $size, ')
          ..write('modified: $modified, ')
          ..write('parentPath: $parentPath, ')
          ..write('isFolder: $isFolder, ')
          ..write('cachedAt: $cachedAt, ')
          ..write('mimeType: $mimeType, ')
          ..write('etag: $etag, ')
          ..write('isShared: $isShared, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransferTasksTable extends TransferTasks
    with TableInfo<$TransferTasksTable, TransferTaskRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransferTasksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remotePathMeta = const VerificationMeta(
    'remotePath',
  );
  @override
  late final GeneratedColumn<String> remotePath = GeneratedColumn<String>(
    'remote_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _totalBytesMeta = const VerificationMeta(
    'totalBytes',
  );
  @override
  late final GeneratedColumn<int> totalBytes = GeneratedColumn<int>(
    'total_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _bytesDoneMeta = const VerificationMeta(
    'bytesDone',
  );
  @override
  late final GeneratedColumn<int> bytesDone = GeneratedColumn<int>(
    'bytes_done',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    direction,
    remotePath,
    localPath,
    totalBytes,
    bytesDone,
    state,
    attempts,
    lastError,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transfer_tasks';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransferTaskRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('remote_path')) {
      context.handle(
        _remotePathMeta,
        remotePath.isAcceptableOrUnknown(data['remote_path']!, _remotePathMeta),
      );
    } else if (isInserting) {
      context.missing(_remotePathMeta);
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    } else if (isInserting) {
      context.missing(_localPathMeta);
    }
    if (data.containsKey('total_bytes')) {
      context.handle(
        _totalBytesMeta,
        totalBytes.isAcceptableOrUnknown(data['total_bytes']!, _totalBytesMeta),
      );
    }
    if (data.containsKey('bytes_done')) {
      context.handle(
        _bytesDoneMeta,
        bytesDone.isAcceptableOrUnknown(data['bytes_done']!, _bytesDoneMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransferTaskRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransferTaskRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      remotePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_path'],
      )!,
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      )!,
      totalBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total_bytes'],
      )!,
      bytesDone: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_done'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
    );
  }

  @override
  $TransferTasksTable createAlias(String alias) {
    return $TransferTasksTable(attachedDatabase, alias);
  }
}

class TransferTaskRow extends DataClass implements Insertable<TransferTaskRow> {
  /// Domain-supplied task id. Text, not autoincrement, so a task keeps its
  /// identity across a process restart.
  final String id;

  /// `upload` or `download`.
  final String direction;
  final String remotePath;
  final String localPath;
  final int totalBytes;
  final int bytesDone;

  /// One of `TransferState`'s names.
  final String state;
  final int attempts;
  final String? lastError;
  final DateTime? createdAt;
  const TransferTaskRow({
    required this.id,
    required this.direction,
    required this.remotePath,
    required this.localPath,
    required this.totalBytes,
    required this.bytesDone,
    required this.state,
    required this.attempts,
    this.lastError,
    this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['direction'] = Variable<String>(direction);
    map['remote_path'] = Variable<String>(remotePath);
    map['local_path'] = Variable<String>(localPath);
    map['total_bytes'] = Variable<int>(totalBytes);
    map['bytes_done'] = Variable<int>(bytesDone);
    map['state'] = Variable<String>(state);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    return map;
  }

  TransferTasksCompanion toCompanion(bool nullToAbsent) {
    return TransferTasksCompanion(
      id: Value(id),
      direction: Value(direction),
      remotePath: Value(remotePath),
      localPath: Value(localPath),
      totalBytes: Value(totalBytes),
      bytesDone: Value(bytesDone),
      state: Value(state),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
    );
  }

  factory TransferTaskRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransferTaskRow(
      id: serializer.fromJson<String>(json['id']),
      direction: serializer.fromJson<String>(json['direction']),
      remotePath: serializer.fromJson<String>(json['remotePath']),
      localPath: serializer.fromJson<String>(json['localPath']),
      totalBytes: serializer.fromJson<int>(json['totalBytes']),
      bytesDone: serializer.fromJson<int>(json['bytesDone']),
      state: serializer.fromJson<String>(json['state']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'direction': serializer.toJson<String>(direction),
      'remotePath': serializer.toJson<String>(remotePath),
      'localPath': serializer.toJson<String>(localPath),
      'totalBytes': serializer.toJson<int>(totalBytes),
      'bytesDone': serializer.toJson<int>(bytesDone),
      'state': serializer.toJson<String>(state),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
    };
  }

  TransferTaskRow copyWith({
    String? id,
    String? direction,
    String? remotePath,
    String? localPath,
    int? totalBytes,
    int? bytesDone,
    String? state,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
  }) => TransferTaskRow(
    id: id ?? this.id,
    direction: direction ?? this.direction,
    remotePath: remotePath ?? this.remotePath,
    localPath: localPath ?? this.localPath,
    totalBytes: totalBytes ?? this.totalBytes,
    bytesDone: bytesDone ?? this.bytesDone,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
  );
  TransferTaskRow copyWithCompanion(TransferTasksCompanion data) {
    return TransferTaskRow(
      id: data.id.present ? data.id.value : this.id,
      direction: data.direction.present ? data.direction.value : this.direction,
      remotePath: data.remotePath.present
          ? data.remotePath.value
          : this.remotePath,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      totalBytes: data.totalBytes.present
          ? data.totalBytes.value
          : this.totalBytes,
      bytesDone: data.bytesDone.present ? data.bytesDone.value : this.bytesDone,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransferTaskRow(')
          ..write('id: $id, ')
          ..write('direction: $direction, ')
          ..write('remotePath: $remotePath, ')
          ..write('localPath: $localPath, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('bytesDone: $bytesDone, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    direction,
    remotePath,
    localPath,
    totalBytes,
    bytesDone,
    state,
    attempts,
    lastError,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransferTaskRow &&
          other.id == this.id &&
          other.direction == this.direction &&
          other.remotePath == this.remotePath &&
          other.localPath == this.localPath &&
          other.totalBytes == this.totalBytes &&
          other.bytesDone == this.bytesDone &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt);
}

class TransferTasksCompanion extends UpdateCompanion<TransferTaskRow> {
  final Value<String> id;
  final Value<String> direction;
  final Value<String> remotePath;
  final Value<String> localPath;
  final Value<int> totalBytes;
  final Value<int> bytesDone;
  final Value<String> state;
  final Value<int> attempts;
  final Value<String?> lastError;
  final Value<DateTime?> createdAt;
  final Value<int> rowid;
  const TransferTasksCompanion({
    this.id = const Value.absent(),
    this.direction = const Value.absent(),
    this.remotePath = const Value.absent(),
    this.localPath = const Value.absent(),
    this.totalBytes = const Value.absent(),
    this.bytesDone = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransferTasksCompanion.insert({
    required String id,
    required String direction,
    required String remotePath,
    required String localPath,
    this.totalBytes = const Value.absent(),
    this.bytesDone = const Value.absent(),
    required String state,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       direction = Value(direction),
       remotePath = Value(remotePath),
       localPath = Value(localPath),
       state = Value(state);
  static Insertable<TransferTaskRow> custom({
    Expression<String>? id,
    Expression<String>? direction,
    Expression<String>? remotePath,
    Expression<String>? localPath,
    Expression<int>? totalBytes,
    Expression<int>? bytesDone,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (direction != null) 'direction': direction,
      if (remotePath != null) 'remote_path': remotePath,
      if (localPath != null) 'local_path': localPath,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (bytesDone != null) 'bytes_done': bytesDone,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransferTasksCompanion copyWith({
    Value<String>? id,
    Value<String>? direction,
    Value<String>? remotePath,
    Value<String>? localPath,
    Value<int>? totalBytes,
    Value<int>? bytesDone,
    Value<String>? state,
    Value<int>? attempts,
    Value<String?>? lastError,
    Value<DateTime?>? createdAt,
    Value<int>? rowid,
  }) {
    return TransferTasksCompanion(
      id: id ?? this.id,
      direction: direction ?? this.direction,
      remotePath: remotePath ?? this.remotePath,
      localPath: localPath ?? this.localPath,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesDone: bytesDone ?? this.bytesDone,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (remotePath.present) {
      map['remote_path'] = Variable<String>(remotePath.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (totalBytes.present) {
      map['total_bytes'] = Variable<int>(totalBytes.value);
    }
    if (bytesDone.present) {
      map['bytes_done'] = Variable<int>(bytesDone.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransferTasksCompanion(')
          ..write('id: $id, ')
          ..write('direction: $direction, ')
          ..write('remotePath: $remotePath, ')
          ..write('localPath: $localPath, ')
          ..write('totalBytes: $totalBytes, ')
          ..write('bytesDone: $bytesDone, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RemoteNodesTable remoteNodes = $RemoteNodesTable(this);
  late final $TransferTasksTable transferTasks = $TransferTasksTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index idxRemoteNodesParent = Index(
    'idx_remote_nodes_parent',
    'CREATE INDEX idx_remote_nodes_parent ON remote_nodes (parent_path)',
  );
  late final Index idxRemoteNodesName = Index(
    'idx_remote_nodes_name',
    'CREATE INDEX idx_remote_nodes_name ON remote_nodes (name)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    remoteNodes,
    transferTasks,
    settings,
    idxRemoteNodesParent,
    idxRemoteNodesName,
  ];
}

typedef $$RemoteNodesTableCreateCompanionBuilder =
    RemoteNodesCompanion Function({
      required String path,
      required String name,
      required String type,
      Value<int> size,
      Value<DateTime?> modified,
      Value<String?> parentPath,
      Value<bool> isFolder,
      required DateTime cachedAt,
      Value<String?> mimeType,
      Value<String?> etag,
      Value<bool?> isShared,
      Value<int> rowid,
    });
typedef $$RemoteNodesTableUpdateCompanionBuilder =
    RemoteNodesCompanion Function({
      Value<String> path,
      Value<String> name,
      Value<String> type,
      Value<int> size,
      Value<DateTime?> modified,
      Value<String?> parentPath,
      Value<bool> isFolder,
      Value<DateTime> cachedAt,
      Value<String?> mimeType,
      Value<String?> etag,
      Value<bool?> isShared,
      Value<int> rowid,
    });

class $$RemoteNodesTableFilterComposer
    extends Composer<_$AppDatabase, $RemoteNodesTable> {
  $$RemoteNodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get modified => $composableBuilder(
    column: $table.modified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get parentPath => $composableBuilder(
    column: $table.parentPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFolder => $composableBuilder(
    column: $table.isFolder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isShared => $composableBuilder(
    column: $table.isShared,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteNodesTableOrderingComposer
    extends Composer<_$AppDatabase, $RemoteNodesTable> {
  $$RemoteNodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get modified => $composableBuilder(
    column: $table.modified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get parentPath => $composableBuilder(
    column: $table.parentPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFolder => $composableBuilder(
    column: $table.isFolder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get cachedAt => $composableBuilder(
    column: $table.cachedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get etag => $composableBuilder(
    column: $table.etag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isShared => $composableBuilder(
    column: $table.isShared,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteNodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RemoteNodesTable> {
  $$RemoteNodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<DateTime> get modified =>
      $composableBuilder(column: $table.modified, builder: (column) => column);

  GeneratedColumn<String> get parentPath => $composableBuilder(
    column: $table.parentPath,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFolder =>
      $composableBuilder(column: $table.isFolder, builder: (column) => column);

  GeneratedColumn<DateTime> get cachedAt =>
      $composableBuilder(column: $table.cachedAt, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get etag =>
      $composableBuilder(column: $table.etag, builder: (column) => column);

  GeneratedColumn<bool> get isShared =>
      $composableBuilder(column: $table.isShared, builder: (column) => column);
}

class $$RemoteNodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RemoteNodesTable,
          RemoteNodeRow,
          $$RemoteNodesTableFilterComposer,
          $$RemoteNodesTableOrderingComposer,
          $$RemoteNodesTableAnnotationComposer,
          $$RemoteNodesTableCreateCompanionBuilder,
          $$RemoteNodesTableUpdateCompanionBuilder,
          (
            RemoteNodeRow,
            BaseReferences<_$AppDatabase, $RemoteNodesTable, RemoteNodeRow>,
          ),
          RemoteNodeRow,
          PrefetchHooks Function()
        > {
  $$RemoteNodesTableTableManager(_$AppDatabase db, $RemoteNodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteNodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RemoteNodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RemoteNodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> path = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<DateTime?> modified = const Value.absent(),
                Value<String?> parentPath = const Value.absent(),
                Value<bool> isFolder = const Value.absent(),
                Value<DateTime> cachedAt = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<bool?> isShared = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteNodesCompanion(
                path: path,
                name: name,
                type: type,
                size: size,
                modified: modified,
                parentPath: parentPath,
                isFolder: isFolder,
                cachedAt: cachedAt,
                mimeType: mimeType,
                etag: etag,
                isShared: isShared,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String path,
                required String name,
                required String type,
                Value<int> size = const Value.absent(),
                Value<DateTime?> modified = const Value.absent(),
                Value<String?> parentPath = const Value.absent(),
                Value<bool> isFolder = const Value.absent(),
                required DateTime cachedAt,
                Value<String?> mimeType = const Value.absent(),
                Value<String?> etag = const Value.absent(),
                Value<bool?> isShared = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteNodesCompanion.insert(
                path: path,
                name: name,
                type: type,
                size: size,
                modified: modified,
                parentPath: parentPath,
                isFolder: isFolder,
                cachedAt: cachedAt,
                mimeType: mimeType,
                etag: etag,
                isShared: isShared,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteNodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RemoteNodesTable,
      RemoteNodeRow,
      $$RemoteNodesTableFilterComposer,
      $$RemoteNodesTableOrderingComposer,
      $$RemoteNodesTableAnnotationComposer,
      $$RemoteNodesTableCreateCompanionBuilder,
      $$RemoteNodesTableUpdateCompanionBuilder,
      (
        RemoteNodeRow,
        BaseReferences<_$AppDatabase, $RemoteNodesTable, RemoteNodeRow>,
      ),
      RemoteNodeRow,
      PrefetchHooks Function()
    >;
typedef $$TransferTasksTableCreateCompanionBuilder =
    TransferTasksCompanion Function({
      required String id,
      required String direction,
      required String remotePath,
      required String localPath,
      Value<int> totalBytes,
      Value<int> bytesDone,
      required String state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime?> createdAt,
      Value<int> rowid,
    });
typedef $$TransferTasksTableUpdateCompanionBuilder =
    TransferTasksCompanion Function({
      Value<String> id,
      Value<String> direction,
      Value<String> remotePath,
      Value<String> localPath,
      Value<int> totalBytes,
      Value<int> bytesDone,
      Value<String> state,
      Value<int> attempts,
      Value<String?> lastError,
      Value<DateTime?> createdAt,
      Value<int> rowid,
    });

class $$TransferTasksTableFilterComposer
    extends Composer<_$AppDatabase, $TransferTasksTable> {
  $$TransferTasksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytesDone => $composableBuilder(
    column: $table.bytesDone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TransferTasksTableOrderingComposer
    extends Composer<_$AppDatabase, $TransferTasksTable> {
  $$TransferTasksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesDone => $composableBuilder(
    column: $table.bytesDone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TransferTasksTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransferTasksTable> {
  $$TransferTasksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get remotePath => $composableBuilder(
    column: $table.remotePath,
    builder: (column) => column,
  );

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<int> get totalBytes => $composableBuilder(
    column: $table.totalBytes,
    builder: (column) => column,
  );

  GeneratedColumn<int> get bytesDone =>
      $composableBuilder(column: $table.bytesDone, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$TransferTasksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransferTasksTable,
          TransferTaskRow,
          $$TransferTasksTableFilterComposer,
          $$TransferTasksTableOrderingComposer,
          $$TransferTasksTableAnnotationComposer,
          $$TransferTasksTableCreateCompanionBuilder,
          $$TransferTasksTableUpdateCompanionBuilder,
          (
            TransferTaskRow,
            BaseReferences<_$AppDatabase, $TransferTasksTable, TransferTaskRow>,
          ),
          TransferTaskRow,
          PrefetchHooks Function()
        > {
  $$TransferTasksTableTableManager(_$AppDatabase db, $TransferTasksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransferTasksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransferTasksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransferTasksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> remotePath = const Value.absent(),
                Value<String> localPath = const Value.absent(),
                Value<int> totalBytes = const Value.absent(),
                Value<int> bytesDone = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransferTasksCompanion(
                id: id,
                direction: direction,
                remotePath: remotePath,
                localPath: localPath,
                totalBytes: totalBytes,
                bytesDone: bytesDone,
                state: state,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String direction,
                required String remotePath,
                required String localPath,
                Value<int> totalBytes = const Value.absent(),
                Value<int> bytesDone = const Value.absent(),
                required String state,
                Value<int> attempts = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransferTasksCompanion.insert(
                id: id,
                direction: direction,
                remotePath: remotePath,
                localPath: localPath,
                totalBytes: totalBytes,
                bytesDone: bytesDone,
                state: state,
                attempts: attempts,
                lastError: lastError,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TransferTasksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransferTasksTable,
      TransferTaskRow,
      $$TransferTasksTableFilterComposer,
      $$TransferTasksTableOrderingComposer,
      $$TransferTasksTableAnnotationComposer,
      $$TransferTasksTableCreateCompanionBuilder,
      $$TransferTasksTableUpdateCompanionBuilder,
      (
        TransferTaskRow,
        BaseReferences<_$AppDatabase, $TransferTasksTable, TransferTaskRow>,
      ),
      TransferTaskRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RemoteNodesTableTableManager get remoteNodes =>
      $$RemoteNodesTableTableManager(_db, _db.remoteNodes);
  $$TransferTasksTableTableManager get transferTasks =>
      $$TransferTasksTableTableManager(_db, _db.transferTasks);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}

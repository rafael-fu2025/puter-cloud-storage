/// Tests for the repository's cache policy and its error handling.
///
/// Two behaviours here are the reason the repository exists at all, and both
/// are asserted directly:
///
/// * a listing renders from the index before the network answers, and
/// * a transport error keeps its [PuterErrorKind] instead of being flattened
///   into "network error".
///
/// The second one is a real defect this suite was written to pin down: the
/// previous revision wrapped every failure as `networkError`, which turned
/// "your storage is full" into "check your connection".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:puter_cloud_storage/core/config/app_config.dart';
import 'package:puter_cloud_storage/core/error/puter_exception.dart';
import 'package:puter_cloud_storage/data/database/node_cache.dart';
import 'package:puter_cloud_storage/data/repositories/file_repository.dart';
import 'package:puter_cloud_storage/domain/entities/remote_node.dart';

import '../support/fake_transport.dart';

RemoteNode _file(String path, {int size = 10}) => RemoteNode(
      path: path,
      name: path.substring(path.lastIndexOf('/') + 1),
      isDirectory: false,
      sizeBytes: size,
    );

RemoteNode _folder(String path) => RemoteNode(
      path: path,
      name: path.substring(path.lastIndexOf('/') + 1),
      isDirectory: true,
    );

void main() {
  late FakeTransport transport;
  late InMemoryNodeCache cache;
  late FileRepository repository;

  setUp(() {
    transport = FakeTransport(
      tree: <String, List<RemoteNode>>{
        '/': <RemoteNode>[_folder('/Documents'), _file('/notes.txt')],
        '/Documents': <RemoteNode>[_file('/Documents/report.pdf', size: 2048)],
      },
    );
    cache = InMemoryNodeCache();
    repository = FileRepository(
      transport: transport,
      cache: cache,
      config: const AppConfig(),
    );
  });

  group('listing', () {
    test('reads through to the server on a cold cache', () async {
      final listing = await repository.listDirectory('/');

      expect(listing.items, hasLength(2));
      expect(listing.fromCache, isFalse);
      expect(transport.listCalls, <String>['/']);
    });

    test('writes the listing into the index', () async {
      await repository.listDirectory('/');
      final cached = await repository.cachedChildren('/');

      expect(cached.map((RemoteNode n) => n.name), contains('notes.txt'));
    });

    test('performs no request when the cached copy is fresh', () async {
      await repository.listDirectory('/');
      final callsAfterFirst = transport.listCalls.length;

      final second = await repository.listDirectory('/');

      expect(second.fromCache, isTrue);
      expect(
        transport.listCalls.length,
        callsAfterFirst,
        reason: 'a fresh listing must not spend request budget',
      );
    });

    test('force bypasses the freshness window', () async {
      await repository.listDirectory('/');
      final callsAfterFirst = transport.listCalls.length;

      await repository.listDirectory('/', force: true);

      expect(transport.listCalls.length, callsAfterFirst + 1);
    });

    test('falls back to the index when the server cannot be reached', () async {
      await repository.listDirectory('/');
      transport.listError = const PuterException(
        PuterErrorKind.network,
        'unreachable',
      );

      final listing = await repository.listDirectory('/', force: true);

      // Offline browsing is a stated feature: refusing to show folders the app
      // already knows about would be worse than showing them slightly stale.
      expect(listing.items, hasLength(2));
      expect(listing.fromCache, isTrue);
    });

    test('rethrows when there is nothing cached to fall back on', () async {
      transport.listError = const PuterException(
        PuterErrorKind.storageLimitReached,
        'full',
      );

      // The error kind must survive: the UI decides whether to offer Retry from
      // it, and `413` is not retryable.
      await expectLater(
        repository.listDirectory('/'),
        throwsA(
          isA<PuterException>().having(
            (PuterException e) => e.kind,
            'kind',
            PuterErrorKind.storageLimitReached,
          ),
        ),
      );
    });

    test('surfaces per-entry failures rather than dropping them', () async {
      transport.nextPage = const RemoteNodePage(
        items: <RemoteNode>[],
        failures: <NodeFailure>[
          NodeFailure(path: '/locked', message: 'Forbidden', statusCode: 403),
        ],
      );

      final listing = await repository.listDirectory('/', force: true);

      expect(listing.isPartial, isTrue);
      expect(listing.failures.single.path, '/locked');
    });
  });

  group('search', () {
    test('finds a cached entry without touching the network', () async {
      await repository.listDirectory('/');
      final callsBefore = transport.listCalls.length;

      final results = await repository.search('notes');

      expect(results, hasLength(1));
      expect(results.single.path, '/notes.txt');
      expect(
        transport.listCalls.length,
        callsBefore,
        reason: 'search is served from the index only — Puter has no '
            'server-side filesystem search',
      );
    });

    test('is case-insensitive', () async {
      await repository.listDirectory('/');
      expect(await repository.search('NOTES'), hasLength(1));
    });

    test('scopes to a subtree when asked', () async {
      await repository.listDirectory('/');
      await repository.listDirectory('/Documents');

      final scoped = await repository.search('report', scopePath: '/Documents');
      // Scoping to the root is the same as not scoping at all.
      final everywhere = await repository.search('report', scopePath: '/');

      expect(scoped, hasLength(1));
      expect(everywhere, hasLength(1));
    });

    test('ignores a query too short to mean anything', () async {
      await repository.listDirectory('/');
      expect(await repository.search('  '), isEmpty);
    });
  });

  group('mutations', () {
    test('createDirectory reconciles the parent folder', () async {
      await repository.createDirectory('/Documents/Ideas');

      expect(transport.createdDirectories, <String>['/Documents/Ideas']);
      expect(
        transport.listCalls,
        contains('/Documents'),
        reason: 'the parent must be refetched, not patched by guesswork',
      );
    });

    test('delete clears the subtree from the index', () async {
      await repository.listDirectory('/');
      await repository.listDirectory('/Documents');
      final node = (await repository.cachedChildren('/')).firstWhere(
        (RemoteNode n) => n.name == 'Documents',
      );

      await repository.delete(node);

      expect(transport.deletedPaths, <String>['/Documents']);
      expect(await repository.cachedChildren('/Documents'), isEmpty);
    });

    test('move reconciles both the old and the new parent', () async {
      await repository.listDirectory('/');
      final node = (await repository.cachedChildren('/')).firstWhere(
        (RemoteNode n) => n.name == 'Documents',
      );

      await repository.move(node, '/Archive');

      expect(transport.moves.single.to, '/Archive');
      expect(transport.listCalls, contains('/'));
      // The folder moves to the new parent's bucket, so it is browsable there
      // immediately rather than after a refetch.
      final moved = await repository.cachedChildren('/');
      expect(moved.map((RemoteNode n) => n.name), contains('Archive'));
      expect(moved.map((RemoteNode n) => n.name), isNot(contains('Documents')));
    });

    test('refuses to move a folder inside itself', () async {
      final folder = _folder('/Documents');

      await expectLater(
        repository.move(folder, '/Documents/nested'),
        throwsA(
          isA<PuterException>().having(
            (PuterException e) => e.kind,
            'kind',
            PuterErrorKind.badRequest,
          ),
        ),
      );
      expect(
        transport.moves,
        isEmpty,
        reason: 'the server must never see a self-nesting move',
      );
    });

    test('refuses a rename containing a separator', () async {
      await expectLater(
        repository.rename(_file('/notes.txt'), 'a/b'),
        throwsA(isA<PuterException>()),
      );
    });

    test('a no-op rename does not call the server', () async {
      await repository.rename(_file('/notes.txt'), 'notes.txt');
      expect(transport.moves, isEmpty);
    });

    test('emits a change notification naming the affected folder', () async {
      final seen = <Set<String>>[];
      final subscription = repository.changes.listen(seen.add);
      addTearDown(subscription.cancel);

      await repository.createDirectory('/Documents/Ideas');
      await Future<void>.delayed(Duration.zero);

      expect(seen, isNotEmpty);
      expect(seen.first, contains('/Documents'));
    });
  });

  group('quota', () {
    test('is reported when the transport can', () async {
      transport.usageResult = const StorageUsage(
        capacityBytes: 1000,
        usedBytes: 900,
      );

      final usage = await repository.usage();

      expect(usage.freeBytes, 100);
      expect(usage.isNearLimit(0.9), isTrue);
      expect(usage.canFit(100), isTrue);
      expect(usage.canFit(101), isFalse);
    });
  });
}

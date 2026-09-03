import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/share/backend_detector.dart';
import 'package:harness/share/context_length.dart';
import 'package:harness/share/engine_run.dart';
import 'package:harness/share/join_args.dart';
import 'package:harness/share/local_models.dart';
import 'package:harness/share/node_identity.dart';
import 'package:harness/share/share_route.dart';

const _grid = 'grid-3378218621364f16';

DetectedBackend _ollama({bool running = true}) => DetectedBackend(
  kind: BackendKind.ollama,
  label: 'Ollama',
  baseUrl: BackendDetector.ollamaBase,
  running: running,
);

void main() {
  group('which route the page opens on', () {
    test('local leads, because it costs nothing and sends nothing', () {
      expect(
        defaultShareRoute(
          canRunLocal: true,
          serverFound: true,
          hasKeyProvider: true,
        ),
        ShareRoute.local,
      );
    });

    test('a running server beats a key: one press, and no download', () {
      expect(
        defaultShareRoute(
          canRunLocal: false,
          serverFound: true,
          hasKeyProvider: true,
        ),
        ShareRoute.server,
      );
    });

    test('never opens on a route this machine cannot take', () {
      expect(
        defaultShareRoute(
          canRunLocal: false,
          serverFound: false,
          hasKeyProvider: false,
        ),
        // The endpoint form takes a typed address, so it is always possible.
        ShareRoute.server,
      );
    });
  });

  group('the routes offered', () {
    test('leaves out what the machine cannot do, rather than greying it', () {
      final offers = buildShareRouteOffers(
        canRunLocal: false,
        needsModel: false,
        keyProviders: const [],
        backends: const [],
      );
      expect(offers.map((offer) => offer.route), [ShareRoute.server]);
    });

    test('says an engine is running only when it is', () {
      String lineFor(bool running) => buildShareRouteOffers(
        canRunLocal: false,
        needsModel: false,
        keyProviders: const [],
        backends: [_ollama(running: running)],
      ).last.line;
      expect(lineFor(true), contains('is running here'));
      expect(lineFor(false), contains('is installed here'));
      // Telling somebody to start what is already up sends them looking for a
      // button that is not there.
      expect(lineFor(true), isNot(contains('Start it')));
    });

    test('names the providers the CLI actually whitelists', () {
      final offers = buildShareRouteOffers(
        canRunLocal: false,
        needsModel: false,
        keyProviders: const ['OpenAI', 'Anthropic'],
        backends: const [],
      );
      expect(offers.first.line, contains('OpenAI or Anthropic'));
    });

    test('a machine with the engine but no model still gets the route', () {
      final offers = buildShareRouteOffers(
        canRunLocal: true,
        needsModel: true,
        keyProviders: const [],
        backends: const [],
      );
      expect(offers.first.route, ShareRoute.local);
      // One download is a step on the route, not a reason to hide it.
      expect(offers.first.line, contains('Downloads a model first'));
    });

    test('counts only external engines, so the pane can name the number', () {
      final offers = buildShareRouteOffers(
        canRunLocal: false,
        needsModel: false,
        keyProviders: const [],
        backends: [
          _ollama(),
          const DetectedBackend(
            kind: BackendKind.llamaCpp,
            label: 'llama.cpp (grid)',
            baseUrl: '',
          ),
        ],
      );
      expect(offers.last.detected, 1);
    });
  });

  group('the models on disk', () {
    test('a split set is one model, at its full size', () {
      final models = groupLocalModels({
        'MiniMax-M3-UD-IQ3_XXS-00001-of-00003.gguf': 3,
        'MiniMax-M3-UD-IQ3_XXS-00002-of-00003.gguf': 4,
        'MiniMax-M3-UD-IQ3_XXS-00003-of-00003.gguf': 5,
      });
      expect(models, hasLength(1));
      expect(models.single.sizeBytes, 12);
      expect(models.single.parts, 3);
      expect(models.single.expectedParts, 3);
      expect(models.single.isComplete, isTrue);
      // llama.cpp is pointed at the first shard and finds the rest itself.
      expect(models.single.file, endsWith('-00001-of-00003.gguf'));
    });

    test('a set missing a shard is offered, but not as ready', () {
      final models = groupLocalModels({
        'Big-Q4_K_M-00001-of-00005.gguf': 1,
        'Big-Q4_K_M-00002-of-00005.gguf': 1,
      });
      expect(models.single.isComplete, isFalse);
      expect(models.single.parts, 2);
      expect(models.single.expectedParts, 5);
    });

    test('ignores anything that is not a gguf, and sorts by size', () {
      final models = groupLocalModels({
        'small.gguf': 1,
        'big.gguf': 9,
        'notes.txt': 100,
        'half.gguf.part': 50,
      });
      expect(models.map((model) => model.file), ['big.gguf', 'small.gguf']);
    });

    test('the advertised name drops the shard marker and the quant tag', () {
      expect(
        deriveAdvertiseName('Qwen3.6-35B-A3B-UD-IQ3_S.gguf'),
        'Qwen3.6-35B-A3B',
      );
      expect(
        deriveAdvertiseName('MiniMax-M3-UD-IQ3_XXS-00001-of-00005.gguf'),
        'MiniMax-M3',
      );
      expect(deriveAdvertiseName('/a/b/plain.gguf'), 'plain');
      // Nothing recognisable to strip leaves a usable name rather than nothing.
      expect(deriveAdvertiseName('Q4_K_M.gguf'), 'Q4_K_M');
    });

    test('sizes read the way a download does', () {
      expect(modelSizeLabel(900000000), '900 MB');
      expect(modelSizeLabel(15000000000), '15 GB');
      expect(modelSizeLabel(4500000000), '4.5 GB');
    });
  });

  group('the join command', () {
    test('the local engine gets a port we picked, not the CLI default', () {
      final args = localJoinArgs(
        gridId: _grid,
        modelFile: 'model.gguf',
        endpointPort: 51234,
        nodeName: 'MacBookPro2021',
        advertiseAs: 'Qwen3.6',
        contextSize: 204800,
      );
      expect(args, [
        'join', _grid,
        '--serve', 'model.gguf',
        '--endpoint-port', '51234',
        '--advertise-as', 'Qwen3.6',
        '--ctx-size', '204800',
        '--name', 'MacBookPro2021',
      ]);
    });

    test('an unknown context window is omitted, never defaulted', () {
      // With no --ctx-size the node advertises no window at all, and the grid's
      // router treats that as unknown rather than trusting a made-up number.
      expect(
        externalJoinArgs(
          gridId: _grid,
          endpoint: 'http://localhost:11434/v1',
          model: 'qwen3',
          nodeName: 'mac',
        ),
        isNot(contains('--ctx-size')),
      );
    });

    test('a blank advertise name is left off, not sent empty', () {
      expect(
        localJoinArgs(
          gridId: _grid,
          modelFile: 'm.gguf',
          endpointPort: 1,
          nodeName: 'mac',
          advertiseAs: '   ',
        ),
        isNot(contains('--advertise-as')),
      );
    });

    test('an API join never carries the key — argv is world-readable', () {
      final args = apiJoinArgs(
        gridId: _grid,
        kind: 'openai',
        nodeName: 'mac',
        models: const ['openai:gpt-5.5', 'openai:gpt-5.4'],
      );
      expect(args.join(' '), isNot(contains('sk-')));
      expect(args, containsAllInOrder(['-m', 'openai:gpt-5.5']));
      expect(args, containsAllInOrder(['-m', 'openai:gpt-5.4']));
      // No aliasing or window for an API engine: the CLI refuses one and the
      // vendor owns the other.
      expect(args, isNot(contains('--advertise-as')));
      expect(args, isNot(contains('--ctx-size')));
    });

    test('leaving without a selector leaves the lot', () {
      expect(leaveArgs(gridId: _grid), ['leave', _grid]);
      expect(leaveArgs(gridId: _grid, selector: ''), ['leave', _grid]);
      expect(leaveArgs(gridId: _grid, selector: 'm.gguf'), [
        'leave', _grid, '--engine', 'm.gguf',
      ]);
    });
  });

  group("this computer's name", () {
    test('drops .local and keeps a name a file can be called', () {
      expect(deriveNodeName('MacBookPro2021.local'), 'MacBookPro2021');
      expect(deriveNodeName("Dev's Mac (2)"), 'Dev-s-Mac-2');
    });

    test('never empty — the CLI would replace one with a random id', () {
      expect(deriveNodeName('   '), fallbackNodeName);
      expect(deriveNodeName('---'), fallbackNodeName);
    });
  });

  group('the run record', () {
    test('reads the union, per engine', () {
      final record = EngineRunRecord.fromJson({
        'engine_id': 'remote',
        'grid_id': _grid,
        'pid': 4242,
        'endpoint_port': 51234,
        'models': ['Qwen3.6', 'openai:gpt-5.5'],
        'engines': [
          {'models': ['Qwen3.6']},
          {'models': ['openai:gpt-5.5'], 'api_kind': 'openai'},
        ],
      });
      expect(record.pid, 4242);
      expect(record.endpointPort, 51234);
      expect(record.engines.map((spec) => spec.kind), [
        EngineKind.local,
        EngineKind.api,
      ]);
      expect(record.engines.first.leaveSelector, 'Qwen3.6');
    });

    test('an external engine is matched on its endpoint, not its model', () {
      final spec = EngineSpec.fromJson({
        'models': ['qwen3'],
        'endpoint_url': 'http://localhost:11434/v1',
      });
      expect(spec.kind, EngineKind.external);
      expect(spec.leaveSelector, 'http://localhost:11434/v1');
    });

    test('a record written before engines[] still lists as one engine', () {
      final record = EngineRunRecord.fromJson({
        'engine_id': 'remote',
        'grid_id': _grid,
        'models': ['Qwen3.6'],
      });
      expect(record.engines, hasLength(1));
      expect(record.engines.single.models, ['Qwen3.6']);
      expect(record.pid, isNull);
    });

    test('picks the record whose process answers, not the first on disk', () {
      final dead = EngineRunRecord.fromJson({'pid': 1, 'models': <String>[]});
      final live = EngineRunRecord.fromJson({'pid': 2, 'models': <String>[]});
      expect(
        firstLiveRun([dead, live], isAlive: (pid) => pid == 2),
        same(live),
      );
      expect(firstLiveRun([dead], isAlive: (_) => false), isNull);
    });

    test('a record we cannot check reads as alive, not as stopped', () {
      // Believing a dead engine is alive costs one harmless `grid leave`;
      // believing a live one is dead invites a second join on top of it.
      expect(pidIsAlive(null), isTrue);
    });

    test('a missing run directory is a computer that is not sharing', () {
      final missing = Directory('${Directory.systemTemp.path}/no-such-grid-dir');
      expect(readEngineRuns(_grid, runDir: missing), isEmpty);
    });
  });

  group('the context window', () {
    test('defaults to 200k, or the model when it holds less', () {
      expect(defaultContextLength(262144), 204800);
      expect(defaultContextLength(40960), 40960);
    });

    test('a dragged value always lands on a clean 1k', () {
      expect(snapContextLength(200123, 262144), 199680);
      expect(formatContextLength(snapContextLength(200123, 262144)), '195k');
      expect(snapContextLength(1, 262144), minContextTokens);
      expect(snapContextLength(999999, 262144), 262144);
    });

    test('labels the way the reader would write it', () {
      expect(formatContextLength(4096), '4k');
      expect(formatContextLength(204800), '200k');
      expect(formatContextLength(262144), '256k');
      expect(formatContextLength(1048576), '1M');
      expect(formatContextLength(1572864), '1.5M');
    });
  });
}

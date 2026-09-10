// Asking someone else's server what it serves, before joining it to a grid.
//
// Ported from the Grid app (`autonomous-grid-app`, commit `2742acea`) along
// with the two logic files it covers. The bug it closes is worth restating,
// because every assertion here is shaped by it: an address missing `/v1` used
// to join perfectly happily. The node went green, the model appeared in the
// list, and every message after that failed — twice over, since the capability
// probe travels the same address, so the node also registered as supporting no
// tools and no vision and the router refused chat before a request was made.
// One wrong address, two unrelated-looking errors two minutes apart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harness/share/engine_endpoint.dart';
import 'package:harness/share/engine_reachability.dart';
import 'package:harness/share/grid_cli.dart';
import 'package:harness/share/share_controller.dart';
import 'package:harness/share/share_discovery.dart';
import 'package:harness/share/widgets/serve_server_form.dart';
import 'package:harness/share/widgets/share_form_parts.dart';

class _Cli extends GridCli {
  _Cli() : super(environment: const {});

  @override
  Future<String?> locate() async => '/usr/local/bin/grid';

  @override
  Future<T?> runJson<T>(List<String> arguments) async => null;
}

ShareCapabilities get _caps => const ShareCapabilities(
  cliInstalled: true,
  engineInstalled: true,
  models: [],
  backends: [],
  keyProviders: [],
);

/// An OpenAI `/models` body from vLLM — the one engine that states the window
/// it was actually launched with.
String _vllmBody(List<String> ids, {int? maxLen}) =>
    '{"data":[${ids.map((id) => '{"id":"$id"'
        '${maxLen == null ? '' : ',"max_model_len":$maxLen'}}').join(',')}]}';

void main() {
  group('readEngineAddress', () {
    String? baseOf(String raw) => switch (readEngineAddress(raw)) {
      EngineAddressReady(:final base) => base,
      _ => null,
    };

    test('a full chat endpoint loses its path', () {
      expect(
        baseOf('http://localhost:8080/v1/chat/completions'),
        'http://localhost:8080/v1',
      );
    });

    test('/chat/completions is cut before /completions is considered', () {
      // Order is the whole trick. Cutting `/completions` first leaves
      // `…/v1/chat` — an address that looks plausible and answers nothing.
      expect(
        baseOf('http://x.dev/v1/chat/completions'),
        isNot(endsWith('/chat')),
      );
    });

    test('the other three OpenAI endpoints are cut too', () {
      for (final path in ['/completions', '/embeddings', '/responses']) {
        expect(baseOf('http://x.dev/v1$path'), 'http://x.dev/v1');
      }
    });

    test('trailing slashes go, before and after the cut', () {
      expect(baseOf('http://x.dev/v1///'), 'http://x.dev/v1');
      expect(baseOf('http://x.dev/v1/chat/completions/'), 'http://x.dev/v1');
    });

    test('an endpoint in the middle of the path is left alone', () {
      // Only a TRAILING endpoint is a paste that took too much; one in the
      // middle is somebody's real routing.
      expect(
        baseOf('http://x.dev/completions/v1'),
        'http://x.dev/completions/v1',
      );
    });

    test('the surviving path keeps the exact case it was typed in', () {
      // A path may well be case-sensitive on the far side, and this function is
      // not in the business of rewriting one.
      expect(
        baseOf('http://x.dev/MyApi/V1/Chat/Completions'),
        'http://x.dev/MyApi/V1',
      );
    });

    test('a missing /v1 is left missing, never repaired', () {
      // The invariant: what gets tested is what gets called. Adding `/v1` here
      // would let the check pass against a URL the join never uses, and the
      // join would fail exactly as before — now wearing a green tick.
      expect(baseOf('http://localhost:8080'), 'http://localhost:8080');
    });

    test('a bare host:port is refused rather than quietly repaired', () {
      // `Uri.parse` reads `localhost:8080/v1` as scheme `localhost`, and the
      // request then dies as an unnamed transport error.
      final address = readEngineAddress('localhost:8080/v1');
      expect(address, isA<EngineAddressRejected>());
      expect((address as EngineAddressRejected).message, contains('http://'));
    });

    test('the scheme is recognised in any casing, http or https', () {
      expect(baseOf('HTTPS://x.dev/v1'), 'HTTPS://x.dev/v1');
      expect(baseOf('https://x.dev/v1'), 'https://x.dev/v1');
    });

    test('a query or fragment is refused, not stapled over', () {
      // Neither can survive having `/models` appended, and both are always a
      // paste that took too much with it.
      for (final raw in ['http://x.dev/v1?key=1', 'http://x.dev/v1#top']) {
        expect(readEngineAddress(raw), isA<EngineAddressRejected>());
      }
    });

    test('an address with no server name in it is refused', () {
      expect(readEngineAddress('http:///v1'), isA<EngineAddressRejected>());
    });

    test('a blank field is not an error', () {
      // Red before the first keystroke reads as the app being broken.
      expect(readEngineAddress('   '), isA<EngineAddressEmpty>());
    });

    test('the check calls /models on the base that will be joined', () {
      final address = readEngineAddress(
        'http://localhost:8080/v1/chat/completions',
      ) as EngineAddressReady;
      expect(address.modelsUrl, 'http://localhost:8080/v1/models');
      expect(address.chatUrl, 'http://localhost:8080/v1/chat/completions');
    });

    test('a base missing /v1 builds the URL that will 404', () {
      // Stated as a test because it is the behaviour, not an oversight.
      final address =
          readEngineAddress('http://localhost:8080') as EngineAddressReady;
      expect(address.modelsUrl, 'http://localhost:8080/models');
    });
  });

  group('modelIdsFrom', () {
    test('the OpenAI shape every one of them serves', () {
      expect(modelIdsFrom(_vllmBody(['a', 'b'])), ['a', 'b']);
    });

    test('ids keep their exact case', () {
      expect(modelIdsFrom(_vllmBody(['Qwen/Qwen3-27B'])), ['Qwen/Qwen3-27B']);
    });

    test('a duplicate id is listed once', () {
      expect(modelIdsFrom(_vllmBody(['a', 'a'])), ['a']);
    });

    test('a body it cannot read yields no names rather than throwing', () {
      // The server answered, so the address is good; a parse quibble is not a
      // reason to refuse the join.
      for (final body in ['not json', '[]', '{"data":"nope"}', '']) {
        expect(modelIdsFrom(body), isEmpty);
      }
    });

    test('an entry with no usable name is skipped, not counted', () {
      expect(modelIdsFrom('{"data":[{"object":"model"},{"id":"a"}]}'), ['a']);
    });

    test('a native `models` envelope is accepted too', () {
      expect(modelIdsFrom('{"models":[{"name":"llama3"}]}'), ['llama3']);
    });
  });

  group('engineFrom', () {
    test('vLLM is known by max_model_len', () {
      expect(engineFrom(_vllmBody(['a'], maxLen: 8192)), ProbedEngine.vllm);
    });

    test('llama.cpp is known by its meta block', () {
      expect(
        engineFrom('{"data":[{"id":"a","meta":{"n_ctx_train":4096}}]}'),
        ProbedEngine.llamaCpp,
      );
    });

    test('Ollama is known by owned_by', () {
      expect(
        engineFrom('{"data":[{"id":"a","owned_by":"library"}]}'),
        ProbedEngine.ollama,
      );
    });

    test('a structural marker beats an owned_by string', () {
      // A field somebody had a reason to add is harder to coincide with.
      expect(
        engineFrom(
          '{"data":[{"id":"a","max_model_len":8,"owned_by":"library"}]}',
        ),
        ProbedEngine.vllm,
      );
    });

    test('any other OpenAI-compatible server is unknown, not an error', () {
      expect(engineFrom(_vllmBody(['a'])), ProbedEngine.unknown);
      expect(engineFrom('garbage'), ProbedEngine.unknown);
    });
  });

  group('servedContextFrom', () {
    test('vLLM says what it was launched with, and that is taken', () {
      expect(servedContextFrom(_vllmBody(['a'], maxLen: 32768)), 32768);
    });

    test("llama.cpp's trained window is deliberately NOT taken", () {
      // `n_ctx_train` is the window the MODEL was trained at, not the one
      // `llama-server` was started with. A 128k model served at 8192 would
      // advertise 128k, and the router picks nodes on that number.
      expect(
        servedContextFrom(
          '{"data":[{"id":"a","meta":{"n_ctx_train":131072}}]}',
        ),
        isNull,
      );
    });

    test('a server that says nothing leaves it unknown', () {
      expect(servedContextFrom(_vllmBody(['a'])), isNull);
    });

    test('a nonsense window is ignored rather than passed on', () {
      expect(servedContextFrom('{"data":[{"max_model_len":0}]}'), isNull);
      expect(servedContextFrom('{"data":[{"max_model_len":"soon"}]}'), isNull);
    });

    test('a window sent as a string is still read', () {
      expect(servedContextFrom('{"data":[{"max_model_len":"4096"}]}'), 4096);
    });
  });

  group('probeEngine', () {
    EngineAddressReady address() =>
        readEngineAddress('http://localhost:8080/v1') as EngineAddressReady;

    test('a 200 with a recognised body offers its models', () async {
      final reach = await probeEngine(
        address(),
        fetch: (_) async => (200, _vllmBody(['a', 'b'], maxLen: 8192)),
      );
      expect(reach, isA<EngineReachable>());
      final reachable = reach as EngineReachable;
      expect(reachable.models, ['a', 'b']);
      expect(reachable.contextLength, 8192);
      expect(reachable.canOfferModels, isTrue);
    });

    test('an unrecognised engine keeps the text field', () async {
      // It may still have handed over a usable list — but a picker built from a
      // body nobody recognised might be listing the wrong thing, and a wrong
      // pick is harder to notice than a name typed by hand.
      final reach = await probeEngine(
        address(),
        fetch: (_) async => (200, _vllmBody(['a'])),
      ) as EngineReachable;
      expect(reach.models, ['a']);
      expect(reach.canOfferModels, isFalse);
    });

    test('a recognised engine that listed nothing keeps the text field', () {
      const reach = EngineReachable([], ProbedEngine.vllm);
      expect(reach.canOfferModels, isFalse);
    });

    test('a non-200 names the URL, and only suggests /v1', () async {
      // A 404 here is usually a missing `/v1` — but not always, and telling
      // someone whose server really does sit at the root to add it sends them
      // to fix a thing that was never wrong.
      final reach = await probeEngine(
        address(),
        fetch: (_) async => (404, 'Not Found'),
      );
      final message = (reach as EngineUnreachable).message;
      expect(message, contains('http://localhost:8080/v1/models'));
      expect(message, contains('404'));
      expect(message, contains('Many servers need /v1'));
    });

    test(
      'a transport failure names the URL that was actually called',
      () async {
        // Nothing server-side records it, so support has had nothing to ask but
        // "what did you type?".
        final reach = await probeEngine(
          address(),
          fetch: (_) async => throw const SocketExceptionStub(),
        );
        expect(
          (reach as EngineUnreachable).message,
          contains('http://localhost:8080/v1/models'),
        );
      },
    );

    test('it asks the base, never the raw text', () async {
      String? asked;
      await probeEngine(
        readEngineAddress('http://localhost:8080/v1/chat/completions/')
            as EngineAddressReady,
        fetch: (url) async {
          asked = url;
          return (200, _vllmBody(['a']));
        },
      );
      expect(asked, 'http://localhost:8080/v1/models');
    });
  });

  group('the form asks before it joins', () {
    Future<ShareController> pump(
      WidgetTester tester, {
      required EngineFetch fetch,
    }) async {
      final controller = ShareController(cli: _Cli(), readRuns: (_) => const [])
        ..bindGridForTest('grid-1', _caps);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 860,
              child: SingleChildScrollView(
                child: ServeServerForm(
                  controller: controller,
                  gridName: 'autonomous.ai',
                  fetch: fetch,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    Future<void> type(WidgetTester tester, String address) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('server-endpoint-field')),
          matching: find.byType(TextField),
        ),
        address,
      );
      // Past the typing pause, then let the answer land.
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
    }

    testWidgets('a bare host:port is refused under the field', (tester) async {
      await pump(tester, fetch: (_) async => fail('nothing to ask yet'));
      await type(tester, 'localhost:8080/v1');

      expect(
        find.text('Start the address with http:// or https://'),
        findsWidgets,
      );
    });

    testWidgets('a reachable server echoes the URL the grid will call', (
      tester,
    ) async {
      await pump(
        tester,
        fetch: (_) async => (200, _vllmBody(['qwen3'], maxLen: 32768)),
      );
      await type(tester, 'http://localhost:8080/v1');

      // The line a person can compare against the curl in their own server's
      // docs — the one place a missing `/v1` becomes obvious.
      expect(
        find.text(
          'The grid will call http://localhost:8080/v1/chat/completions',
        ),
        findsOneWidget,
      );
      // One model is not a choice, it is the answer.
      expect(find.text('qwen3'), findsWidgets);
    });

    testWidgets('a 404 blocks Start and says which URL answered it', (
      tester,
    ) async {
      await pump(tester, fetch: (_) async => (404, 'Not Found'));
      await type(tester, 'http://localhost:8080');

      expect(
        find.textContaining('http://localhost:8080/models answered 404'),
        findsOneWidget,
      );
      // The button's own line stays short — the detail is already under the
      // field, and saying it twice on one screen is not clearer.
      expect(find.text("The grid couldn't reach that server."), findsOneWidget);
    });

    testWidgets('an unreachable address leaves Start dead', (tester) async {
      // The fail-closed half: `grid join --at` would take this address happily,
      // and the node it registered would fail every message while looking
      // healthy. Asserted on the callback rather than by tapping — the button
      // sits below a 600px test viewport, so a tap that "did nothing" would
      // pass whether or not the guard existed.
      await pump(tester, fetch: (_) async => (404, 'Not Found'));
      await type(tester, 'http://localhost:9999/v1');

      expect(tester.widget<StartRow>(find.byType(StartRow)).onPressed, isNull);
    });

    testWidgets('a reachable server with a model makes Start live', (
      tester,
    ) async {
      // The other side of the same guard: it has to let a good address through.
      await pump(
        tester,
        fetch: (_) async => (200, _vllmBody(['qwen3'], maxLen: 8192)),
      );
      await type(tester, 'http://localhost:8080/v1');

      expect(
        tester.widget<StartRow>(find.byType(StartRow)).onPressed,
        isNotNull,
      );
    });

    testWidgets('a server that states its window caps the ladder', (
      tester,
    ) async {
      // The app used to send a flat window for every external engine. The
      // router picks nodes on that number, so an inflated one wins work it
      // then cannot do.
      await pump(
        tester,
        fetch: (_) async => (200, _vllmBody(['qwen3'], maxLen: 32768)),
      );
      await type(tester, 'http://localhost:8080/v1');

      expect(
        find.textContaining('This server reports it serves'),
        findsOneWidget,
      );
    });
  });
}

/// Stands in for a socket failure without importing `dart:io` into a test that
/// otherwise needs none of it.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}

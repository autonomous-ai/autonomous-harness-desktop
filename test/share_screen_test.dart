import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/grid/grid_selection_store.dart';
import 'package:harness/share/backend_detector.dart';
import 'package:harness/share/grid_cli.dart';
import 'package:harness/share/share_route.dart';
import 'package:harness/share/widgets/share_rail.dart';
import 'package:harness/share/widgets/share_pane.dart';
import 'package:harness/share/share_controller.dart';

/// An in-memory store, so a test never touches `~/.harness`.
class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// A CLI that is not installed, which is what a test machine has.
class _AbsentCli extends GridCli {
  _AbsentCli() : super(environment: const {});

  @override
  Future<String?> locate() async => null;
}

Widget _app(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('with no grid chosen it says so instead of a broken form', (
    tester,
  ) async {
    final selection = GridSelectionStore(storage: _MemoryStore());
    await tester.pumpWidget(
      _app(SharePane(selection: selection, cli: _AbsentCli())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pick a grid first.'), findsOneWidget);
  });

  testWidgets('without the Grid CLI it explains, rather than offering forms', (
    tester,
  ) async {
    final selection = GridSelectionStore(storage: _MemoryStore());
    await selection.selectNetwork(
      networkId: 'grid-3378218621364f16',
      networkName: 'autonomous.ai',
    );
    await tester.pumpWidget(
      _app(SharePane(selection: selection, cli: _AbsentCli())),
    );
    await tester.pumpAndSettle();

    expect(find.text('The Grid CLI is not on this computer.'), findsOneWidget);
    expect(find.text('Start sharing'), findsNothing);
  });

  testWidgets('the rail names the grid and offers only what is possible', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SizedBox(
            // The viewport a widget test runs in, so the rail is exercised at
            // the height it actually has to scroll inside.
            width: 396,
            height: 600,
            child: ShareRail(
              gridName: 'autonomous.ai',
              offers: buildShareRouteOffers(
                canRunLocal: true,
                needsModel: false,
                keyProviders: const ['OpenAI'],
                backends: const [
                  DetectedBackend(
                    kind: BackendKind.ollama,
                    label: 'Ollama',
                    baseUrl: BackendDetector.ollamaBase,
                    running: false,
                  ),
                ],
              ),
              route: ShareRoute.local,
              status: ShareStatus.idle,
              onPick: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Put this computer\nto work.'), findsOneWidget);
    expect(find.textContaining('autonomous.ai'), findsOneWidget);
    expect(find.text('Not sharing yet'), findsOneWidget);
    expect(find.text('CHOOSE A ROUTE'), findsOneWidget);
    expect(find.text('Run a local model'), findsOneWidget);
    expect(find.text('Share frontier models via your API key'), findsOneWidget);
    expect(find.text('Start an engine you already have'), findsOneWidget);
    // Ollama is installed but not answering, and the card must say which.
    expect(find.textContaining('is installed here'), findsOneWidget);
  });

  testWidgets('a live share never claims the app is holding it up', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: SizedBox(
            // The viewport a widget test runs in, so the rail is exercised at
            // the height it actually has to scroll inside.
            width: 396,
            height: 600,
            child: ShareRail(
              gridName: 'autonomous.ai',
              offers: buildShareRouteOffers(
                canRunLocal: true,
                needsModel: false,
                keyProviders: const [],
                backends: const [],
              ),
              route: ShareRoute.local,
              status: ShareStatus.live,
              onPick: (_) => fail('a route cannot be picked while sharing'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('WAYS TO SHARE'), findsOneWidget);
    expect(find.text('Sharing'), findsOneWidget);
    // The footnote is the one place this page could tell a costly lie: the
    // engine is detached, so closing Harness does NOT stop it.
    expect(
      find.textContaining('closing Harness does not stop it'),
      findsOneWidget,
    );
    // The cards stay on screen and stop responding — removing them would take
    // away the only place that says what the alternatives were. Scrolled to
    // first: the rail is a scrolling column, and a tap at an offset outside
    // the viewport proves nothing about whether the card responds.
    final third = find.text('Start an engine you already have');
    await tester.ensureVisible(third);
    await tester.pumpAndSettle();
    await tester.tap(third);
    await tester.pump();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/grid_api_client.dart';
import 'package:harness/share/backend_detector.dart';
import 'package:harness/share/catalog_models.dart';
import 'package:harness/share/grid_cli.dart';
import 'package:harness/share/local_models.dart';
import 'package:harness/share/model_manager_controller.dart';
import 'package:harness/share/model_pull.dart';
import 'package:harness/share/recommended_models.dart';
import 'package:harness/share/share_controller.dart';
import 'package:harness/share/share_discovery.dart';
import 'package:harness/share/widgets/model_manager_panels.dart';
import 'package:harness/share/api_providers.dart';
import 'package:harness/share/widgets/share_fields.dart';
import 'package:harness/shared/theme/share_page_theme.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/share/widgets/serve_key_form.dart';
import 'package:harness/share/widgets/serve_local_form.dart';
import 'package:harness/share/widgets/serve_server_form.dart';

class _Cli extends GridCli {
  _Cli() : super(environment: const {});
  @override
  Future<String?> locate() async => '/usr/local/bin/grid';
  @override
  Future<T?> runJson<T>(List<String> arguments) async => null;
}

class _Api extends GridApiClient {
  @override
  Future<List<CatalogEntry>> catalog({
    String? sort,
    String? query,
    int pageSize = 50,
  }) async => const [];

  @override
  Future<ModelDetail> catalogDetail(
    String repoId, {
    Map<String, dynamic>? device,
  }) async => const ModelDetail(
    repoId: 'org/model-GGUF',
    versions: [
      ModelVersion(
        version: 'BF16',
        sizeBytes: 71100000000,
        pullSpec: 'org/model-GGUF:BF16.gguf',
        urls: [],
        status: VersionStatus.tooLarge,
      ),
      ModelVersion(
        version: 'Q4_K_M',
        sizeBytes: 22200000000,
        pullSpec: 'org/model-GGUF:Q4_K_M.gguf',
        urls: [],
        status: VersionStatus.runnable,
      ),
    ],
  );
}

/// Picks that are already loaded, so a form's empty state can be pumped without
/// spawning the CLI or reaching the shelf.
class _Picks extends RecommendedModelsController {
  _Picks(this.loaded, {this.machineLine}) : super(cli: _Cli(), api: _Api());

  final List<RecommendedPick> loaded;
  final String? machineLine;

  @override
  Future<void> load() async {
    picks = loaded;
    machine = machineLine;
    notifyListeners();
  }
}

ShareCapabilities _caps({
  DetectedBackend? backend,
  List<LocalModel> models = const [],
}) => ShareCapabilities(
  cliInstalled: true,
  engineInstalled: true,
  models: models,
  backends: backend == null ? const [] : [backend],
  keyProviders: const [],
);

Future<ShareController> _pumpServerForm(
  WidgetTester tester, {
  DetectedBackend? backend,
}) async {
  final controller = ShareController(cli: _Cli(), readRuns: (_) => const [])
    ..bindGridForTest('grid-1', _caps(backend: backend));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 860,
          child: SingleChildScrollView(
            child: ServeServerForm(
              controller: controller,
              gridName: 'autonomous.ai',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  group('the page brings its own controls', () {
    testWidgets("a field does not wear the app's global decoration", (
      tester,
    ) async {
      final controller = TextEditingController(text: 'MacBooks-MacBook-Pro');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          // The app's real theme, which is the whole point: its
          // InputDecorationTheme sets filled:true with the app's own surface
          // and a minHeight for a 32px control. A field that draws its own skin
          // has to switch that off, or it renders a second lighter box behind
          // its text, in the wrong grey, sitting off-centre in the box this
          // page drew. That shipped once and is visible in every screenshot of
          // the pane taken before this test existed.
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: ShareTextField(controller: controller, hint: 'name'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.filled, isFalse);
      expect(field.decoration!.isCollapsed, isTrue);
      // The box is the page's, and it is the same height as every button on it.
      expect(
        tester.getSize(find.byType(ShareFieldSkin)).height,
        ShareMetrics.controlHeight,
      );
    });

    testWidgets('a field says when the keyboard is on it', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 260,
                child: ShareTextField(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      BoxDecoration skin() =>
          tester
                  .widgetList<Container>(find.byType(Container))
                  .firstWhere((c) => c.decoration is BoxDecoration)
                  .decoration!
              as BoxDecoration;
      expect(skin().boxShadow, anyOf(isNull, isEmpty));

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      // macOS rings the focused control; this page had no focus state at all.
      expect(skin().boxShadow, isNotEmpty);
      expect((skin().border! as Border).top.color, SharePalette.fieldRimFocus);
    });
  });

  group('every route is the same three steps', () {
    testWidgets('the local route names them, and locks the last one', (
      tester,
    ) async {
      final controller = ShareController(cli: _Cli(), readRuns: (_) => const [])
        ..bindGridForTest('grid-1', _caps());
      final pull = ModelPullController(cli: _Cli());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 860,
              child: SingleChildScrollView(
                child: ServeLocalForm(
                  controller: controller,
                  pull: pull,
                  cli: _Cli(),
                  gridName: 'autonomous.ai',
                  recommended: _Picks(const []),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Route chosen'), findsOneWidget);
      expect(find.text('Get a model onto this disk'), findsOneWidget);
      // The step that follows the download stays on screen, greyed, so an
      // empty disk is a step of three rather than a blank pane.
      expect(find.text('Name it and start sharing'), findsOneWidget);
      expect(find.text('Opens once a model is on this disk.'), findsOneWidget);
      controller.dispose();
      pull.dispose();
    });

    testWidgets("a model on disk collapses step 2 and opens step 3", (
      tester,
    ) async {
      final controller = ShareController(cli: _Cli(), readRuns: (_) => const [])
        ..bindGridForTest(
          'grid-1',
          _caps(
            models: const [
              LocalModel(
                file: 'Qwen3-30B-UD-IQ4_XS.gguf',
                sizeBytes: 16500000000,
                parts: 1,
              ),
            ],
          ),
        );
      final pull = ModelPullController(cli: _Cli());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 860,
              child: SingleChildScrollView(
                child: ServeLocalForm(
                  controller: controller,
                  pull: pull,
                  cli: _Cli(),
                  gridName: 'autonomous.ai',
                  recommended: _Picks(const []),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 2 is answered, so it says the answer and offers a way back.
      expect(find.text('Model on this disk'), findsOneWidget);
      expect(find.text('Qwen3-30B-UD-IQ4_XS.gguf · 17 GB'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
      expect(find.text('Opens once a model is on this disk.'), findsNothing);
      // One button, with the same label as every other route.
      expect(find.text('Start sharing'), findsOneWidget);
      expect(
        find.text('Puts this Mac on autonomous.ai. You can stop at any time.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(find.text('Model'), findsOneWidget);
      controller.dispose();
      pull.dispose();
    });

    testWidgets('an empty disk is offered what this Mac can run', (
      tester,
    ) async {
      final controller = ShareController(cli: _Cli(), readRuns: (_) => const [])
        ..bindGridForTest('grid-1', _caps());
      final pull = ModelPullController(cli: _Cli());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 860,
              child: SingleChildScrollView(
                child: ServeLocalForm(
                  controller: controller,
                  pull: pull,
                  cli: _Cli(),
                  gridName: 'autonomous.ai',
                  recommended: _Picks(const [
                    RecommendedPick(
                      repoId: 'unsloth/Qwen3.6-35B-A3B-MTP-GGUF',
                      file: 'Qwen3.6-35B-A3B-UD-IQ3_S.gguf',
                      minVramGb: 32,
                      sizeBytes: 16500000000,
                      specs: ['unsloth/Qwen3.6-35B-A3B-MTP-GGUF:x.gguf'],
                    ),
                  ], machineLine: 'Apple M1 Pro · 32 GB memory · 572 GB free'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('PICKED FOR THIS MAC'), findsOneWidget);
      expect(find.text('Qwen3.6-35B-A3B-MTP'), findsOneWidget);
      // Every figure in the line is one the CLI or the shelf measured.
      expect(
        find.text('UD-IQ3_S · 17 GB on disk · needs 32 GB to run'),
        findsOneWidget,
      );
      expect(
        find.text('Apple M1 Pro · 32 GB memory · 572 GB free'),
        findsOneWidget,
      );
      expect(find.text('Browse the catalogue'), findsOneWidget);
      controller.dispose();
      pull.dispose();
    });
  });

  group('sharing an engine that is already here', () {
    testWidgets('a stopped engine is an option, not a second button', (
      tester,
    ) async {
      final controller = await _pumpServerForm(
        tester,
        backend: const DetectedBackend(
          kind: BackendKind.ollama,
          label: 'Ollama',
          baseUrl: BackendDetector.ollamaBase,
          running: false,
        ),
      );

      expect(find.text('Ollama'), findsOneWidget);
      expect(find.text('STOPPED'), findsOneWidget);
      // Two primaries on one pane is one too many: the launch happens on the
      // way through the one press every route ends with.
      expect(find.text('Launch & share'), findsNothing);
      expect(find.text('Start engine'), findsNothing);
      expect(find.text('Start sharing'), findsOneWidget);
      expect(
        find.text('Starts Ollama, then puts it on autonomous.ai.'),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('an engine already answering is not told to start again', (
      tester,
    ) async {
      final controller = await _pumpServerForm(
        tester,
        backend: const DetectedBackend(
          kind: BackendKind.ollama,
          label: 'Ollama',
          baseUrl: BackendDetector.ollamaBase,
          models: ['qwen3', 'llama3'],
        ),
      );

      expect(find.text('STOPPED'), findsNothing);
      expect(
        find.textContaining('Answering on this computer with 2 models.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Puts Ollama on autonomous.ai'),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('with nothing detected the typed fields stand alone', (
      tester,
    ) async {
      final controller = await _pumpServerForm(tester);

      expect(find.text('OR POINT AT ANOTHER ENDPOINT'), findsNothing);
      expect(find.text('Another endpoint'), findsNothing);
      expect(find.text('Endpoint'), findsOneWidget);
      expect(find.text('Model id'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('the helper names what is missing, not a general sentence', (
      tester,
    ) async {
      final controller = await _pumpServerForm(tester);

      expect(
        find.text('Add an endpoint and a model id to continue.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'http://localhost:8080/v1'),
        'http://localhost:8080/v1',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'The id the server answers to'),
        'qwen3',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Its models, quantization and flags are shared as they are.'),
        findsOneWidget,
      );
      controller.dispose();
    });
  });

  group('lending a key', () {
    const offer = KeyProviderOffer(
      provider: ApiProvider(
        kind: 'openai',
        label: 'OpenAI',
        envVar: 'OPENAI_API_KEY',
        keyHint: 'sk-…',
        keyHelpUrl: 'https://platform.openai.com/api-keys',
      ),
      models: [
        ApiModel(advertised: 'openai:gpt-5.5', vendorName: 'gpt-5.5'),
        ApiModel(advertised: 'openai:gpt-5.4', vendorName: 'gpt-5.4'),
      ],
    );

    Future<ShareController> pump(
      WidgetTester tester, {
      Set<String> stored = const {},
    }) async {
      final controller = ShareController(cli: _Cli(), readRuns: (_) => const [])
        ..bindGridForTest('grid-1', _caps());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 820,
              child: SingleChildScrollView(
                child: ServeKeyForm(
                  controller: controller,
                  offers: const [offer],
                  storedKinds: stored,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('every model is on offer until one is switched off', (
      tester,
    ) async {
      final controller = await pump(tester);

      // The count is the row of chips said in words, so nobody has to compare
      // four boxes by eye to find out what this key is offering.
      expect(
        find.text(
          'All 2 offered to the grid — OpenAI picks whichever fits the '
          'question.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('gpt-5.4'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '1 of 2 offered to the grid. Switch them all on to let OpenAI '
          'decide.',
        ),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('the key is hidden, and can be shown', (tester) async {
      final controller = await pump(tester);

      // The first field on the pane is the key; the second is this computer's
      // name, which this route used to send without ever showing.
      TextField field() =>
          tester.widget<TextField>(find.byType(TextField).first);
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show'));
      await tester.pumpAndSettle();
      expect(field().obscureText, isFalse);
      expect(find.text("This computer's name"), findsOneWidget);
      controller.dispose();
    });

    testWidgets('with no key stored it will not start, and says why', (
      tester,
    ) async {
      final controller = await pump(tester);

      expect(
        find.text('Enter a valid API key to start sharing cloud models.'),
        findsOneWidget,
      );
      expect(find.text('Start cloud engine'), findsNothing);
      expect(find.text('Start sharing'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      controller.dispose();
    });

    testWidgets('a key already on this computer is reused, and said so', (
      tester,
    ) async {
      final controller = await pump(tester, stored: const {'openai'});

      // Grid's own form cannot say this because it never looks at the file.
      expect(
        find.text('Reusing the OpenAI key already on this computer.'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      controller.dispose();
    });
  });

  group('the model manager', () {
    testWidgets('a version too large to run cannot be downloaded', (
      tester,
    ) async {
      final manager = ModelManagerController(cli: _Cli(), api: _Api());
      await manager.load();
      await manager.select('org/model-GGUF');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 560,
              height: 500,
              child: VersionPanel(
                manager: manager,
                busy: false,
                onDownload: (_, _) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Too large for memory'), findsOneWidget);
      expect(find.text('Runs on this Mac'), findsOneWidget);
      // Ten minutes and seventy gigabytes spent on something that cannot load
      // is the one outcome worth disabling a button for.
      final buttons = tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .toList();
      expect(buttons, hasLength(2));
      expect(buttons.first.onPressed, isNull);
      expect(buttons.last.onPressed, isNotNull);
      manager.dispose();
    });

    testWidgets('the specs a version downloads come from its urls', (
      tester,
    ) async {
      // One file when the catalogue names one; every shard when it is split.
      expect(
        versionSpecs(
          const ModelVersion(
            version: 'Q4',
            sizeBytes: 1,
            pullSpec: 'org/r:one.gguf',
            urls: [],
          ),
        ),
        ['org/r:one.gguf'],
      );
      expect(
        versionSpecs(
          const ModelVersion(
            version: 'Q4',
            sizeBytes: 1,
            pullSpec: 'org/r:a-00001-of-00002.gguf',
            urls: [
              'https://huggingface.co/org/r/resolve/main/a-00001-of-00002.gguf',
              'https://huggingface.co/org/r/resolve/main/a-00002-of-00002.gguf',
            ],
          ),
        ),
        hasLength(2),
      );
    });
  });
}

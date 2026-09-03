import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/grid_api_client.dart';
import 'package:harness/share/backend_detector.dart';
import 'package:harness/share/catalog_models.dart';
import 'package:harness/share/grid_cli.dart';
import 'package:harness/share/model_manager_controller.dart';
import 'package:harness/share/share_controller.dart';
import 'package:harness/share/share_discovery.dart';
import 'package:harness/share/widgets/model_manager_panels.dart';
import 'package:harness/share/api_providers.dart';
import 'package:harness/share/widgets/serve_key_form.dart';
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

ShareCapabilities _caps({DetectedBackend? backend}) => ShareCapabilities(
  cliInstalled: true,
  engineInstalled: true,
  models: const [],
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
            child: ServeServerForm(controller: controller),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  group('sharing an engine that is already here', () {
    testWidgets('a stopped engine is launched and shared in one press', (
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
      expect(find.text('Installed on this computer, not running yet.'), findsOneWidget);
      // Starting it and sharing it is one intention, not two.
      expect(find.text('Launch & share'), findsOneWidget);
      expect(find.text('Start Ollama'), findsNothing);
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

      expect(find.text('Share it'), findsOneWidget);
      expect(find.text('Launch & share'), findsNothing);
      expect(
        find.text('Answering on this computer with 2 models.'),
        findsOneWidget,
      );
      controller.dispose();
    });

    testWidgets('with nothing detected the typed half stands alone', (
      tester,
    ) async {
      final controller = await _pumpServerForm(tester);

      expect(find.text('OR POINT AT ANOTHER ENDPOINT'), findsNothing);
      expect(
        find.text('Endpoint, any OpenAI-compatible server'),
        findsOneWidget,
      );
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

      // The state is in the label, not only in the tint.
      expect(find.text('gpt-5.5 · on'), findsOneWidget);
      expect(find.text('gpt-5.4 · on'), findsOneWidget);

      await tester.tap(find.text('gpt-5.4 · on'));
      await tester.pumpAndSettle();
      expect(find.text('gpt-5.4 · off'), findsOneWidget);
      controller.dispose();
    });

    testWidgets('the key is hidden, and can be shown', (tester) async {
      final controller = await pump(tester);

      TextField field() => tester.widget<TextField>(find.byType(TextField));
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show'));
      await tester.pumpAndSettle();
      expect(field().obscureText, isFalse);
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
      expect(
        tester
            .widget<FilledButton>(find.byType(FilledButton))
            .onPressed,
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

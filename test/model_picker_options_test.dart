// The picker is a list of PROVIDERS with the models each one serves, so the
// states worth pinning are the ones a live account is hard to put in front of a
// person: a provider still answering, one that failed, one serving nothing, a
// search that matches a provider's name rather than a model's, and a keyboard
// walking rows past the headers between them.
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/grid/agent_grid.dart';
import 'package:harness/grid/grid_models_controller.dart';
import 'package:harness/grid/grid_selection_store.dart' show kNoGridTargetLabel;
import 'package:harness/grid/grid_network.dart';
import 'package:harness/grid/grid_networks_controller.dart';
import 'package:harness/grid/model_picker_options.dart';

GridNetwork _provider(String id, String name) =>
    GridNetwork.fromJson({'network_id': id, 'name': name});

final _office = _provider('grid-office', 'Office');
final _lab = _provider('grid-lab', 'Lab');

/// The models cache, as a lookup the builder can be handed.
GridModelsState Function(String) _served(Map<String, GridModelsState> states) =>
    (id) => states[id] ?? const GridModelsIdle();

List<String> _labels(List<ModelPickerItem> items) => [
  for (final item in items)
    switch (item) {
      ModelPickerHeader(:final title) => '# $title',
      ModelPickerNote(:final message) => '· $message',
      ModelPickerRow(:final label) => label,
    },
];

void main() {
  group('the list', () {
    test('opens with the one choice that needs no network call', () {
      // The no-provider row must not be one that appears once a fetch lands: it is
      // the only choice the app can offer with nothing loaded at all.
      final items = modelPickerItems(
        providers: const [],
        modelsOf: _served(const {}),
      );

      expect(_labels(items), [kNoGridTargetLabel]);
      expect((items.first as ModelPickerRow).choice, ModelChoice.none);
    });

    test('groups every provider over the models it serves', () {
      final items = modelPickerItems(
        providers: [_office, _lab],
        modelsOf: _served({
          _office.networkId: const GridModelsReady(['GLM-4.7-Flash']),
          _lab.networkId: const GridModelsReady(['Qwen3.8-27B']),
        }),
      );

      expect(_labels(items), [
        kNoGridTargetLabel,
        '# Office',
        'Auto',
        'GLM-4.7-Flash',
        '# Lab',
        'Auto',
        'Qwen3.8-27B',
      ]);
    });

    test('a model carries the provider that answers for it', () {
      // The pair IS the choice — an id alone does not say who serves it, and
      // the agent is retargeted at a relay.
      final items = modelPickerItems(
        providers: [_lab],
        modelsOf: _served({
          _lab.networkId: const GridModelsReady(['Qwen3.8-27B']),
        }),
      );

      final row = items.last as ModelPickerRow;
      expect(row.choice.networkId, _lab.networkId);
      expect(row.choice.networkName, 'Lab');
      expect(row.choice.model, 'Qwen3.8-27B');
    });

    test("the relay's virtual auto router is not offered beside the menu's own Auto", () {
      // Two rows reading the same word that send different things: this Auto
      // leaves ANTHROPIC_MODEL unset, the relay's would set it to `auto` and
      // leave the header printing the raw id back. Matched on modelKey, since
      // ids arrive from three sources that disagree on case.
      for (final id in ['auto', 'Auto', 'AUTO', ' auto ']) {
        final items = modelPickerItems(
          providers: [_office],
          modelsOf: _served({
            _office.networkId: GridModelsReady([id, 'GLM-4.7-Flash']),
          }),
        );

        expect(
          _labels(items).where((label) => label.toLowerCase() == 'auto').length,
          1,
          reason: 'relay advertised $id',
        );
      }
    });

    test('a provider serving only that router is not listed at all', () {
      // Auto with nothing to route to is a row that resolves to nothing, and a
      // name over one apology is not a choice — so the group goes with it.
      final items = modelPickerItems(
        providers: [_office],
        modelsOf: _served({
          _office.networkId: const GridModelsReady(['auto']),
        }),
      );

      expect(_labels(items), [kNoGridTargetLabel]);
    });

    test('one still answering, or failed, is not listed either', () {
      // On an account with four providers the panel WAS four names over four
      // apologies, none of them a thing anyone could pick. What is still
      // happening is said once, under the list — see the note group below.
      final items = modelPickerItems(
        providers: [_office, _lab],
        modelsOf: _served({
          _office.networkId: const GridModelsLoading(),
          _lab.networkId: const GridModelsFailed('The relay is unreachable.'),
        }),
      );

      expect(_labels(items), [kNoGridTargetLabel]);
    });

    test('the ones that DID answer are listed while the others load', () {
      final items = modelPickerItems(
        providers: [_office, _lab],
        modelsOf: _served({
          _office.networkId: const GridModelsLoading(),
          _lab.networkId: const GridModelsReady(['Qwen3.8-27B']),
        }),
      );

      expect(_labels(items), [
        kNoGridTargetLabel,
        '# Lab',
        'Auto',
        'Qwen3.8-27B',
      ]);
    });
  });

  group('searching', () {
    final models = _served({
      _office.networkId: const GridModelsReady([
        'GLM-4.7-Flash',
        'Qwen3.8-27B',
      ]),
      _lab.networkId: const GridModelsReady(['Qwen3.8-Flash-Next']),
    });

    test(
      'matches models across every provider, and drops the groups with none',
      () {
        final items = modelPickerItems(
          providers: [_office, _lab],
          modelsOf: models,
          query: 'glm',
        );

        expect(_labels(items), ['# Office', 'GLM-4.7-Flash']);
      },
    );

    test("a provider's own name brings its whole list", () {
      // Typing a provider is how you say "show me what this one has", and every
      // model under it is an answer to that.
      final items = modelPickerItems(
        providers: [_office, _lab],
        modelsOf: models,
        query: 'lab',
      );

      expect(_labels(items), ['# Lab', 'Auto', 'Qwen3.8-Flash-Next']);
    });

    test('nothing matching is an empty list, for the panel to speak to', () {
      expect(
        modelPickerItems(
          providers: [_office, _lab],
          modelsOf: models,
          query: 'gpt',
        ),
        isEmpty,
      );
    });

    test('a provider still loading matches nothing, name or otherwise', () {
      // It has no rows to offer, and a header alone is a group with nothing in
      // it.
      final items = modelPickerItems(
        providers: [_office],
        modelsOf: _served({_office.networkId: const GridModelsLoading()}),
        query: 'off',
      );

      expect(items, isEmpty);
    });
  });

  group('recents', () {
    test('sit at the top, named by the provider they came from', () {
      final items = modelPickerItems(
        providers: [_office, _lab],
        modelsOf: _served({
          _office.networkId: const GridModelsReady(['GLM-4.7-Flash']),
          _lab.networkId: const GridModelsReady(['Qwen3.8-27B']),
        }),
        recents: [
          ModelChoice(networkId: _lab.networkId, model: 'Qwen3.8-27B'),
          ModelChoice(networkId: _office.networkId),
        ],
      );

      expect(_labels(items).take(4), [
        kNoGridTargetLabel,
        '# Recent',
        'Qwen3.8-27B',
        'Auto',
      ]);
      expect((items[2] as ModelPickerRow).note, 'Lab');
      expect(
        (items[3] as ModelPickerRow).note,
        'Office',
        reason: 'the group header no longer says which provider a row is on',
      );
    });

    test('a renamed provider reads under the name it has now', () {
      // The name is rebuilt from the live list rather than replayed from disk.
      final renamed = _provider(_lab.networkId, 'Lab East');
      final items = modelPickerItems(
        providers: [renamed],
        modelsOf: _served({
          renamed.networkId: const GridModelsReady(['m1']),
        }),
        recents: [ModelChoice(networkId: renamed.networkId, model: 'm1')],
      );

      expect((items[2] as ModelPickerRow).note, 'Lab East');
      expect((items[2] as ModelPickerRow).choice.networkName, 'Lab East');
    });

    test('a pick on a provider this computer no longer offers is dropped', () {
      final items = modelPickerItems(
        providers: [_office],
        modelsOf: _served({
          _office.networkId: const GridModelsReady(['GLM-4.7-Flash']),
        }),
        recents: const [ModelChoice(networkId: 'grid-gone', model: 'ghost')],
      );

      expect(_labels(items), [
        kNoGridTargetLabel,
        '# Office',
        'Auto',
        'GLM-4.7-Flash',
      ]);
    });

    test('a search hides them rather than printing half the matches twice', () {
      final items = modelPickerItems(
        providers: [_office],
        modelsOf: _served({
          _office.networkId: const GridModelsReady(['GLM-4.7-Flash']),
        }),
        recents: [
          ModelChoice(networkId: _office.networkId, model: 'GLM-4.7-Flash'),
        ],
        query: 'glm',
      );

      expect(_labels(items), ['# Office', 'GLM-4.7-Flash']);
    });
  });

  group('walking the list with the keyboard', () {
    final items = modelPickerItems(
      providers: [_office, _lab],
      modelsOf: _served({
        _office.networkId: const GridModelsReady(['GLM-4.7-Flash']),
        _lab.networkId: const GridModelsLoading(),
      }),
    );

    test('lands only where Enter means something', () {
      // 0 no-provider · 1 # Office · 2 Auto · 3 GLM. The second provider is
      // still answering, so it contributes nothing to walk over.
      expect(firstPickableIndex(items), 0);
      expect(
        nextPickableIndex(items, 0, 1),
        2,
        reason: 'the header is skipped',
      );
      expect(nextPickableIndex(items, 2, -1), 0);
    });

    test('stops at the ends rather than wrapping', () {
      // A wrap in a scrolled list reads as the panel having jumped rather than
      // the selection having moved.
      expect(nextPickableIndex(items, 3, 1), 3);
      expect(nextPickableIndex(items, 0, -1), 0);
      expect(nextPickableIndex(const [], null, 1), isNull);
    });

    test('finds the row an agent is already on', () {
      expect(
        indexOfChoice(
          items,
          ModelChoice(networkId: _office.networkId, model: 'GLM-4.7-Flash'),
        ),
        3,
      );
      expect(indexOfChoice(items, ModelChoice.none), 0);
      expect(
        indexOfChoice(items, const ModelChoice(networkId: 'grid-gone')),
        isNull,
        reason: 'a provider not in the list has no row to tick',
      );
    });
  });

  group('where the agent is running now', () {
    test('no grid at all is a real, tickable choice', () {
      expect(currentModelChoice(null, [_office]), ModelChoice.none);
    });

    test('a relay resolves to the provider whose id it names', () {
      final choice = currentModelChoice(
        const AgentGrid(
          baseUrl: 'https://grid.autonomous.ai/grid-lab/relay/v1',
          model: 'Qwen3.8-27B',
        ),
        [_office, _lab],
      );

      expect(
        choice,
        ModelChoice(networkId: _lab.networkId, model: 'Qwen3.8-27B'),
      );
      expect(choice!.networkName, 'Lab');
    });

    test('a provider this account cannot name ticks nothing', () {
      // An agent can be on a grid belonging to another account entirely. Ticking
      // a row that is not where it is running would be worse than ticking none.
      expect(
        currentModelChoice(
          const AgentGrid(
            baseUrl: 'https://grid.autonomous.ai/grid-other/relay/v1',
          ),
          [_office, _lab],
        ),
        isNull,
      );
    });
  });

  group('the note under the list', () {
    test('says once that models are still coming, not once per provider', () {
      expect(
        modelPickerModelsNote(
          providers: [_office, _lab],
          modelsOf: _served({
            _office.networkId: const GridModelsLoading(),
            _lab.networkId: const GridModelsIdle(),
          }),
        ),
        'Loading models…',
      );
    });

    test('goes quiet once every provider has answered', () {
      expect(
        modelPickerModelsNote(
          providers: [_office, _lab],
          modelsOf: _served({
            _office.networkId: const GridModelsReady(['GLM-4.7-Flash']),
            _lab.networkId: const GridModelsReady(['Qwen3.8-27B']),
          }),
        ),
        isNull,
      );
    });

    test('a provider serving nothing is not something to wait for', () {
      // Neither pending nor broken — a grid with no models, and nothing here
      // for the reader to wait for or fix.
      expect(
        modelPickerModelsNote(
          providers: [_office],
          modelsOf: _served({
            _office.networkId: const GridModelsReady(['auto']),
          }),
        ),
        isNull,
      );
    });

    test('one failure is quoted, several are counted', () {
      expect(
        modelPickerModelsNote(
          providers: [_office],
          modelsOf: _served({
            _office.networkId: const GridModelsFailed(
              'The relay is unreachable.',
            ),
          }),
        ),
        'The relay is unreachable.',
        reason:
            'GridApiClient already turned it into a sentence with a way out',
      );
      expect(
        modelPickerModelsNote(
          providers: [_office, _lab],
          modelsOf: _served({
            _office.networkId: const GridModelsFailed('one'),
            _lab.networkId: const GridModelsFailed('two'),
          }),
        ),
        '2 providers could not be reached',
      );
    });

    test('a load still running outranks a failure', () {
      // The condition that resolves on its own comes first: a failure named
      // while a grid is still answering reads as a verdict on the whole list.
      expect(
        modelPickerModelsNote(
          providers: [_office, _lab],
          modelsOf: _served({
            _office.networkId: const GridModelsLoading(),
            _lab.networkId: const GridModelsFailed('nope'),
          }),
        ),
        'Loading models…',
      );
    });
  });

  group('the account-level note', () {
    // Shared with the sidebar's provider pill, so the two pickers cannot word
    // the same failure differently.
    test('speaks for every state but the one with providers in it', () {
      expect(providerLoadNote(const GridNetworksIdle()), 'Loading providers…');
      expect(
        providerLoadNote(const GridNetworksLoading()),
        'Loading providers…',
      );
      expect(
        providerLoadNote(const GridNetworksSignedOut()),
        'Sign in to Grid in Settings',
      );
      expect(
        providerLoadNote(const GridNetworksFailed('Grid is unreachable.')),
        'Grid is unreachable.',
      );
      expect(
        providerLoadNote(GridNetworksReady(GridMe.fromJson(const {}))),
        isNull,
      );
    });
  });
}

// The rules behind the one thing this app says unprompted. Every case here is
// a case where a warning would otherwise be noise: a window nobody can act on,
// a subscription nothing here is spending, a card that came back a minute
// after being closed.
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/usage/usage_nudge_store.dart';
import 'package:harness/usage/usage_offer.dart';
import 'package:harness/usage/usage_pressure.dart';
import 'package:harness/usage/usage_window.dart';

class _MemoryStore implements LocalKeyValueStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

UsageWindow _window(String label, double percent, {DateTime? resetsAt}) =>
    UsageWindow(label: label, usedPercent: percent, resetsAt: resetsAt);

ProviderUsage _ok(UsageProvider provider, List<UsageWindow> windows) =>
    ProviderUsage(
      provider: provider,
      status: UsageStatus.ok,
      windows: windows,
      fetchedAt: DateTime.now(),
    );

UsageAlert _alert(double percent, {String label = 'Session'}) =>
    UsageAlert(provider: UsageProvider.claude, window: _window(label, percent));

void main() {
  group('pressure', () {
    test('the two thresholds are the only two steps', () {
      expect(usagePressureOf(0), UsagePressure.calm);
      expect(usagePressureOf(79.9), UsagePressure.calm);
      expect(usagePressureOf(80), UsagePressure.warn);
      expect(usagePressureOf(89.9), UsagePressure.warn);
      expect(usagePressureOf(90), UsagePressure.critical);
      expect(usagePressureOf(100), UsagePressure.critical);
    });

    test('alerts are the critical windows, most spent first', () {
      final alerts = usageAlerts([
        _ok(UsageProvider.claude, [
          _window('Session', 91),
          _window('Weekly', 40),
        ]),
        _ok(UsageProvider.codex, [_window('5h', 97)]),
      ]);
      expect(alerts.map((a) => a.window.label), ['5h', 'Session']);
    });

    test('a reading with no figures raises nothing', () {
      final alerts = usageAlerts([
        const ProviderUsage(
          provider: UsageProvider.claude,
          status: UsageStatus.signedOut,
          message: 'Sign in to Claude to see usage',
        ),
        ProviderUsage.loading(UsageProvider.codex),
      ]);
      expect(alerts, isEmpty);
    });

    test(
      'the dismissal key survives a reset time that moves under the poll',
      () {
        // The vendors recompute `resets_at` on every answer. A key carrying it
        // would change once a minute, and a dismissal would then be for a
        // window that no longer exists by that name.
        final first = UsageAlert(
          provider: UsageProvider.claude,
          window: _window('Session', 91, resetsAt: DateTime(2026, 1, 1, 12)),
        );
        final later = UsageAlert(
          provider: UsageProvider.claude,
          window: _window('Session', 93, resetsAt: DateTime(2026, 1, 1, 12, 3)),
        );
        expect(first.key, later.key);
      },
    );

    test('a dismissal lapses when the window resets', () {
      final resets = DateTime(2026, 1, 1, 12);
      expect(
        UsageAlert(
          provider: UsageProvider.claude,
          window: _window('Session', 91, resetsAt: resets),
        ).dismissedUntil(),
        resets,
      );
    });

    test('a window with no reset time still lapses', () {
      // Otherwise one click would silence an account forever, which is the one
      // thing a dismissal must never be able to do.
      final now = DateTime(2026, 1, 1, 12);
      expect(_alert(91).dismissedUntil(now: now), now.add(kUsageDismissGrace));
    });
  });

  group('tally', () {
    test('counts only this engine, and only agents on their own login', () {
      final tally = tallyUsageAgents('claude', const [
        (engine: 'claude', onProvider: false, busy: false),
        (engine: 'claude', onProvider: false, busy: true),
        // Already on a provider: not spending this subscription, so moving it
        // would change nothing about the figure — but it still counts as
        // [present], because it is proof this computer runs the engine.
        (engine: 'claude', onProvider: true, busy: false),
        (engine: 'codex', onProvider: false, busy: false),
        (engine: null, onProvider: false, busy: false),
      ]);
      expect(tally.present, 3);
      expect(tally.candidates, 2);
      expect(tally.movable, 1);
    });
  });

  group('offer', () {
    const busyOnly = UsageAgentTally(present: 2, candidates: 2, movable: 0);
    const idle = UsageAgentTally(present: 3, candidates: 3, movable: 3);

    /// Every agent of this engine already moved onto a provider by hand.
    const parked = UsageAgentTally(present: 2, candidates: 0, movable: 0);

    test('the silence says which of the three it is', () {
      // Four unrelated facts about a machine produce the identical blank, and
      // they are fixed in completely different places — so the notice can log
      // which one it was rather than leaving somebody to guess at a feature
      // that looks broken.
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: 'Water Grid',
          tally: idle,
          gridSurface: false,
        ).blocked,
        UsageOfferBlocked.noProviders,
      );
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: 'Water Grid',
          tally: UsageAgentTally.none,
          gridSurface: true,
        ).blocked,
        UsageOfferBlocked.noAgents,
      );
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: 'Water Grid',
          tally: busyOnly,
          gridSurface: true,
        ).blocked,
        UsageOfferBlocked.allBusy,
      );
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: 'Water Grid',
          tally: idle,
          gridSurface: true,
        ).blocked,
        isNull,
      );
    });

    test('a build with no providers is offered nothing', () {
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: 'Water Grid',
          tally: idle,
          gridSurface: false,
        ).offer,
        isNull,
      );
    });

    test('an engine this computer does not run is offered nothing', () {
      // The limit is real, but whatever burned it is on a machine this app
      // cannot reach — so there is nothing to move and nothing to say.
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: 'Water Grid',
          tally: UsageAgentTally.none,
          gridSurface: true,
        ).offer,
        isNull,
      );
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: null,
          tally: UsageAgentTally.none,
          gridSurface: true,
        ).offer,
        isNull,
      );
    });

    test('agents parked on a provider still earn the DEFAULT offer', () {
      // The hole this closes: with no default picked, `New agent` launches the
      // next one onto the very subscription that is running out — so the fact
      // that today's agents were moved by hand is not a reason to say nothing.
      expect(
        resolveUsageOffer(
          alert: _alert(97),
          providerName: null,
          tally: parked,
          gridSurface: true,
        ).offer!.action,
        UsageOfferAction.chooseProvider,
      );
      // With a default already picked there IS nothing to do: new agents
      // launch on it, and nothing here is on the subscription to move.
      expect(
        resolveUsageOffer(
          alert: _alert(97),
          providerName: 'Water Grid',
          tally: parked,
          gridSurface: true,
        ).blocked,
        UsageOfferBlocked.noAgents,
      );
    });

    test('a provider chosen and every agent mid-turn is offered nothing', () {
      // The CLI refuses a busy agent with AGENT_BUSY, so the only button worth
      // drawing would be refused the moment it was pressed.
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: 'Water Grid',
          tally: busyOnly,
          gridSurface: true,
        ).offer,
        isNull,
      );
    });

    test('no provider chosen offers the picker, busy agents or not', () {
      // Choosing one is worth doing whether or not anything can move right
      // now — it is what every agent started after this will launch on.
      final offer = resolveUsageOffer(
        alert: _alert(95),
        providerName: null,
        tally: busyOnly,
        gridSurface: true,
      ).offer!;
      expect(offer.action, UsageOfferAction.chooseProvider);
      expect(offer.actionLabel, 'Choose a provider');
      expect(offer.providerName, isNull);
    });

    test('an empty provider name is no provider', () {
      expect(
        resolveUsageOffer(
          alert: _alert(95),
          providerName: '',
          tally: idle,
          gridSurface: true,
        ).offer!.action,
        UsageOfferAction.chooseProvider,
      );
    });

    test('the button names the count and the destination', () {
      final offer = resolveUsageOffer(
        alert: _alert(92),
        providerName: 'Water Grid',
        tally: idle,
        gridSurface: true,
      ).offer!;
      expect(offer.action, UsageOfferAction.moveAgents);
      expect(offer.headline, 'Claude is 92% through its Session limit');
      expect(offer.actionLabel, 'Move 3 agents');
      expect(offer.detail, contains('moving 3 agents to Water Grid'));
    });

    test('one agent is not "1 agents"', () {
      expect(
        resolveUsageOffer(
          alert: _alert(92),
          providerName: 'Water Grid',
          tally: const UsageAgentTally(present: 1, candidates: 1, movable: 1),
          gridSurface: true,
        ).offer!.actionLabel,
        'Move 1 agent',
      );
    });

    test('the countdown leads when the vendor sent one', () {
      final offer = resolveUsageOffer(
        alert: UsageAlert(
          provider: UsageProvider.codex,
          window: _window(
            '5h',
            96,
            resetsAt: DateTime.now().add(const Duration(hours: 2, minutes: 4)),
          ),
        ),
        providerName: 'Water Grid',
        tally: idle,
        gridSurface: true,
      ).offer!;
      expect(offer.detail, startsWith('It resets in 2h 3m.'));
    });

    test('and is simply absent when it did not', () {
      // Never "resets in 0m", which would read as a measurement rather than as
      // the silence it is.
      final offer = resolveUsageOffer(
        alert: _alert(96),
        providerName: 'Water Grid',
        tally: idle,
        gridSurface: true,
      ).offer!;
      expect(offer.detail, isNot(contains('resets')));
      expect(offer.detail, startsWith('Keep working'));
    });
  });

  group('nudge store', () {
    test('a dismissal survives a relaunch', () async {
      final disk = _MemoryStore();
      final until = DateTime.now().add(const Duration(hours: 3));
      await UsageNudgeStore(storage: disk).dismiss('claude|Session', until);

      final next = UsageNudgeStore(storage: disk);
      await next.load();
      expect(next.isDismissed('claude|Session'), isTrue);
      expect(next.isDismissed('codex|5h'), isFalse);
    });

    test('and lapses once that window has reset', () async {
      final disk = _MemoryStore();
      final store = UsageNudgeStore(storage: disk);
      await store.dismiss(
        'claude|Session',
        DateTime.now().add(const Duration(minutes: 1)),
      );
      expect(
        store.isDismissed(
          'claude|Session',
          now: DateTime.now().add(const Duration(hours: 2)),
        ),
        isFalse,
      );
    });

    test('an expired row is swept rather than kept forever', () async {
      final disk = _MemoryStore();
      final now = DateTime(2026, 1, 1, 12);
      final store = UsageNudgeStore(storage: disk);
      await store.dismiss(
        'claude|Session',
        now.subtract(const Duration(hours: 1)),
        now: now,
      );
      expect(store.value, isEmpty);
      final next = UsageNudgeStore(storage: disk);
      await next.load(now: now);
      expect(next.value, isEmpty);
    });

    test('an unreadable file costs the silence, never the warning', () async {
      final disk = _MemoryStore();
      disk.values['usage_limit_dismissals'] = 'not json';
      final store = UsageNudgeStore(storage: disk);
      await store.load();
      expect(store.isDismissed('claude|Session'), isFalse);
    });
  });
}

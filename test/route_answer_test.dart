// What the window makes of the router's answer.
//
// The threshold lives on this data: `confidence` decides whether ⌘K works in silence or stops and asks.
// A field that quietly parses to 0 would turn every confident route into a question — and a field that
// throws would turn it into a spinner that never ends — so the shapes that can actually arrive are
// pinned here rather than assumed.
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';

void main() {
  test('reads a full answer', () {
    final answer = RouteAnswer.fromJson({
      'agentId': 'a1',
      'machineId': 'm-local',
      'name': 'auth-api',
      'confidence': 0.86,
      'reason': 'name matches the domain',
      'candidates': [
        {'agentId': 'a1', 'machineId': 'm-local', 'name': 'auth-api', 'machine': 'this computer', 'recent': 'token rotation'},
        {'agentId': 'a2', 'machineId': 'm-mini', 'name': 'payment-api', 'machine': 'mac-mini', 'recent': 'webhook retries'},
      ],
    });
    expect(answer.agentId, 'a1');
    expect(answer.confidence, 0.86);
    expect(answer.isEmpty, isFalse);
    expect(answer.candidates.map((c) => c.name), ['auth-api', 'payment-api']);
    expect(answer.candidates.first.recent, 'token rotation');
    // The machine travels with the name: the list spans every computer, so it is the only thing telling
    // two agents called the same thing apart.
    expect(answer.candidates.map((c) => c.machine), ['this computer', 'mac-mini']);
    // …and the id beside it, which is what actually opens the pane on the right computer.
    expect(answer.machineId, 'm-local');
    expect(answer.candidates.map((c) => c.machineId), ['m-local', 'm-mini']);
  });

  test('an integer confidence is still a number', () {
    // The router is told to answer 0..1 and a model that says `1` sends an int. Read as a double or the
    // certain answer is the one that gets second-guessed.
    expect(RouteAnswer.fromJson({'agentId': 'a1', 'confidence': 1}).confidence, 1.0);
  });

  test('a picked-nobody answer says so rather than pretending', () {
    final answer = RouteAnswer.fromJson({'agentId': '', 'reason': 'no agents in machine'});
    expect(answer.isEmpty, isTrue);
    expect(answer.confidence, 0);
    expect(answer.candidates, isEmpty);
  });

  test('junk parses to an empty answer instead of throwing', () {
    // This crosses a socket. A malformed frame must land the palette on "nobody to send to", which the
    // person can act on — not on an exception behind a spinner, which they cannot.
    final answer = RouteAnswer.fromJson({
      'agentId': 7,
      'confidence': 'high',
      'candidates': ['not a candidate', 42, {'agentId': 'a3', 'name': 'ok'}],
    });
    expect(answer.isEmpty, isTrue);
    expect(answer.confidence, 0);
    expect(answer.candidates.map((c) => c.name), ['ok']);
    expect(answer.candidates.single.recent, '');
    expect(answer.candidates.single.machine, '');
    expect(answer.candidates.single.machineId, '');
  });
}

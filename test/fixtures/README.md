# Relay fixtures

One real `GET {relay}/grid/overview`, `/grid/members/usage` and the control
plane's member roster, captured from a live grid and then **anonymised**:
every provider email, member address and machine name is replaced.

The roster keeps each row's `source` — 13 people somebody added, 20 admitted by
the grid's own email domain — because that is the one field the share sheet
renders differently: a domain membership has no row to delete, so it is offered
no way off.

The figures are untouched, and that is the point of keeping them — the panels
these drive are almost entirely about fitting real numbers beside real names,
and a hand-written fixture would have neither the eight-machine grid, the three
owner groups, the 92% cache hit rate, nor the one model carrying 61% of the
work. Every layout bug found in the port was found with these.

Recapture with the probe in the commit that added them; anonymise before
committing.

# Relay fixtures

One real `GET {relay}/grid/overview`, `/grid/members/usage` and the control
plane's member roster, captured from a live grid and then **anonymised**:
every provider email, member address and machine name is replaced.

The figures are untouched, and that is the point of keeping them — the panels
these drive are almost entirely about fitting real numbers beside real names,
and a hand-written fixture would have neither the eight-machine grid, the three
owner groups, the 92% cache hit rate, nor the one model carrying 61% of the
work. Every layout bug found in the port was found with these.

Recapture with the probe in the commit that added them; anonymise before
committing.

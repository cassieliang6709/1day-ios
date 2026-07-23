# 1Day beta test

## Goal

Run the same core task with 5–10 real participants and collect evidence that can
be reproduced or audited. Do not turn estimates, developer tests, or invited
users into resume metrics.

## Participant task

1. Install the TestFlight build.
2. Create or join a one-day shared challenge.
3. Record at least three moments.
4. Re-record one moment to verify replacement behavior.
5. Sync the room, render a final film, and try to share or save it.
6. Report the first blocker and give the experience a 1–5 rating.

## Metrics to record

Keep participant identities outside the public repository. Use anonymous IDs
such as `P01`.

| Participant | Joined room | Recorded 3+ | Re-record worked | Sync worked | Export worked | Shared/saved | Minutes | Rating | First blocker |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| P01 |  |  |  |  |  |  |  |  |  |
| P02 |  |  |  |  |  |  |  |  |  |
| P03 |  |  |  |  |  |  |  |  |  |
| P04 |  |  |  |  |  |  |  |  |  |
| P05 |  |  |  |  |  |  |  |  |  |
| P06 |  |  |  |  |  |  |  |  |  |
| P07 |  |  |  |  |  |  |  |  |  |
| P08 |  |  |  |  |  |  |  |  |  |
| P09 |  |  |  |  |  |  |  |  |  |
| P10 |  |  |  |  |  |  |  |  |  |

## Metric definitions

- **Join success rate:** participants who entered a room / participants who tried
- **Core completion rate:** participants who recorded at least three moments and exported / participants who started
- **Export success rate:** successful final exports / participants who attempted export
- **Shared-room success rate:** rooms in which clips from at least two participants synced / shared rooms tested
- **Median time to first export:** median elapsed minutes among successful participants

Always report the denominator: “8 of 10 testers exported successfully” is more
credible than “80% success” alone.

## Recruitment message

> I built a small iPhone app that turns a few moments from your day into one
> short film. I’m looking for 5–10 people to try a private TestFlight beta. It
> should take about 10 minutes plus three tiny recordings. I’m testing whether
> joining, recording, syncing, and exporting are understandable—not testing you.
> Would you be willing to try it and send me the first thing that feels confusing?

## Resume gate

Use **Independent iOS Project** until an external TestFlight build is distributed
or the app is approved for the App Store. “Launched” requires a real external
release, not a successful local build.

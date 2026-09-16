# No-access Home usability protocol

Status: prepared; **not yet run**. Card UI-hierarchy must remain `Not Started` until participant sessions produce observations.

## Question and threshold

Can a first-time user who has no configured access identify, without coaching:

1. that access must be imported;
2. the primary import action;
3. the current connection/access status;
4. the next step after an import failure?

Pass only if at least 4 of 5 participants complete items 1-3 in 30 seconds and at least 4 of 5 choose the recovery action in 45 seconds. Record time and outcome for every participant; do not average away failures.

## Session

- Use the same build, device class, locale, text scale, and empty profile state for all participants.
- Give the neutral prompt: “You received access to a VPN service. Show how you would start using it here.”
- Do not name buttons, explain product structure, or point at the screen.
- After the initial task, show the import-failed state and ask: “What would you do next?”
- Stop after 5 minutes or when the participant reaches the next screen.

## Observation record

Store only an anonymous participant code, build SHA, device class, locale, text scale, completion flags, elapsed seconds, first action, recovery action, and a short paraphrased observation. Do not record profile URLs, email, configuration, server names, or screen/video without separate consent.

| Participant | Import need noticed | Import action found | Status understood | Recovery chosen | Seconds | First action | Observation |
|---|---|---|---|---|---:|---|---|
| P01 | — | — | — | — | — | — | — |

## Decision

- **Keep:** thresholds pass and no repeated confusion appears.
- **Iterate:** one threshold fails; change only the smallest label, hierarchy, or action needed, then rerun the same protocol.
- **Stop/redesign:** two or more thresholds fail or participants systematically infer account/payment behavior that does not exist.

Until completed observations exist, the result is “not verified”; visual preference is not evidence for a redesign.

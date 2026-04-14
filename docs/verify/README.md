# Verification workflow

This directory supports the `cshub-verify` agent team handoff workflow.
Not part of v0.2.8 spec scope (§1); documented in the v0.2.8 execution plan's
"Verification Handoff" section.

## Structure

- `scenarios/` — human-authored functional test scenarios, one per feature
- `runs/` — verify team reports and decisions, appended per verify round
- `handoff-manifest.md` — current handoff state, overwritten per round (only
  written at mandatory checkpoint phases: 4, 7, 10, 12)

## Cadence

Verify team is invoked at designated checkpoints only, not at every phase
boundary. See the "Cadence" subsection at the top of
`docs/superpowers/plans/2026-04-11-v0.2.8-execution-plan.md` for the rule and
the list of mandatory checkpoints.

Non-checkpoint phases update scenarios if the functional surface changed; they
do not write the handoff manifest and do not pause for verify.

## Manifest format

Two mandatory sections: 1a "What changed" and 1b "Environment requirements".
Missing or incomplete 1b causes the Coordinator to REJECT the handoff without
starting the Tester and without counting it as a verify round.

Template in the execution plan's "Verification Handoff" section.

# ADR-0006: Propose, Gate, Commit: plan on PR, apply behind approval

- Status: Accepted
- Date: 2026-10-05

## Context

Infrastructure changes must be reviewed against what Terraform will actually
do, not against the diff alone. The approval must be explicit and recorded,
and it must cover exactly the change that gets applied.

## Decision

The pipeline follows a three-stage method:

1. **Propose** (`.github/workflows/propose.yml`, on pull request):
   `terraform fmt -check`, `terraform validate`, `tflint` (with the azurerm
   ruleset), a `trivy config` misconfiguration scan, and a speculative
   `terraform plan`. The plan summary (counts, changed addresses, full plan)
   is posted to the PR as a single comment that is updated on each push.
2. **Gate** (`.github/workflows/apply.yml`, on merge to `main`): a fresh plan
   is published to the run summary together with a **plan fingerprint**, a
   SHA-256 over the planned resource changes. The `apply` job targets the
   `production` environment, which pauses the run until a required reviewer
   approves it.
3. **Commit**: the approved job re-plans under a state lock, recomputes the
   fingerprint and applies **only if it matches** the approved one. If
   anything changed in between (drift, a concurrent change), the run fails
   and has to be reviewed again.

`destroy.yml` follows the same plan, gate, fingerprint, apply sequence for
teardown and requires a typed confirmation.

## Consequences

- No plan file is passed between jobs as an artifact. Plan files can contain
  sensitive values, and artifacts on a public repository are readable by
  others. The fingerprint carries the guarantee without the plan file.
- All state-changing workflows share one concurrency group with
  `cancel-in-progress: false`, so a run holding the state lock is never
  cancelled midway.
- Branch protection on `main` should require the `propose` checks, so an
  unreviewed or failing change cannot reach the gate.
- On a public repository, plan output (resource names, IDs including the
  subscription ID) is visible in PR comments. These are identifiers, not
  credentials. A private repository is the better default for real workloads.

## Alternatives considered

- **Apply on merge without an environment gate.** Faster, but no explicit
  approval of the plan.
- **Upload the plan file as an artifact and apply it.** Exact, but exposes
  plan contents (see above) and goes stale silently if state changes.
- **Terraform Cloud / HCP Terraform run workflow.** Equivalent controls,
  plus an external SaaS dependency; GitHub-native was preferred here.

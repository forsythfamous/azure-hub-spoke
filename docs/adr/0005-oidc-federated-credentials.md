# ADR-0005: GitHub OIDC federated credentials, two identities, no secrets

- Status: Accepted
- Date: 2026-10-05

## Context

The pipeline must authenticate to Azure for plan and apply. Client secrets
and certificates are long-lived credentials that leak through logs, forks and
copied configuration, and they need rotation.

## Decision

- Use **workload identity federation**. GitHub Actions issues a short-lived
  OIDC token, and Entra ID exchanges it for an access token only if the
  token's subject matches a federated credential. No secret exists to leak
  or rotate. `azure/login` and the azurerm provider/backend both use OIDC
  (`ARM_USE_OIDC=true`, `use_azuread_auth=true` for state).
- Use **two identities** with different subjects and roles:

  | Identity | Federated subject(s) | Azure roles |
  |---|---|---|
  | plan | `repo:<owner>/<repo>:pull_request`, `repo:<owner>/<repo>:ref:refs/heads/main` | Reader (subscription), Storage Blob Data Reader (state container) |
  | apply | `repo:<owner>/<repo>:environment:production` | Contributor (dedicated subscription), Storage Blob Data Contributor (state container) |

- The apply identity's client ID is an **environment secret** of
  `production`. It is only available to jobs that passed the environment's
  protection rules.

## Consequences

- A pull request, including one from a compromised branch, can only obtain
  a read-only token. Write access needs a merge to `main` plus a reviewer's
  approval of the `production` environment.
- Speculative plans run with `-lock=false`, so the plan identity needs no
  write access to state.
- The configuration creates no role assignments, so neither identity needs
  `Owner` or `User Access Administrator`.
- Resource provider registration is turned off in the provider
  (`resource_provider_registrations = "none"`). Required providers are
  registered once by a subscription owner (see docs/deployment-identity.md).

## Alternatives considered

- **Service principal with client secret.** Rejected: long-lived secret.
- **Single identity for plan and apply.** Rejected: every PR would run
  with write access to the subscription.
- **Self-hosted runner with managed identity.** Removes the federation
  step but adds a runner to operate and patch; worth it only when private
  network access to the data plane is required.

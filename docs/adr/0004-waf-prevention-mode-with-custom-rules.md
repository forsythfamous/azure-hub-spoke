# ADR-0004: Application Gateway WAF_v2 in Prevention mode with custom rules

- Status: Accepted
- Date: 2026-10-05

## Context

The workload is exposed to the Internet over HTTP(S) and needs L7
protection: managed OWASP-class signatures, bot handling, a way to express
application-specific policy, and request rate limiting per client.

## Decision

- Application Gateway **WAF_v2**, autoscaling from 0 to 2 instances, zone
  redundant where the region supports zones.
- A standalone WAF policy (`azurerm_web_application_firewall_policy`)
  associated with the gateway, in **Prevention** mode, with
  **Microsoft_DefaultRuleSet 2.1** (anomaly scoring, OWASP CRS-derived) and
  **Microsoft_BotManagerRuleSet 1.1**.
- Request body inspection is enforced (128 KB inspect limit and maximum body),
  and log scrubbing removes the `Authorization` header and all cookie values
  from WAF logs.
- Two custom rules, evaluated before the managed rules:
  1. `BlockAdminPathFromUntrusted` (priority 10): blocks configurable admin
     URI prefixes unless the client is in `waf_admin_allowed_cidrs`. With the
     list empty the paths are blocked for everyone.
  2. `RateLimitPerClientIp` (priority 20): a `RateLimitRule` keyed on
     `ClientAddr`, 100 requests per minute by default.
- Diagnostic settings send gateway and WAF logs to Log Analytics in
  resource-specific tables (`AGWAccessLogs`, `AGWFirewallLogs`).

## Consequences

- Starting in Prevention mode means false positives surface as blocked
  requests, not as unread log entries. The expected workflow for a real
  application is: deploy, review `AGWFirewallLogs`, then add targeted rule
  exclusions or overrides in the policy (never a global switch to Detection).
- Application Gateway WAF answers every block, custom or managed, with
  **HTTP 403**. Rate-limited requests are therefore distinguishable from
  signature blocks only in the logs (`RuleId == "RateLimitPerClientIp"`).
  docs/VERIFY.md checks it that way. The rate-limit counter is kept per
  instance and is approximate, so the cut-off point under load is not exact.
- The listener is HTTP only. Adding HTTPS needs a certificate in Key Vault
  and a user-assigned identity on the gateway. The TLS policy
  (`AppGwSslPolicy20220101S`, TLS 1.2+) is already set so it applies as soon
  as an HTTPS listener exists. This is tracked as a known gap in the README.

## Alternatives considered

- **Azure Front Door Premium + WAF.** Global edge, better DDoS posture and
  rate limiting at the edge; also a different cost model and a different
  failure domain. The right choice for global, multi-region front ends; not
  needed to protect a single-region workload in a spoke.
- **OWASP CRS 3.2.** Still supported; DRS 2.1 is the current Microsoft
  recommendation and includes Microsoft Threat Intelligence rules.
- **Detection mode first.** Common for brownfield rollouts. Here the backend
  is purpose-built, so there is no legacy traffic to baseline.

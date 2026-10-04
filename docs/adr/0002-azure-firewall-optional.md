# ADR-0002: Azure Firewall is optional and off by default

- Status: Accepted
- Date: 2026-10-05

## Context

Azure Firewall Standard costs about USD 1.25/hour (~USD 915/month) before
data processing, roughly three times everything else in this design combined.
The environment is meant to be deployed for verification and then destroyed,
and it must remain secure when the firewall is not deployed.

## Decision

- `enable_firewall` (default `false`) controls the firewall, its policy and
  its public IP(s). `firewall_sku_tier` selects Basic, Standard or Premium.
- `AzureFirewallSubnet` and `AzureFirewallManagementSubnet` are always
  created, so the address plan does not change when the firewall is toggled.
- Route tables are created only when the firewall exists. They send
  `0.0.0.0/0` from the app subnet to the firewall's private IP, with BGP
  route propagation disabled. The Application Gateway subnet never gets this
  route (a default route to a virtual appliance is unsupported for
  Application Gateway v2).
- Spoke-to-spoke traffic is allowed only by explicit firewall rules. The one
  rule shipped is an application rule from the app subnet to the storage
  account's blob FQDN. Application rules SNAT, which keeps the return path
  from the private endpoint symmetric without UDRs in the data spoke.

## Consequences

- **Firewall disabled (default):** the spokes have no transit path to each
  other; peering is non-transitive. The workload tier cannot reach the data
  spoke's private endpoint. This is the intended secure default, and
  docs/VERIFY.md checks it as such. Subnets for compute have default outbound
  access disabled, so there is no implicit Internet egress either.
- **Firewall enabled:** workload to storage traffic flows through the hub
  and is logged in the resource-specific `AZFW*` tables. Egress from the app
  subnet is denied unless a rule allows it.
- The Basic tier (~USD 290/month) is a cheaper way to exercise the routed
  path. It needs a management subnet and public IP and supports threat
  intelligence in alert mode only. Both are handled in the module.

## Alternatives considered

- **Always-on firewall.** Correct for production, too expensive for an
  environment whose purpose is verification.
- **NVA on a small VM.** Cheaper but turns into an operated appliance
  (patching, HA, throughput) and is not representative of an Azure-native
  design.
- **Direct spoke-to-spoke peering.** Removes the inspection point and does
  not scale; rejected.

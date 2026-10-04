# ADR-0001: Customer-managed hub-spoke instead of Azure Virtual WAN

- Status: Accepted
- Date: 2026-10-05

## Context

The topology needs a shared hub (DNS, egress inspection, shared services)
and isolated spokes for the workload and data tiers, in a single region,
with no on-premises connectivity in scope. Both a customer-managed hub VNet
and Azure Virtual WAN can provide this.

## Decision

Build a customer-managed hub VNet with VNet peering to each spoke.

## Consequences

- Every routing decision is a visible Terraform resource: peerings, route
  tables, firewall rules. Nothing is implied by a managed hub router, which
  makes the design reviewable in a pull request and testable with
  `az network nic show-effective-route-table`.
- Idle cost is close to zero without the firewall. A Virtual WAN hub carries
  an hourly hub charge on its own (roughly USD 180/month for a Standard hub
  before any firewall), which conflicts with a deploy, verify, destroy routine.
- Spoke-to-spoke transit has to be designed explicitly (UDR to the hub
  firewall, ADR-0002); with Virtual WAN it comes with the hub router.
- Peering, UDRs and DNS links grow linearly with the number of spokes. For
  tens of spokes, multiple regions or branch/VPN-heavy connectivity, Virtual
  WAN (or Azure Virtual Network Manager for connectivity configuration)
  becomes the better trade-off and this decision should be revisited.

## Alternatives considered

- **Virtual WAN Standard hub with secured hub (Firewall Manager).** Less
  plumbing, but higher fixed cost and less control over routing tables;
  disproportionate for two spokes in one region.
- **Azure Virtual Network Manager connectivity configuration.** Useful at
  scale for managing peerings as a group; adds a management resource without
  reducing complexity for two spokes.

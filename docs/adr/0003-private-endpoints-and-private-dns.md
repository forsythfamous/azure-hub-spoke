# ADR-0003: Private endpoints with centrally hosted Private DNS zones

- Status: Accepted
- Date: 2026-10-05

## Context

PaaS data services must not be reachable from the Internet. Service
endpoints keep the public endpoint (and its public IP) and only filter by
source subnet. Private endpoints give the service a private IP in a VNet,
but only work if every client resolves the service FQDN to that IP.

## Decision

- The storage account has `public_network_access_enabled = false`, shared
  key access disabled and Entra ID as the default authorization. It is
  reachable only through a private endpoint in the data spoke.
- `privatelink.*` Private DNS zones are hosted once, in the hub resource
  group. The hub VNet and every spoke VNet are linked to them. Spokes create
  their own links, so dependencies run one way (hub to spoke) and adding a
  spoke never edits the hub module.
- The endpoint registers its A record through a `private_dns_zone_group`;
  Azure manages the record lifecycle. No hand-written DNS records.
- The private endpoint subnet has network policies enabled
  (`NetworkSecurityGroupEnabled`), so its NSG actually filters endpoint
  traffic. Without this setting the NSG is attached but ignored for private
  endpoints.
- Storage is managed through ARM only (`data_plane_available = false`,
  containers created with `storage_account_id`), so Terraform never needs a
  network path to the blob endpoint.

## Consequences

- Clients outside the linked VNets resolve the public CNAME chain and are
  rejected by the storage service. That rejection is one of the checks in
  docs/VERIFY.md.
- Any additional resolver (on-premises DNS, a custom DNS server) must forward
  to Azure DNS (168.63.129.16) through a resolver in the hub. This is out of
  scope here and is the usual next step (Azure DNS Private Resolver).
- At scale, the zone links and zone groups are often enforced with Azure
  Policy (DeployIfNotExists) rather than declared per endpoint.

## Alternatives considered

- **Service endpoints.** Cheaper, but the public endpoint stays reachable and
  data can leave to any storage account in the region unless service
  endpoint policies are added. Rejected for a data tier.
- **Zones per spoke.** Leads to split-brain DNS once a second spoke needs the
  same service. Rejected.

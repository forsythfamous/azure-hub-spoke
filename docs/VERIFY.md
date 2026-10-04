# Post-deployment verification

A checklist for turning each claim in the README into evidence after a
real deployment. Each check states the command, the expected result, and
what the result proves. Save raw outputs under `evidence/<date>/` (redact
the subscription ID), then fill in the **Verification status** table in the
README.

Nothing in this file has been run yet. The expected results follow from the
configuration and Azure's documented behaviour; a check that does not match
is a finding to record, not something to explain away.

## 0. Setup

Run from `envs/dev` after a successful apply, signed in as a human operator
(`az login`) with at least `Reader` on the subscription, `Virtual Machine
Contributor` on the workload resource group (for Run Command), and
`Log Analytics Reader` on the workspace.

```bash
cd envs/dev
RG_HUB=$(terraform output -json resource_groups | jq -r .hub)
RG_WL=$(terraform output -json resource_groups | jq -r .workload)
RG_DATA=$(terraform output -json resource_groups | jq -r .data)
VNET_HUB=$(terraform output -json vnet_names | jq -r .hub)
VNET_WL=$(terraform output -json vnet_names | jq -r .workload)
VNET_DATA=$(terraform output -json vnet_names | jq -r .data)
AGW_IP=$(terraform output -raw app_gateway_public_ip)
SA=$(terraform output -raw storage_account_name)
SA_HOST=$(terraform output -raw storage_blob_host)
PE_IP=$(terraform output -raw storage_private_endpoint_ip)
VM=$(terraform output -raw backend_vm_name)
LAW=$(terraform output -raw log_analytics_workspace_id)
mkdir -p ../../evidence/$(date +%F)

# Helper: run a shell snippet on the backend VM (no SSH, no public IP).
invm() { az vm run-command invoke -g "$RG_WL" -n "$VM" --command-id RunShellScript \
           --scripts "$1" --query 'value[0].message' -o tsv; }
```

## 1. Hub-spoke peering

```bash
for v in "$VNET_WL" "$VNET_DATA"; do
  az network vnet peering list -g "$( [ "$v" = "$VNET_WL" ] && echo "$RG_WL" || echo "$RG_DATA")" \
    --vnet-name "$v" --query "[].{name:name,state:peeringState,sync:peeringSyncLevel,fwd:allowForwardedTraffic}" -o table
done
az network vnet peering list -g "$RG_HUB" --vnet-name "$VNET_HUB" \
  --query "[].{name:name,state:peeringState,sync:peeringSyncLevel}" -o table
```

- [ ] Expected: four peerings (two per spoke), all `Connected` / `FullyInSync`.
- [ ] No peering exists between the two spokes (`az network vnet peering list`
      on each spoke shows only the hub).

Proves: hub-spoke topology as declared, with no direct spoke-to-spoke link.

## 2. Private DNS and the private endpoint

```bash
az network private-dns record-set a list -g "$RG_HUB" \
  -z privatelink.blob.core.windows.net --query "[].{name:name,ip:aRecords[0].ipv4Address}" -o table
az network private-dns link vnet list -g "$RG_HUB" \
  -z privatelink.blob.core.windows.net --query "[].{name:name,vnet:virtualNetwork.id,state:virtualNetworkLinkState}" -o table
az network private-endpoint show -g "$RG_DATA" -n "pe-${SA}-blob" \
  --query "privateLinkServiceConnections[0].privateLinkServiceConnectionState.status" -o tsv
```

- [ ] An A record `<storage account>` with IP = `$PE_IP` (in `10.12.0.0/24`).
- [ ] Three VNet links (hub, workload, data), all `Completed`.
- [ ] Connection status `Approved`.

### 2a. Resolution from inside a spoke

```bash
invm "resolvectl query $SA_HOST; getent ahostsv4 $SA_HOST | head -1"
```

- [ ] The CNAME chain goes through `$SA.privatelink.blob.core.windows.net` and
      the address is `$PE_IP`.

Proves: VNets linked to the hub's zones resolve the public FQDN to the
private endpoint.

### 2b. Resolution and access from the Internet

```bash
nslookup "$SA_HOST"                       # from your workstation
curl -sS -o /dev/null -w '%{http_code}\n' "https://${SA_HOST}/data?restype=container&comp=list"
az storage blob list --account-name "$SA" -c data --auth-mode login -o table   # as a user with Blob Data Reader
az storage account show -g "$RG_DATA" -n "$SA" \
  --query "{publicNetworkAccess:publicNetworkAccess,allowSharedKeyAccess:allowSharedKeyAccess,minTls:minimumTlsVersion}" -o json
```

- [ ] `nslookup` returns a **public** IP (the privatelink CNAME resolves
      publicly outside linked VNets).
- [ ] `curl` returns `403` (authorization or public network access failure),
      not a container listing.
- [ ] `az storage blob list` fails with an authorization/network error even
      with a valid data-plane RBAC role.
- [ ] `publicNetworkAccess: Disabled`, `allowSharedKeyAccess: false`,
      `minTls: TLS1_2`.

Proves: the storage account has no usable public path, even for an
authenticated caller.

## 3. Spoke isolation and the firewall path

### 3a. Firewall disabled (default)

```bash
invm "curl -sS -m 10 -o /dev/null -w '%{http_code}\n' https://$SA_HOST/ || echo 'no route'"
az network nic show-effective-route-table -g "$RG_WL" -n "nic-$VM" -o table
```

- [ ] `curl` times out (`000` / `no route`): the workload spoke cannot reach
      the data spoke, because peering is not transitive.
- [ ] Effective routes show the hub prefix (`10.10.0.0/22`) via
      `VNetPeering` and **no** route to `10.12.0.0/22`.

### 3b. Firewall enabled (`TF_VAR_ENABLE_FIREWALL=true`, re-apply)

```bash
az network nic show-effective-route-table -g "$RG_WL" -n "nic-$VM" -o table
invm "curl -sS -m 10 -o /dev/null -w '%{http_code}\n' https://$SA_HOST/"
invm "curl -sS -m 10 -o /dev/null -w '%{http_code}\n' https://example.com/ || echo blocked"
az monitor log-analytics query -w "$LAW" --analytics-query "
AZFWApplicationRule
| where TimeGenerated > ago(30m)
| project TimeGenerated, SourceIp, Fqdn, Action, Rule, RuleCollection
| order by TimeGenerated desc" -o table
```

- [ ] `0.0.0.0/0` next hop `VirtualAppliance` = firewall private IP (source `User`).
- [ ] The storage request returns an HTTP status from the storage service
      (any non-`000` code, e.g. `400`), which proves the TCP/TLS path through
      the firewall to the private endpoint.
- [ ] `example.com` is blocked (`000`/`blocked`).
- [ ] Logs show `Allow` for the storage FQDN (rule
      `workload-app-to-storage-blob`) and `Deny` for `example.com`.

Proves: spoke-to-spoke traffic exists only through the hub firewall and only
for explicitly allowed destinations.

## 4. NSGs

```bash
az network nic list-effective-nsg -g "$RG_WL" -n "nic-$VM" \
  --query "value[0].effectiveSecurityRules[?access=='Deny' || starts_with(name,'securityRules')].{name:name,prio:priority,access:access,dir:direction}" -o table
az network vnet subnet show -g "$RG_DATA" --vnet-name "$VNET_DATA" -n snet-private-endpoints \
  --query privateEndpointNetworkPolicies -o tsv
```

- [ ] Custom rules plus `Deny-All-Inbound` (4096) are effective on the app NIC.
- [ ] `NetworkSecurityGroupEnabled` on the private endpoint subnet (the NSG
      really applies to endpoint traffic).

## 5. Application Gateway WAF

```bash
# Benign request reaches the backend.
curl -sS -o /dev/null -w 'benign: %{http_code}\n' "http://$AGW_IP/"

# Managed rules (DRS 2.1): SQL injection and XSS payloads.
curl -sS -o /dev/null -w 'sqli:   %{http_code}\n' "http://$AGW_IP/?id=1%27%20OR%20%271%27%3D%271"
curl -sS -o /dev/null -w 'xss:    %{http_code}\n' "http://$AGW_IP/?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E"

# Custom rule 1: admin path from an untrusted source.
curl -sS -o /dev/null -w 'admin:  %{http_code}\n' "http://$AGW_IP/admin"

# Custom rule 2: rate limit (default 100 requests / minute / client IP).
for i in $(seq 1 250); do curl -s -o /dev/null -w '%{http_code}\n' "http://$AGW_IP/"; done | sort | uniq -c
```

- [ ] `benign: 200` (backend health: `az network application-gateway show-backend-health -g "$RG_WL" -n <agw>` shows `Healthy`).
- [ ] `sqli: 403`, `xss: 403`, `admin: 403`.
- [ ] The loop returns `200` first, then `403` once the threshold is passed.
      The cut-off is approximate because counters are kept per instance.

Application Gateway WAF returns **403 for every block**. It does not send
429 for rate limiting. Which rule blocked a request is shown in the WAF log:

```bash
az monitor log-analytics query -w "$LAW" --analytics-query "
AGWFirewallLogs
| where TimeGenerated > ago(30m)
| summarize hits = count() by RuleId, Action, RuleSetType
| order by hits desc" -o table
```

- [ ] Rows for the DRS SQLi/XSS rules (and anomaly-score evaluation) with
      action `Blocked` (or `Matched` plus a blocking score rule).
- [ ] `BlockAdminPathFromUntrusted` with action `Blocked`.
- [ ] `RateLimitPerClientIp` with action `Blocked`.
- [ ] Policy is in Prevention mode:
      `az network application-gateway waf-policy show -g "$RG_WL" -n <waf-policy> --query policySettings.mode`.

Log ingestion lags by several minutes. Re-run the query before treating a
missing row as a failure.

## 6. Diagnostic settings

```bash
for id in $(az resource list --query "[?tags.workload=='hubspoke'].id" -o tsv); do
  n=$(az monitor diagnostic-settings list --resource "$id" --query "length(@)" -o tsv 2>/dev/null || echo n/a)
  echo "$n  $id"
done
az monitor log-analytics query -w "$LAW" --analytics-query "
union withsource=Table *
| where TimeGenerated > ago(1h)
| summarize rows = count() by Table
| order by rows desc" -o table
```

- [ ] VNets, NSGs, public IPs, the Application Gateway, the storage account
      and its blob service, the VM, the workspace (and firewall when
      enabled) each report `1` diagnostic setting. Private DNS zones, route
      tables, private endpoints and NICs report `n/a`/`0` (no diagnostic
      categories, or out of scope).
- [ ] The workspace contains `AGWAccessLogs`, `AGWFirewallLogs`,
      `StorageBlobLogs`, `AzureMetrics` (plus `AZFW*` tables when the
      firewall is enabled).

## 7. Pipeline evidence

- [ ] PR link with the plan comment posted by `propose.yml`.
- [ ] `apply.yml` run showing the `production` approval (reviewer, time) and
      the "Plan fingerprint matches the approved plan" line.
- [ ] A run in which the fingerprint check failed, if one occurred.
- [ ] `destroy.yml` run, approved, ending with `Destroy complete!`.
- [ ] Entra sign-in logs for the two identities (`Workload identities`
      sign-ins) show federated credential sign-ins only, no secret-based ones.

## 8. Cost controls

```bash
for rg in "$RG_HUB" "$RG_WL" "$RG_DATA"; do
  az consumption budget list --resource-group "$rg" --query "[].{name:name,amount:amount,spent:currentSpend.amount}" -o table
done
az network application-gateway show -g "$RG_WL" -n <agw> --query autoscaleConfiguration
az monitor log-analytics workspace show --ids "$(az monitor log-analytics workspace list --query "[?customerId=='$LAW'].id" -o tsv)" \
  --query workspaceCapping.dailyQuotaGb
```

- [ ] One budget per resource group with the configured amount.
- [ ] Autoscale `minCapacity: 0`, `maxCapacity: 2`.
- [ ] Daily cap `1` GB.
- [ ] After the destroy run: `az group list --query "[?tags.workload=='hubspoke']" -o table`
      returns nothing, and Cost Management shows the actual cost of the
      verification window. Record that figure in the README.

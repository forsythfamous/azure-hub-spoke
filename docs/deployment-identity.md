# Deployment identity and least privilege

How the pipeline authenticates, what each identity can do, and the one-time
setup a subscription owner performs. Rationale: [ADR-0005](adr/0005-oidc-federated-credentials.md).

## Principles

- No client secrets or certificates. GitHub OIDC tokens are exchanged for
  Entra ID tokens through federated credentials.
- Read and write are separate identities. Pull requests only ever get the
  read identity.
- The write identity is only usable inside the `production` environment,
  after a reviewer approves the run.
- Terraform creates no role assignments, so no identity holds `Owner` or
  `User Access Administrator`.
- Use a dedicated subscription. Subscription-scoped `Contributor` is
  acceptable only where the subscription holds nothing else.

## Identities

| | plan | apply |
|---|---|---|
| Used by | `propose.yml` (PR plan), plan jobs in `apply.yml` / `destroy.yml` | `apply` / `destroy` jobs (environment `production`) |
| Federated subjects | `repo:<owner>/<repo>:pull_request`<br>`repo:<owner>/<repo>:ref:refs/heads/main` | `repo:<owner>/<repo>:environment:production` |
| Subscription role | `Reader` | `Contributor` |
| State container role | `Storage Blob Data Reader` | `Storage Blob Data Contributor` |
| GitHub secret | `AZURE_PLAN_CLIENT_ID` (repository secret) | `AZURE_APPLY_CLIENT_ID` (environment secret on `production`) |

Why `Contributor` at subscription scope for apply: the configuration creates
its own resource groups, which needs
`Microsoft.Resources/subscriptions/resourceGroups/write` at subscription
scope. To narrow this further, pre-create the three resource groups, import
them, and grant `Contributor` on those groups only. Budget resources
(`Microsoft.Consumption/budgets/*`) are covered by `Contributor` at
resource-group scope.

**To confirm on the first real deployment:** a `Reader`-only plan identity
may receive `403` on actions that read keys during refresh (for example
`Microsoft.Storage/storageAccounts/listKeys/action` or
`Microsoft.OperationalInsights/workspaces/sharedKeys/action`), depending on
provider behaviour for accounts with shared keys disabled. If that happens,
grant a custom role with only the failing action rather than promoting the
plan identity to `Contributor`, and record the outcome in the README.

## One-time setup (subscription owner)

User-assigned managed identities are used below because they cannot carry a
client secret at all. An app registration with federated credentials works
identically; only the `az ad app` commands differ.

```bash
SUB=<subscription-id>
REPO=<owner>/<repo>
LOC=polandcentral
az account set --subscription "$SUB"

# 1. Resource providers (the provider block disables auto-registration).
for ns in Microsoft.Network Microsoft.Storage Microsoft.Compute \
          Microsoft.OperationalInsights Microsoft.Insights Microsoft.Consumption; do
  az provider register --namespace "$ns"
done

# 2. Remote state: Entra-only storage account (no shared keys, no public blobs).
az group create -n rg-tfstate-plc -l "$LOC"
az storage account create -g rg-tfstate-plc -n <sttfstateXXXXXX> -l "$LOC" \
  --sku Standard_ZRS --kind StorageV2 --min-tls-version TLS1_2 \
  --allow-blob-public-access false --allow-shared-key-access false
az storage account blob-service-properties update -g rg-tfstate-plc \
  --account-name <sttfstateXXXXXX> --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 30
az storage container create --account-name <sttfstateXXXXXX> -n tfstate --auth-mode login
STATE_SCOPE=$(az storage account show -g rg-tfstate-plc -n <sttfstateXXXXXX> --query id -o tsv)/blobServices/default/containers/tfstate

# 3. Identities and federated credentials.
az group create -n rg-identity-plc -l "$LOC"
az identity create -g rg-identity-plc -n id-hubspoke-plan
az identity create -g rg-identity-plc -n id-hubspoke-apply

fic() { az identity federated-credential create -g rg-identity-plc --identity-name "$1" \
  --name "$2" --issuer https://token.actions.githubusercontent.com \
  --subject "$3" --audiences api://AzureADTokenExchange; }
fic id-hubspoke-plan  gh-pull-request "repo:${REPO}:pull_request"
fic id-hubspoke-plan  gh-main         "repo:${REPO}:ref:refs/heads/main"
fic id-hubspoke-apply gh-production   "repo:${REPO}:environment:production"

# 4. Role assignments.
PLAN=$(az identity show -g rg-identity-plc -n id-hubspoke-plan --query principalId -o tsv)
APPLY=$(az identity show -g rg-identity-plc -n id-hubspoke-apply --query principalId -o tsv)
ra() { az role assignment create --assignee-object-id "$1" --assignee-principal-type ServicePrincipal --role "$2" --scope "$3"; }
ra "$PLAN"  "Reader"                        "/subscriptions/$SUB"
ra "$PLAN"  "Storage Blob Data Reader"      "$STATE_SCOPE"
ra "$APPLY" "Contributor"                   "/subscriptions/$SUB"
ra "$APPLY" "Storage Blob Data Contributor" "$STATE_SCOPE"

# Client IDs for the GitHub secrets.
az identity show -g rg-identity-plc -n id-hubspoke-plan  --query clientId -o tsv
az identity show -g rg-identity-plc -n id-hubspoke-apply --query clientId -o tsv
```

The state account stays reachable from GitHub-hosted runners over its public
endpoint, with key access disabled. Making it private as well requires
self-hosted runners inside a VNet.

## GitHub configuration

| Kind | Name | Value |
|---|---|---|
| Repository secret | `AZURE_TENANT_ID` | Entra tenant ID |
| Repository secret | `AZURE_SUBSCRIPTION_ID` | Target subscription ID |
| Repository secret | `AZURE_PLAN_CLIENT_ID` | Client ID of `id-hubspoke-plan` |
| Environment secret (`production`) | `AZURE_APPLY_CLIENT_ID` | Client ID of `id-hubspoke-apply` |
| Repository variable | `TFSTATE_RESOURCE_GROUP` | `rg-tfstate-plc` |
| Repository variable | `TFSTATE_STORAGE_ACCOUNT` | State storage account name |
| Repository variable | `TFSTATE_CONTAINER` | `tfstate` |
| Repository variable | `TFSTATE_KEY` | `azure-hub-spoke/dev.tfstate` |
| Repository variable | `TF_VAR_OWNER` | Owner tag value |
| Repository variable | `TF_VAR_VM_ADMIN_SSH_PUBLIC_KEY` | OpenSSH public key |
| Repository variable | `TF_VAR_BUDGET_CONTACT_EMAILS` | HCL list, e.g. `["ops@example.com"]` |
| Repository variable | `TF_VAR_ENABLE_FIREWALL` | `false` (or `true` for the routed path) |

Environment `production`:

- Required reviewers: at least one. In a single-maintainer repository the
  maintainer approves their own run. The gate still forces an explicit,
  logged approval made after reading the plan.
- Deployment branches: `main` only.

Branch protection on `main`: require pull requests and the
`fmt / validate / tflint / trivy` and `plan (dev)` checks.

Tenant ID, subscription ID and client IDs are identifiers, not credentials.
They are stored as secrets so they stay out of logs.

## Enabling Azure in CI

Until a subscription is connected, pull requests run only the static checks (fmt, validate, tflint, trivy and the
mocked `terraform test` suite), and pushes to `main` do not plan or apply. After the identities, state storage and
secrets above are in place, set the repository variable `AZURE_ENABLED` to `true` to turn on plan and apply.

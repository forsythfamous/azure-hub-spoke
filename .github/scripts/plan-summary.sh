#!/usr/bin/env bash
# Renders a saved Terraform plan into a Markdown summary and a fingerprint.
#
#   plan-summary.sh <plan-file> <title>
#
# Writes plan-summary.md in the current directory. When running in GitHub
# Actions it also sets the step outputs `has_changes` and `fingerprint`.
#
# The fingerprint is a SHA-256 over the sorted list of planned resource
# changes (address, actions, planned values). The apply job re-plans under a
# state lock and refuses to apply unless its fingerprint equals the one the
# reviewer approved: what was reviewed is what gets applied.
set -euo pipefail

plan_file="${1:?plan file required}"
title="${2:-Terraform plan}"
max_plan_chars=50000

terraform show -json "$plan_file" > plan.json
terraform show -no-color "$plan_file" > plan.txt

changes_filter='[.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])]'

count() { jq "$changes_filter | map(select(.change.actions == $1)) | length" plan.json; }
n_create=$(count '["create"]')
n_update=$(count '["update"]')
n_delete=$(count '["delete"]')
n_replace=$(jq "$changes_filter | map(select(.change.actions | length == 2)) | length" plan.json)
n_total=$(jq "$changes_filter | length" plan.json)

fingerprint=$(jq -cS "$changes_filter | map({address, actions: .change.actions, after: .change.after}) | sort_by(.address)" plan.json \
  | sha256sum | cut -d' ' -f1)

{
  echo "<!-- terraform-plan:${title} -->"
  echo "### ${title}"
  echo
  echo "| create | update | replace | destroy |"
  echo "|---:|---:|---:|---:|"
  echo "| ${n_create} | ${n_update} | ${n_replace} | ${n_delete} |"
  echo
  if [ "$n_total" -gt 0 ]; then
    echo "<details><summary>Changed resources (${n_total})</summary>"
    echo
    echo "| action | address |"
    echo "|---|---|"
    jq -r "$changes_filter | .[] | \"| \(.change.actions | join(\"/\")) | \`\(.address)\` |\"" plan.json | head -n 200
    echo
    echo "</details>"
    echo
  fi
  echo "<details><summary>Full plan output</summary>"
  echo
  echo '```text'
  if [ "$(wc -c < plan.txt)" -gt "$max_plan_chars" ]; then
    head -c "$max_plan_chars" plan.txt
    echo
    echo "... truncated; see the workflow log for the full plan ..."
  else
    cat plan.txt
  fi
  echo '```'
  echo
  echo "</details>"
  echo
  echo "Plan fingerprint: \`${fingerprint}\`"
} > plan-summary.md

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "fingerprint=${fingerprint}"
    if [ "$n_total" -gt 0 ]; then echo "has_changes=true"; else echo "has_changes=false"; fi
  } >> "$GITHUB_OUTPUT"
fi

echo "changes=${n_total} fingerprint=${fingerprint}"

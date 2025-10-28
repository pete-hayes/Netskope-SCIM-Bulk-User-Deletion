#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Netskope SCIM Bulk User Deletion
# Version: 1.0
#
# This script automates the bulk deletion of users in a Netskope tenant using
# the SCIM API.
#
# Requirements:
#   - macOS
#	- curl
#	- jq
#
# Usage: ./delete_netskope_users.sh <TENANT_FQDN> <API_TOKEN> <CSV_FILE>
# Example: ./delete_netskope_users.sh example.goskope.com abc123def456ghi789jk users.csv
#
# CSV format: email
#
# Author: Peter Hayes
# License: MIT
#
# Disclaimer:
#   This project is not affiliated with or supported by Netskope.
#   It may be incomplete, outdated, or inaccurate.
#   Use at your own risk.
################################################################################

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <TENANT_FQDN> <API_TOKEN> <CSV_FILE>"
  exit 1
fi

TENANT_FQDN="$1"
API_TOKEN="$2"
CSV_FILE="$3"
API_URL="https://${TENANT_FQDN}/api/v2/users/getusers"
DELETE_URL="https://${TENANT_FQDN}/api/v2/scim/Users"

# ---------------------------------------------------------------------------
# Validate CSV
# ---------------------------------------------------------------------------

printf "\n"
echo "Netskope Tenant: $TENANT_FQDN"
echo "Processing $CSV_FILE"

if [[ ! -f "$CSV_FILE" ]]; then
  echo "Error: CSV file '$CSV_FILE' not found."
  exit 1
fi

EMAILS=()
while IFS= read -r line || [[ -n "$line" ]]; do
  line=$(echo "$line" | tr -d '\r' | xargs)
  [[ -z "$line" ]] && continue
  if echo "$line" | grep -Eq '^[^,[:space:]]+@[^,[:space:]]+$'; then
    EMAILS+=("$line")
  fi
done < "$CSV_FILE"

if [[ ${#EMAILS[@]} -eq 0 ]]; then
  echo "Error: No valid email addresses found in $CSV_FILE"
  exit 1
fi

echo "CSV validated: ${#EMAILS[@]} email(s) loaded."

# ---------------------------------------------------------------------------
# Find matching users in Netskope user database
# ---------------------------------------------------------------------------

FOUND_USERS=()
SCIM_IDS=()
NOT_FOUND_USERS=()

LIMIT=50
OFFSET=0

echo "Querying Netskope user database to match email list..."

while true; do
  RESPONSE=$(curl -sk -X POST "$API_URL" \
    -H "accept: application/json" \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --argjson emails "$(printf '%s\n' "${EMAILS[@]}" | jq -R . | jq -s .)" \
      --argjson offset "$OFFSET" \
      --argjson limit "$LIMIT" \
      '{
        query: {
          paging: { offset: $offset, limit: $limit },
          filter: {
            and: [
              {
                or: [
                  { "accounts.userName": { "in": $emails } },
                  { "emails": { "in": $emails } }
                ]
              },
              { "accounts.deleted": { "eq": false } }
            ]
          },
          projection: ["accounts.userName", "accounts.scimId", "emails"]
        }
      }')")

  USERS=$(echo "$RESPONSE" | jq -r '.data[]? | [.accounts[0].userName, .accounts[0].scimId] | @tsv' || true)
  [[ -z "$USERS" ]] && break

  while IFS=$'\t' read -r USERNAME SCIM_ID; do
    [[ -z "$USERNAME" || -z "$SCIM_ID" ]] && continue
    FOUND_USERS+=("$USERNAME")
    SCIM_IDS+=("$SCIM_ID")
  done <<< "$USERS"

  TOTAL=$(echo "$RESPONSE" | jq -r '.totalCount // 0')
  (( OFFSET += LIMIT ))
  [[ $OFFSET -ge $TOTAL ]] && break
done

# Produce not found list
for EMAIL in "${EMAILS[@]}"; do
  if printf '%s\n' ${FOUND_USERS[@]+"${FOUND_USERS[@]}"} | grep -qx "$EMAIL"; then
    continue
  else
    NOT_FOUND_USERS+=("$EMAIL")
  fi
done

FOUND_COUNT=${#FOUND_USERS[@]}
NOT_FOUND_COUNT=${#NOT_FOUND_USERS[@]}
TOTAL_COUNT=${#EMAILS[@]}

# ---------------------------------------------------------------------------
# Summary of lookup results
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "Summary:"
echo "  Tenant:               $TENANT_FQDN"
echo "  Total Users:    	$TOTAL_COUNT"
echo "  Found:                $FOUND_COUNT"
echo "  Not Found:            $NOT_FOUND_COUNT"
echo "------------------------------------------------------------"

if [[ $FOUND_COUNT -eq 0 ]]; then
  echo ""
  echo "No matching users found. Nothing to delete."
  exit 0
fi

# ---------------------------------------------------------------------------
# Optional export
# ---------------------------------------------------------------------------

read -rp "Do you want to export found/not found lists? (y/n): " EXPORT
if [[ "$EXPORT" =~ ^[Yy]$ ]]; then
  printf '%s\n' ${FOUND_USERS[@]+"${FOUND_USERS[@]}"} > found_users.csv
  printf '%s\n' ${NOT_FOUND_USERS[@]+"${NOT_FOUND_USERS[@]}"} > not_found_users.csv
  echo "Exported found_users.csv and not_found_users.csv"
fi

# ---------------------------------------------------------------------------
# Confirm user deletion
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "You are about to delete ${#SCIM_IDS[@]} user(s)."
read -rp "Type DELETE to confirm: " CONFIRM
[[ "$CONFIRM" == "DELETE" ]] || { echo "Aborted."; exit 0; }

# ---------------------------------------------------------------------------
# Perform user deletions
# ---------------------------------------------------------------------------

DELETED_COUNT=0
ERROR_COUNT=0

for i in "${!SCIM_IDS[@]}"; do
  USER="${FOUND_USERS[$i]}"
  SCIM_ID="${SCIM_IDS[$i]}"
  echo -n "Deleting $USER: "
  if curl -sk -X DELETE "${DELETE_URL}/${SCIM_ID}" \
      -H "accept: */*" \
      -H "Authorization: Bearer ${API_TOKEN}" >/dev/null; then
    echo "OK"
    ((DELETED_COUNT++))
  else
    echo "Error"
    ((ERROR_COUNT++))
  fi
done

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

echo "------------------------------------------------------------"
echo "Summary:"
echo "  Tenant:               $TENANT_FQDN"
echo "  Total Users:    	$TOTAL_COUNT"
echo "  Found:                $FOUND_COUNT"
echo "  Not Found:            $NOT_FOUND_COUNT"
echo "  Deleted:              $DELETED_COUNT"
echo "  Errors:               $ERROR_COUNT"
echo "------------------------------------------------------------"
echo "Completed."
# Netskope-SCIM-Bulk-User-Deletion
Automate the bulk deletion of users in a Netskope tenant using the SCIM API

## Features
- Supports **macOS (Bash)**
- Accepts a CSV user list.
- Validates CSV input and skips invalid or blank lines.
- Handles authentication, errors, and summary reporting.

## Requirements
- A Netskope SCIM API token with permission to manage users.
- Bash 4+
- `curl`
- `jq`

## CSV Format
Each user email should be listed on a new line, e.g.,

`user1@example.com`

`user2@example.com`

Refer to the included `example_users.csv` file for a sample.

## Usage
**Syntax:** `./delete_netskope_users.sh <TENANT_FQDN> <API_TOKEN> <CSV_FILE>`

**Example:** `./delete_netskope_users.sh example.goskope.com abc123def456ghi789jk users.csv`


## License
Licensed under MIT — free to use, modify, and share, with no warranty.

## Disclaimer
This project is **not affiliated with or supported by Netskope**. It may be incomplete, outdated, or inaccurate. Use at your own risk.

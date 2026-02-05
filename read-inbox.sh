#!/usr/bin/env bash
set -euo pipefail

# Fastmail JMAP Inbox Reader
# Usage: FASTMAIL_TOKEN=your_api_token ./read-inbox.sh

if [[ -z "${FASTMAIL_TOKEN:-}" ]]; then
  echo "Error: FASTMAIL_TOKEN environment variable is required." >&2
  echo "Generate one at: Fastmail → Settings → Privacy & Security → API tokens" >&2
  exit 1
fi

JMAP_URL="https://api.fastmail.com/jmap"
AUTH_HEADER="Authorization: Bearer $FASTMAIL_TOKEN"

# Step 1: Get account ID from session endpoint
echo "Fetching session..." >&2
SESSION=$(curl -s -H "$AUTH_HEADER" "$JMAP_URL/session")

ACCOUNT_ID=$(echo "$SESSION" | jq -r '.primaryAccounts["urn:ietf:params:jmap:mail"]')

if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "null" ]]; then
  echo "Error: Failed to get account ID. Check your API token." >&2
  echo "$SESSION" >&2
  exit 1
fi

echo "Account ID: $ACCOUNT_ID" >&2

# Step 2: Find the Inbox mailbox ID
echo "Fetching inbox..." >&2
MAILBOX_RESPONSE=$(curl -s -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  "$JMAP_URL/api" \
  -d '{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Mailbox/query", {
      "accountId": "'"$ACCOUNT_ID"'",
      "filter": { "role": "inbox" }
    }, "findInbox"]
  ]
}')

INBOX_ID=$(echo "$MAILBOX_RESPONSE" | jq -r '.methodResponses[0][1].ids[0]')

if [[ -z "$INBOX_ID" || "$INBOX_ID" == "null" ]]; then
  echo "Error: Failed to find Inbox mailbox." >&2
  echo "$MAILBOX_RESPONSE" >&2
  exit 1
fi

# Step 3: Query emails in the Inbox
echo "Fetching messages..." >&2
RESPONSE=$(curl -s -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  "$JMAP_URL/api" \
  -d '{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Email/query", {
      "accountId": "'"$ACCOUNT_ID"'",
      "filter": { "inMailbox": "'"$INBOX_ID"'" },
      "sort": [{ "property": "receivedAt", "isAscending": false }],
      "limit": 10
    }, "emailList"],
    ["Email/get", {
      "accountId": "'"$ACCOUNT_ID"'",
      "#ids": {
        "resultOf": "emailList",
        "name": "Email/query",
        "path": "/ids"
      },
      "properties": ["subject", "from", "receivedAt", "preview"]
    }, "emailDetails"]
  ]
}')

# Step 4: Display results
echo "" >&2
echo "$RESPONSE" | jq -r '
  .methodResponses[1][1].list[]
  | "From:    \(.from[0].name // .from[0].email)"
  + "\nSubject: \(.subject)"
  + "\nDate:    \(.receivedAt)"
  + "\nPreview: \(.preview)"
  + "\n---"'

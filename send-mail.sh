#!/usr/bin/env bash
set -euo pipefail

# Fastmail JMAP Mail Sender
# Usage: FASTMAIL_TOKEN=your_api_token ./send-mail.sh -t recipient@example.com -s "Subject" -b "Body"

usage() {
  cat >&2 <<EOF
Usage: $0 [options]

Required:
  -t, --to ADDRESS        Recipient email address (repeatable)
  -s, --subject SUBJECT   Email subject line
  -b, --body BODY         Plain-text email body (or use --body-file)
  --body-file FILE        Read body from a file (- for stdin)

Optional:
  -c, --cc ADDRESS        CC recipient (repeatable)
  --bcc ADDRESS           BCC recipient (repeatable)
  -f, --from ADDRESS      From address (defaults to account's default identity)
  -h, --help              Show this help message

Environment:
  FASTMAIL_TOKEN          API token (required)
EOF
  exit 1
}

# Parse arguments
TO_ADDRS=()
CC_ADDRS=()
BCC_ADDRS=()
SUBJECT=""
BODY=""
BODY_FILE=""
FROM=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--to)      TO_ADDRS+=("$2"); shift 2 ;;
    -s|--subject) SUBJECT="$2"; shift 2 ;;
    -b|--body)    BODY="$2"; shift 2 ;;
    --body-file)  BODY_FILE="$2"; shift 2 ;;
    -c|--cc)      CC_ADDRS+=("$2"); shift 2 ;;
    --bcc)        BCC_ADDRS+=("$2"); shift 2 ;;
    -f|--from)    FROM="$2"; shift 2 ;;
    -h|--help)    usage ;;
    *)            echo "Unknown option: $1" >&2; usage ;;
  esac
done

# Validate required arguments
if [[ ${#TO_ADDRS[@]} -eq 0 ]]; then
  echo "Error: At least one --to address is required." >&2
  usage
fi

if [[ -z "$SUBJECT" ]]; then
  echo "Error: --subject is required." >&2
  usage
fi

if [[ -n "$BODY_FILE" ]]; then
  if [[ "$BODY_FILE" == "-" ]]; then
    BODY=$(cat)
  else
    BODY=$(cat "$BODY_FILE")
  fi
fi

if [[ -z "$BODY" ]]; then
  echo "Error: --body or --body-file is required." >&2
  usage
fi

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

# Step 2: Get the sender identity
echo "Fetching identity..." >&2
IDENTITY_RESPONSE=$(curl -s -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  "$JMAP_URL/api" \
  -d '{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:submission"],
  "methodCalls": [
    ["Identity/get", {
      "accountId": "'"$ACCOUNT_ID"'"
    }, "getIdentity"]
  ]
}')

if [[ -n "$FROM" ]]; then
  IDENTITY_ID=$(echo "$IDENTITY_RESPONSE" | jq -r --arg from "$FROM" \
    '.methodResponses[0][1].list[] | select(.email == $from) | .id' | head -1)
  if [[ -z "$IDENTITY_ID" || "$IDENTITY_ID" == "null" ]]; then
    echo "Error: No identity found for '$FROM'. Available identities:" >&2
    echo "$IDENTITY_RESPONSE" | jq -r '.methodResponses[0][1].list[] | "  \(.email)"' >&2
    exit 1
  fi
else
  IDENTITY_ID=$(echo "$IDENTITY_RESPONSE" | jq -r '.methodResponses[0][1].list[0].id')
  FROM=$(echo "$IDENTITY_RESPONSE" | jq -r '.methodResponses[0][1].list[0].email')
fi

if [[ -z "$IDENTITY_ID" || "$IDENTITY_ID" == "null" ]]; then
  echo "Error: Failed to get sender identity." >&2
  echo "$IDENTITY_RESPONSE" >&2
  exit 1
fi

echo "Sending as: $FROM" >&2

# Step 3: Get the Drafts mailbox ID
MAILBOX_RESPONSE=$(curl -s -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  "$JMAP_URL/api" \
  -d '{
  "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
  "methodCalls": [
    ["Mailbox/query", {
      "accountId": "'"$ACCOUNT_ID"'",
      "filter": { "role": "drafts" }
    }, "getDrafts"]
  ]
}')

DRAFTS_MAILBOX_ID=$(echo "$MAILBOX_RESPONSE" | jq -r '.methodResponses[0][1].ids[0]')

if [[ -z "$DRAFTS_MAILBOX_ID" || "$DRAFTS_MAILBOX_ID" == "null" ]]; then
  echo "Error: Could not find Drafts mailbox." >&2
  exit 1
fi

# Step 4: Build recipient JSON arrays
build_addr_array() {
  local addrs=("$@")
  local json="["
  local first=true
  for addr in "${addrs[@]}"; do
    if [[ "$first" == true ]]; then
      first=false
    else
      json+=","
    fi
    json+="{\"email\":$(echo "$addr" | jq -Rs .)}"
  done
  json+="]"
  echo "$json"
}

TO_JSON=$(build_addr_array "${TO_ADDRS[@]}")

CC_JSON="null"
if [[ ${#CC_ADDRS[@]} -gt 0 ]]; then
  CC_JSON=$(build_addr_array "${CC_ADDRS[@]}")
fi

BCC_JSON="null"
if [[ ${#BCC_ADDRS[@]} -gt 0 ]]; then
  BCC_JSON=$(build_addr_array "${BCC_ADDRS[@]}")
fi

# Step 5: Escape body and subject for JSON
SUBJECT_JSON=$(echo "$SUBJECT" | jq -Rs .)
BODY_JSON=$(echo "$BODY" | jq -Rs .)

# Step 6: Create draft and submit in one request
echo "Sending email..." >&2
SEND_RESPONSE=$(curl -s -X POST \
  -H "$AUTH_HEADER" \
  -H "Content-Type: application/json" \
  "$JMAP_URL/api" \
  -d '{
  "using": [
    "urn:ietf:params:jmap:core",
    "urn:ietf:params:jmap:mail",
    "urn:ietf:params:jmap:submission"
  ],
  "methodCalls": [
    ["Email/set", {
      "accountId": "'"$ACCOUNT_ID"'",
      "create": {
        "draft1": {
          "mailboxIds": { "'"$DRAFTS_MAILBOX_ID"'": true },
          "from": [{"email": '"$(echo "$FROM" | jq -Rs .)"'}],
          "to": '"$TO_JSON"',
          "cc": '"$CC_JSON"',
          "bcc": '"$BCC_JSON"',
          "subject": '"$SUBJECT_JSON"',
          "textBody": [{ "partId": "body", "type": "text/plain" }],
          "bodyValues": { "body": { "value": '"$BODY_JSON"' } },
          "keywords": { "$draft": true }
        }
      }
    }, "createEmail"],
    ["EmailSubmission/set", {
      "accountId": "'"$ACCOUNT_ID"'",
      "create": {
        "sub1": {
          "identityId": "'"$IDENTITY_ID"'",
          "emailId": "#draft1"
        }
      },
      "onSuccessDestroyEmail": ["#sub1"],
      "onSuccessUpdateEmail": {
        "#sub1": {
          "keywords/$draft": null,
          "keywords/$seen": true
        }
      }
    }, "submitEmail"]
  ]
}')

# Step 7: Check for errors
EMAIL_ERROR=$(echo "$SEND_RESPONSE" | jq -r '.methodResponses[0][1].notCreated // empty')
SUBMIT_ERROR=$(echo "$SEND_RESPONSE" | jq -r '.methodResponses[1][1].notCreated // empty')

if [[ -n "$EMAIL_ERROR" && "$EMAIL_ERROR" != "{}" ]]; then
  echo "Error creating email:" >&2
  echo "$EMAIL_ERROR" | jq . >&2
  exit 1
fi

if [[ -n "$SUBMIT_ERROR" && "$SUBMIT_ERROR" != "{}" ]]; then
  echo "Error submitting email:" >&2
  echo "$SUBMIT_ERROR" | jq . >&2
  exit 1
fi

echo "Email sent successfully!" >&2
echo "  To:      ${TO_ADDRS[*]}" >&2
[[ ${#CC_ADDRS[@]} -gt 0 ]] && echo "  CC:      ${CC_ADDRS[*]}" >&2
echo "  Subject: $SUBJECT" >&2

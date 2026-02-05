# Fastmail JMAP Inbox Reader

A shell script that fetches and displays the 10 most recent emails from your Fastmail inbox using the [JMAP API](https://jmap.io/).

## Prerequisites

- `curl`
- `jq`
- A Fastmail API token (see below)

## Getting a Fastmail API Token

1. Log in to [Fastmail](https://www.fastmail.com/)
2. Go to **Settings → Privacy & Security → API tokens**
3. Click **New API token**
4. Give it a name (e.g. "JMAP script")
5. Under permissions, ensure **Mail** read access is enabled
6. Click **Generate**
7. Copy the token — it won't be shown again

## Usage

```sh
FASTMAIL_TOKEN=your_api_token ./read-inbox.sh
```

## Output

For each email, the script displays:

- **From** — sender name or email
- **Subject** — email subject line
- **Date** — timestamp received
- **Preview** — short text preview of the message body

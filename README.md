# Fastmail JMAP Tools

Shell scripts for reading and sending email via your Fastmail account using the [JMAP API](https://jmap.io/).

## Prerequisites

- `curl`
- `jq`
- A Fastmail API token (see below)

## Getting a Fastmail API Token

1. Log in to [Fastmail](https://www.fastmail.com/)
2. Go to **Settings → Privacy & Security → API tokens**
3. Click **New API token**
4. Give it a name (e.g. "JMAP script")
5. Under permissions, ensure **Mail** read access and **Mail** send access are enabled
6. Click **Generate**
7. Copy the token — it won't be shown again

## Usage

### Read Inbox

Fetch and display the 10 most recent emails:

```sh
FASTMAIL_TOKEN=your_api_token ./read-inbox.sh
```

Output for each email includes: **From**, **Subject**, **Date**, and **Preview**.

### Send Mail

Send a plain-text email:

```sh
FASTMAIL_TOKEN=your_api_token ./send-mail.sh -t recipient@example.com -s "Hello" -b "Hi chuckles!"
```

Options:

| Flag | Description |
|------|-------------|
| `-t, --to ADDRESS` | Recipient email (required, repeatable) |
| `-s, --subject SUBJECT` | Email subject (required) |
| `-b, --body BODY` | Plain-text body (required unless using `--body-file`) |
| `--body-file FILE` | Read body from a file (`-` for stdin) |
| `-c, --cc ADDRESS` | CC recipient (repeatable) |
| `--bcc ADDRESS` | BCC recipient (repeatable) |
| `-f, --from ADDRESS` | From address (defaults to account's primary identity) |

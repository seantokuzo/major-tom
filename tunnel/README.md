# Cloudflare Tunnel for Major Tom

Persistent Cloudflare Tunnel so the relay server is always accessible from your phone without ad-hoc tunnel commands.

## Prerequisites

- **cloudflared** — `brew install cloudflared`
- A **domain managed by Cloudflare** (free tier works fine)

## One-Time Setup

```bash
cd relay
npm run tunnel:setup
```

This will:
1. Check that `cloudflared` is installed and authenticated
2. Create a named tunnel called `major-tom`
3. Ask for your subdomain (e.g., `majortom.yourdomain.com`)
4. Create the DNS route on Cloudflare
5. Generate `tunnel/config.yml` with your tunnel credentials

## Daily Usage

Start the relay server and tunnel together:

```bash
cd relay
npm run dev:remote
```

Or run them separately:

```bash
# Terminal 1: relay server
npm run dev

# Terminal 2: tunnel
npm run tunnel
```

The tunnel will expose your relay at `https://majortom.yourdomain.com` for browser access.

For the iOS app or other WebSocket clients, use `wss://majortom.yourdomain.com` as the endpoint (the relay listens on the root path, not `/ws`).

## Troubleshooting

**"config.yml not found"** — Run `npm run tunnel:setup` first.

**"cloudflared is not installed"** — `brew install cloudflared`

**"Not logged in"** — The setup script will prompt you to log in. If it fails, run `cloudflared tunnel login` manually.

**DNS not resolving** — It can take a few minutes for Cloudflare DNS to propagate. Check your Cloudflare dashboard under DNS records.

**Tunnel already exists** — That's fine. The setup script is idempotent and will reuse the existing tunnel.

**Connection refused** — Make sure the relay server is running on port 9090 (`npm run dev`).

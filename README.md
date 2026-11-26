# Deploy and Host Wealthfolio on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/wealthfolio-server?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=wealthfolio)

Wealthfolio is a private, local-first personal finance tracker. It follows your investment portfolio across brokers and accounts, along with net worth, income, dividends, contributions and spending. It fetches market prices for stocks, ETFs and crypto, charts performance over time, and runs simple retirement and savings simulations. You import activity from broker CSV files or enter it by hand, and the data stays in one SQLite database that you own. This template runs the official Wealthfolio 3.13.1 web edition on Railway with a persistent volume and a password login.

## About Hosting Wealthfolio

Deploy, wait for the green check, and open the Railway domain. Sign in with `WF_PASSWORD`, which is generated for you on the service's Variables tab. To choose your own password, change `WF_PASSWORD` and redeploy.

**Your data lives on the volume at `/data`:** one SQLite database per profile (`profiles/<id>/app.db`), the profile list, and the encrypted vault for saved credentials (`secrets.json`). Redeploys, restarts and upgrades keep them. Back the volume up with Railway's volume backups.

**Keep `WF_SECRET_KEY` as it is.** It encrypts saved credentials, such as market-data provider keys, and signs logins. If you change it after the first boot, Wealthfolio can no longer read the credentials it saved.

**Custom domain:** add it in Settings > Networking, then set `WF_CORS_ALLOW_ORIGINS=https://money.example.com` (exactly what you type in the browser, no trailing slash) and redeploy.

**Optional extras**, set as variables:
- **Single sign-on** with any OpenID Connect provider (Authentik, PocketID, Authelia…): `WF_OIDC_ISSUER_URL`, `WF_OIDC_CLIENT_ID`, `WF_OIDC_CLIENT_SECRET`, `WF_OIDC_REDIRECT_URL`, and an allowlist in `WF_OIDC_ALLOWED_EMAILS`.
- **AI agent access (MCP):** `WF_MCP_ENABLED=true`, then create a personal access token in the app's settings.
- **Login lifetime:** `WF_AUTH_TOKEN_TTL_MINUTES`, set to 1440 (one day) by this template. Upstream's default is 60.

## Common Use Cases

- Tracking a stock, ETF and crypto portfolio across several brokers in one place
- Following net worth over time, including cash, property and other assets
- Seeing dividends, income and contributions by month and year
- Budgeting and spending categories next to investments
- A private alternative to finance apps that sell or sync your data

## Dependencies for Wealthfolio Hosting

- None. One service with one volume; the database is SQLite on the volume.

### Deployment Dependencies

- [Wealthfolio on GitHub](https://github.com/wealthfolio/wealthfolio)
- [Wealthfolio self-hosting docs](https://wealthfolio.app/docs/guide/self-hosting/docker)
- [Template source](https://github.com/two-workspaces/wealthfolio)

### Implementation Details

- **Login:** Wealthfolio's server requires an Argon2id password hash. The template hashes `WF_PASSWORD` into `WF_AUTH_PASSWORD_HASH` on every boot, so you never handle a hash. If you set `WF_AUTH_PASSWORD_HASH` yourself, it's used as is. If `WF_PASSWORD` is empty, a password is generated once, printed in the deploy logs, and saved on the volume. The server allows 5 login attempts a minute.
- **Master key:** `WF_SECRET_KEY` is generated as a base64-encoded 32-byte key. A value that isn't one is replaced by its SHA-256, the same on every boot, rather than refusing to start.
- **CORS:** `WF_CORS_ALLOW_ORIGINS` is set from the Railway domain. Upstream refuses to start with a password and no explicit origin.
- **Never crash-looping on a variable:** if the server stops within a minute of starting, for example on an invalid OIDC setting, the service shows a "Wealthfolio is not running" page. The deploy logs say which variable to fix.
- **Volume ownership:** Railway mounts volumes as root, so the entrypoint hands `/data` to the image's user (uid 1000) and then runs the server as that user, like upstream.
- **Market data:** prices come from Yahoo Finance by default, and work from Railway (tested with a stock holding valued at the live price).
- **Memory:** the server idles at about 20 MB.
- **Healthcheck:** `/api/v1/healthz`.
- **Image:** upstream's `wealthfolio/wealthfolio:3.13.1`, pinned, plus a small entrypoint. The database migrates itself when the version is bumped.

## Why Deploy Wealthfolio on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Wealthfolio on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

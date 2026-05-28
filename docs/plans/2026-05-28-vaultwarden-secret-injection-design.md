# Vaultwarden Secret Injection Design

## Problem

The `.env` file at the repository root is the single source of secrets for all layers — from Proxmox host bootstrapping to Docker service configuration. This creates several issues:

- The monolithic `.env` is copied wholesale to the remote VM for every stack deploy, exposing all secrets to every container
- Changing any secret requires editing the file and re-running deploy
- No audit trail of which secrets exist or where they're used
- The file lives unencrypted on the controller filesystem

## Goal

Replace the monolithic `.env` with Vaultwarden as the source of truth for runtime service secrets. Keep only a minimal bootstrap `.env` for infrastructure provisioning and Vaultwarden itself.

## Design

### Bootstrap `.env` (remaining contents)

Only secrets needed **before** Vaultwarden is running:

```
HOST_ROOT_PASSWORD="..."
TF_USER_PASSWORD="..."
SSH_PUB_KEY_PATH="/root/.ssh/id_ed25519.pub"
VAULTWARDEN_ADMIN_TOKEN="..."
VAULTWARDEN_BW_CLIENTID="user.xxxx"
VAULTWARDEN_BW_CLIENTSECRET="..."
VAULTWARDEN_BW_PASSWORD="..."
```

All other secrets move to Vaultwarden items.

### Vaultwarden Organization

- **Organization:** "Homelab" — created once in the Vaultwarden admin UI
- **Collection:** "Deployment" — under the Homelab org, shared read-only with the deploy-bot user
- **Deploy-bot user:** Dedicated Vaultwarden user with API key access, used only for CI/deploy authentication

### Item Structure

Each stack directory in `03-services/stacks/` maps to one Vaultwarden **Login** item in the Deployment collection. Secrets are stored as **Custom Fields** (Text type):

| Item name | Custom fields |
|---|---|
| `gluetun` | GLUETUN_WIREGUARD_PRIVATE_KEY, GLUETUN_WIREGUARD_PRESHARED_KEY, GLUETUN_WIREGUARD_ADDRESSES |
| `stirlingpdf` | STIRLING_SECURITY_INITIALLOGIN_USERNAME, STIRLING_SECURITY_INITIALLOGIN_PASSWORD |
| `adguard` | ADGUARD_USER, ADGUARD_PASSWORD |
| `wireguard` | WGEASY_PASSWORD_HASH |
| `opencode` | OPENCODE_SERVER_PASSWORD, OPENROUTER_API_KEY |
| `openchamber` | OPENCHAMBER_UI_PASSWORD, GITHUB_SSH_PRIVATE_KEY_B64, GITHUB_TOKEN |
| `vaultwarden` | *(item used only to document its own deprecated vars; no fetch needed for its own deploy)* |

Items are fetched by name matching the stack name, then parsed via `bw get item <name> | jq -r '.fields[] | "\(.name)=\(.value)"'`.

### Deploy Flow

The `./run-docker.sh all` sequence changes to:

1. `host` — unchanged (uses bootstrap .env)
2. `infra` — unchanged (uses bootstrap .env)
3. `services install` — unchanged
4. `services deploy vaultwarden` — **deployed first**, uses bootstrap .env for its ADMIN_TOKEN
5. **bw login & unlock** — authenticate as deploy-bot user, cache session
6. `services deploy <remaining>` — each fetches its secrets from Vaultwarden before deploy

### Changes to `deploy_stack.yml`

The current playbook copies the entire `.env` to the remote VM. New behavior:

1. Receive secrets via Ansible extra-vars (passed from deploy.sh after `bw` fetch)
2. Generate a stack-specific `secrets.env` on the remote VM with only the vars that stack needs
3. Run `docker compose --env-file secrets.env up -d` (instead of relying on auto-detected `.env`)
4. Clean up `secrets.env` from the remote VM after deploy

AdGuard's Jinja2 template rendering continues to work the same way — `ADGUARD_PASSWORD` is fetched from Vaultwarden (plaintext), hashed via Ansible's `password_hash('bcrypt')` filter, and injected into the template. No change to the template logic.

### Changes to `Dockerfile`

Install `bw` (Bitwarden CLI) in the builder image:
```dockerfile
RUN curl -fsSL https://github.com/bitwarden/clients/releases/download/cli-v2025.x.x/bw-linux-xxx.zip \
    -o /tmp/bw.zip && unzip /tmp/bw.zip -d /usr/local/bin && rm /tmp/bw.zip
```

### New Helper Functions in `deploy.sh`

```bash
bw_login_and_unlock() {
  export BW_CLIENTID="$VAULTWARDEN_BW_CLIENTID"
  export BW_CLIENTSECRET="$VAULTWARDEN_BW_CLIENTSECRET"
  bw login --apikey > /dev/null 2>&1
  export BW_SESSION=$(bw unlock --passwordenv VAULTWARDEN_BW_PASSWORD --raw)
  bw sync
}

fetch_stack_secrets() {
  local stack_name=$1
  mkdir -p /tmp/secrets
  bw get item "$stack_name" \
    | jq -r '.fields[] | "\(.name)=\(.value)"' \
    > /tmp/secrets/$stack_name.env
}
```

### Error Handling

- **Vaultwarden unreachable:** `bw login` failure halts the deploy with a clear error message. A `.secrets.env.local` fallback file can be placed on the controller for emergency deploys during Vaultwarden restoration.
- **Missing Vaultwarden item:** If `bw get item <stack_name>` returns empty (or no item found), deploy fails with: "Create a Vaultwarden item named '<stack_name>' in the Deployment collection first."
- **Session caching:** A single `bw unlock --raw` at the start of the deploy phase caches the session for all subsequent stack fetches — no need to re-authenticate per-stack.
- **Cleanup:** Temporary `secrets.env` files on the controller live under `/tmp/secrets/` and are cleaned after the deploy phase completes. Remote VM's `secrets.env` is deleted post-deploy (matching current `.env` cleanup behavior).

### One-Time Setup

1. Create the "Homelab" organization in Vaultwarden
2. Create the "Deployment" collection under it
3. Create the deploy-bot user, assign to the collection (read-only)
4. Generate an API key for deploy-bot (client_id + client_secret)
5. Create one Vaultwarden item per stack with custom fields
6. Add the deployment user's credentials to the bootstrap `.env`
7. Run `./run-docker.sh all` to verify

### Decommissioning

Once all stacks are verified against Vaultwarden, the old monolithic `.env` can be stripped down to only the bootstrap vars listed above. The `.env.example` should be updated to reflect the new minimal format and document the manual Vaultwarden setup steps.

# AGENTS.md — Operational Cheat-Sheet

For full architecture and usage details, see [README.md](./README.md).

## Always wrap with `./run-docker.sh`

Never run `./deploy.sh` directly — `validate.sh` rejects it if Terraform, Ansible, etc. are missing from the host. All tooling lives inside the `Dockerfile` image.

```bash
./run-docker.sh <command>
```

## SSH agent must be running

Ansible inside the container needs SSH agent forwarding. Before any `run-docker.sh` call:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

`run-docker.sh` auto-mounts `SSH_AUTH_SOCK`.

## Layer order is strict

`./run-docker.sh all` executes sequentially:

1. `host` — configures Proxmox (repos, user, cloud template, WoL)
2. `infra` — Terraform clones VM from cloud-init template
3. `services install` — installs Docker on the VM
4. `services deploy all` — starts all stacks from `03-services/stacks/`

No layer can be skipped — each depends on the previous.

## Secrets: bootstrap .env + Vaultwarden

The `.env` holds only **bootstrap secrets** (infrastructure creds + Vaultwarden deploy-bot API key). All runtime service secrets live in Vaultwarden items under the "Deployment" collection.

The `all` deploy flow:
1. Deploys vaultwarden with bootstrap `VAULTWARDEN_ADMIN_TOKEN`
2. Authenticates via `bw login --apikey` as the deploy-bot user
3. Fetches per-stack secrets via `bw get item <stack_name>`
4. Passes them as `secrets_env_file` to `deploy_stack.yml`
5. Docker Compose reads them via `--env-file secrets.env`

## config.json is the single source of truth

| Key | Used by |
|---|---|
| `host.*` | ISO generation (answer.toml), host Ansible, Terraform env vars |
| `vm.*` | Terraform, services inventory |
| `proxmox.tf_user` | Host Ansible, Terraform auth |
| `proxmox.iso_version` | ISO build — must match `proxmox-ve_<version>.iso` in repo root |

Parse with `jq -r .host.ip config.json`, etc.

## SSH user differs per target

- **Proxmox host**: `root` (key injected by custom ISO)
- **Debian VM**: `debian` (cloud-init user)

`deploy.sh` builds inventory.ini fragments inline — don't look for a static inventory file.

## Backup/restore invariants

- Only **Docker named volumes** are backed up (`/var/lib/docker/volumes/`). Bind mounts are silently ignored.
- `services delete <name>` keeps volumes so `services restore <name>` can overwrite them, then `services deploy <name>` re-attaches.
- Backups land in `./backups/<stack>/` on the controller (gitignored).

## Services layer commands

```bash
./run-docker.sh services install             # Docker Engine on VM
./run-docker.sh services deploy <name|all>   # Start stack(s)
./run-docker.sh services delete <name|all>   # Stop & remove stack(s) (volumes kept)
./run-docker.sh services backup <name>       # Snapshot volumes to ./backups/
./run-docker.sh services restore <name>      # Restore from ./backups/ to VM
```

Stack names match directories under `03-services/stacks/`. Some have Jinja2 `.j2` config templates alongside their `docker-compose.yml`.

## No build/test/lint pipeline

This is IaC, not a software project. There are no npm scripts, test runners, linters, or CI. Verification is operational: ping hosts, `ssh` into them, or check service health via Caddy/Portainer.
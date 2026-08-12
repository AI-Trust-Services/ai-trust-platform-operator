# Claude Code — Cluster Authentication Guide (ai-trust-1 / Gardener)

This guide is for **Claude Code** (and any operator driving `kubectl` from Windows + WSL) to
authenticate to the Gardener shoot that hosts Platform Mesh and the AI Trust app. It captures the
**one working path** and the **dead ends** — follow it exactly to avoid the hours we lost discovering it.

> TL;DR: the shoot kubeconfig uses the **gardenlogin** exec plugin. The plugin needs a one-time
> **browser login** that only the **user** can complete (Claude cannot open a browser). After that,
> gardenlogin caches a short-lived cert (~15 min) and Claude's `kubectl` calls work non-interactively
> until it expires. Refresh by re-running `login.sh` in the **Ubuntu terminal**.

---

## The environment

- **Shoot:** `ai-trust-1` in Gardener project `garden-ai-trust`, landscape `landscape-apeirora-one`.
- **Shoot API:** `https://api.ai-trust-1.ai-trust.shoot.gardener.cc-one.showroom.apeirora.eu`
- **Garden dashboard:** `https://dashboard.ingress.garden.gardener.cc-one.showroom.apeirora.eu/namespace/garden-ai-trust/shoots`
- Runs on **Windows 11 + WSL2 Ubuntu**. Claude runs commands via `wsl.exe`.
- The kubeconfig the user downloads from the dashboard is the **gardenlogin format**:
  `user.exec.command: kubectl-gardenlogin get-client-certificate` — it "does not contain credentials
  (requires the gardenlogin kubectl plugin)". Save it as `prerequisites/garden-kubeconfig.yaml`
  (or wherever the bundle expects) **and** as `config/kubeconfig-ai-trust-1.yaml` for ad-hoc use.

---

## One-time WSL setup (non-interactive — Claude can do this)

1. **Install the gardenlogin plugin** (v0.10.0, linux amd64) to `~/.local/bin`:
   ```bash
   curl -fsSL -o ~/.local/bin/kubectl-gardenlogin \
     https://github.com/gardener/gardenlogin/releases/download/v0.10.0/gardenlogin_linux_amd64
   chmod +x ~/.local/bin/kubectl-gardenlogin
   ln -sf ~/.local/bin/kubectl-gardenlogin ~/.local/bin/gardenlogin
   ```
2. **Write `~/.garden/gardenlogin.yaml` AND `~/.garden/gardenctl-v2.yaml`** (gardenlogin reads the
   former; both point at the garden cluster kubeconfig):
   ```yaml
   gardens:
     - identity: landscape-apeirora-one
       kubeconfig: "/mnt/c/claude/projects/eu-ai-trust-platform/config/kubeconfig-garden-ai-trust.yaml"
   ```
3. **Fix the kubelogin plugin name** — kubectl v1.36 resolves the `oidc-login` subcommand by looking
   for `kubectl-oidc_login` (UNDERSCORE), but the binary is usually `kubectl-oidc-login` (hyphens):
   ```bash
   ln -sf ~/.local/bin/kubectl-oidc-login ~/.local/bin/kubectl-oidc_login
   ```
   Without this symlink, `kubectl oidc-login` fails with `unknown command "oidc-login"`.

---

## The login (INTERACTIVE — only the USER can do this)

gardenlogin → the garden kubeconfig → an OIDC **browser** flow. Claude **cannot** complete it
(no browser in WSL; `xdg-open` missing; a non-interactive spawn cancels the flow → "context canceled").

**The user runs this ONE short line in the Ubuntu terminal** (the `mircea@...:~$` prompt):

```bash
bash /mnt/c/claude/projects/eu-ai-trust-platform/config/login.sh
```

`login.sh` runs `KUBECONFIG=config/kubeconfig-ai-trust-1.yaml kubectl get ns`. It opens a browser (WSLg)
or prints a `http://localhost:8000/` URL — the user logs in with SAP creds, and it prints the
namespace list. That **caches a shoot client cert** to `~/.kube/cache/gardenlogin/`, after which
**Claude's kubectl calls reuse it** non-interactively.

**Critical do's and don'ts for running the login command:**
- Run it in the **Ubuntu/WSL terminal**, NOT PowerShell. In PowerShell `!` is a special operator and
  a `!`-prefixed command errors with *"Missing expression after unary operator '!'"*.
- The `!` prefix (`! <cmd>`) only works **inside the Claude Code prompt**, not in any OS shell.
- Keep the command on **one physical line** — a wrapped multi-line paste breaks into separate
  commands and fails (`--oidc-issuer-url ... : No such file or directory`).

**Cert lifetime:** the gardenlogin cert lasts **~15 minutes**. When Claude reports
`Unable to connect ... gardenlogin failed` / `context deadline exceeded`, the user re-runs `login.sh`.

---

## Verifying access (Claude)

```bash
KUBECONFIG=/mnt/c/claude/projects/eu-ai-trust-platform/config/kubeconfig-ai-trust-1.yaml \
  kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
# MUST be https://api.ai-trust-1.ai-trust.shoot.gardener.cc-one... — NOT https://0.0.0.0:... (that's the
# local kind cluster fallback that appears when the shoot cert has expired). Always check this first.
KUBECONFIG=... kubectl get ns    # should list ai-trust-app, platform-mesh-system, etc.
```

---

## WSL execution gotchas (Claude MUST follow — these cost real time)

1. **Run commands from a SCRIPT FILE, not inline `-c`/`-lc`.** Inline
   `wsl.exe -- bash -c '...$VAR...'` **loses shell variables** (they expand to empty), and a **login
   shell (`-lc`)** RESETS `$PATH` to the Windows-merged one where `kubectl.exe` (Windows) shadows the
   Linux `kubectl` and can't exec Linux credential plugins. Write the script to a file and run:
   ```bash
   MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu -- bash '/mnt/c/.../script.sh' 2>&1 | tr -d '\0'
   ```
   Start every script with:  `export PATH=/home/mircea/.local/bin:/usr/local/bin:/usr/bin:/bin`
2. **Use `KUBECONFIG=<file>` env, not the `--kubeconfig` flag** — a kubectl alias/wrapper mangles
   `--kubeconfig` placed before the plugin name (`flags cannot be placed before plugin name`).
3. **Pipe through `tr -d '\0'`** — WSL output carries NUL bytes.
4. **Linux kubectl** = `/usr/local/bin/kubectl` (Docker Desktop symlink). Ensure it wins on `$PATH`.
5. **kcp workspace access:** port-forward `svc/root-proxy:6443` (NOT frontproxy-front-proxy:8443 over a
   raw forward), strip the CA from the kcp-admin kubeconfig + `--insecure-skip-tls-verify`, and target
   sub-workspaces by rewriting the server path to `.../clusters/root:orgs:<org>` etc. `kubectl apply`
   to kcp often needs `--validate=false`; **merge patches are rejected by the kcp openapi — use full
   `kubectl replace`** (strip `managedFields` + `creationTimestamp`).
6. **Background `port-forward &` scripts** may not flush stdout to the harness until they exit — kill
   the port-forward at the end of the script so output returns.

---

## Dead ends — DO NOT waste time here (all tried, all failed)

- **DevTools/dashboard cookie token** as a Bearer → it is a **JWE** (`eyJlbmMi...`,
  `"enc":"A128CBC-HS256"`), the dashboard's *encrypted session*, NOT a signed API token → Gardener
  API returns **401**. Only a signed OIDC ID token (`eyJhbGciOiJSUzI1Ni...`) works.
- **Reusing the old `.mintsr.sh` bearer token** → it expires (~1h). Only a freshly completed
  oidc-login yields a usable token.
- **Claude running oidc-login non-interactively** (any grant-type: auto / authcode / authcode-keyboard
  / device-code) → always needs a browser or a waiting prompt → "context canceled". Not possible from
  Claude's side. The user must do the browser step.
- **Trusting `kubectl config view` when the cert expired** → it silently falls back to the local kind
  cluster (`0.0.0.0:41887`, `portal.localhost`, mkcert cert). Always verify the server is the real
  `*.shoot.gardener.cc-one...` before applying anything.

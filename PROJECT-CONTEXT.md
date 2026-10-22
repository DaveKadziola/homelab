# PROJECT-CONTEXT.md

Facts of this project for the agent rules in `AGENTS.md`. Every filled field names its source.
An empty field is unknown: the agent asks about it and assumes nothing.

Status: draft (takeover 2026-10-18; operator answers recorded 2026-10-18)
Last reviewed: 2026-10-21

## 1. Goal

- What this project is for: self-hosted homelab on Proxmox - Terraform + Ansible + Docker
  Compose, deployed through GitHub Actions with two self-hosted runners.
  <!-- source: README.md first paragraph -->
- Plan and phases: the backlog is the frontmatter of `docs/plan/greenfield-plan.md`.
  The F0-F10 write-up is `docs/plan/greenfield-notes.md` and is not the current procedure.
  Current status: `README.md` "Status".
  <!-- source: docs/plan/greenfield-plan.md frontmatter; docs/plan/greenfield-notes.md "Phases / sprints"; README.md "Status" -->
- Who uses it: the operator (user and admin); later 1-2 occasional users of single apps such as
  the photo gallery and the shopping list. <!-- source: operator, 2026-10-18 -->
- What is out of scope: <ask>

## 2. Stack

| Area | Choice and version | Source |
| --- | --- | --- |
| Languages | Bash (`utils/`, `tests/`), Python helpers (`tests/lib/hlconfig.py`, `utils/bootstrap/homarr_board.py`), HCL, YAML | repository tree |
| Runtime / OS | Ubuntu VMs `ubuntu-apps`, `ubuntu-nas` on a physical Proxmox host; DEV: nested Proxmox in laptop libvirt. VMs run the Ubuntu 24.04 (noble) cloud image | `README.md` "How it is built"; `docs/network.md:6-13`; `terraform/environments/dev/terraform.tfvars:41`; `terraform/environments/prod/terraform.tfvars:43,70` |
| Infrastructure as code | Terraform `>= 1.8.0`, provider `bpg/proxmox` `0.77.1`; Terraform Cloud org `dkhomelabserver`, workspaces `homelab` (prod) and `homelab-dev` (DEV), chosen by `TF_WORKSPACE`, execution mode local | `terraform/versions.tf:2,6-7`; `terraform/cloud.tf` |
| Configuration | Ansible (`ansible/playbooks/`, inventories `ansible/environments/{dev,prod}/hosts.ini`), ansible-lint profile `production`. Ansible version: not pinned | `ansible/ansible.cfg`; `.ansible-lint` |
| Applications | Docker Compose (`compose/core`, `compose/grocery`); services declared once in `config/services.yml`, accounts and secret names in `config/identities.yml` | `README.md` "Applications" |
| CI | GitHub Actions on self-hosted runners `homelab-dev` (laptop) and `homelab-prod` (LXC `ci-runner` on the prod Proxmox host) | `.github/workflows/*.yml` `runs-on`; `utils/pve-ci-runner-lxc.sh` |
| Secrets | `utils/gen-app-credentials.sh` writes each value to the GitHub environment, `~/.homelab-secrets/<env>/` and Bitwarden `homelab/<NAME>/<env>` in one run | `README.md` "Where to start" (Secrets); `knowledge/security.md` "Identities" |

## 3. Constraints

- Hard limits: <ask>. Prod runs since F3: VMs 101, 102 and CT 110 on `192.168.20.20`.
  <!-- source: qm list, pct list on 192.168.20.20 (2026-10-20) -->
- Security: secret values never enter git; names only in `docs/secrets-inventory.md`. gitleaks
  runs in CI. OPNsense `config.xml` backups stay in the gitignored `opnsense/backups/`.
  The repository is **public**: anything committed is published.
  <!-- source: README.md second paragraph; .github/workflows/ci-validate.yml:53 (Gitleaks); .gitignore -->
- Compatibility: <ask>
- Things the agent must never touch without an explicit request each time:
  - `main` and anything that triggers prod workflows (push to `main` applies Terraform and
    deploys apps on prod). <!-- source: .github/workflows/infra-apply-prod.yml, apps-deploy-prod.yml -->
  - Direct pushes to `homelab-v2` (they trigger DEV Terraform apply and app deploy). Changes reach
    it only through a PR; the agent turns on auto-merge (`gh pr merge --auto --merge`) after
    `Infra Plan Dev` shows no VM replace or destroy. Never `[skip ci]`.
    <!-- source: .github/workflows/infra-apply-dev.yml, apps-deploy-dev.yml; knowledge/decisions/0004-ci-autonomy-and-prod-risk-gate.md -->
  - Approving deployments (`prod`, `prod-gate`), editing rulesets, environments or repo settings,
    and starting prod workflows. <!-- source: knowledge/decisions/0004-ci-autonomy-and-prod-risk-gate.md -->
  - `terraform apply` whose plan replaces `ubuntu-apps` - it wipes Docker volumes.
    <!-- source: knowledge/deployment.md:53 -->
  - The OPNsense router and its live configuration.
  - Merging the release PR `homelab-v2` -> `main`: the operator merges it. The F9 gate that blocked
    it is met: wipe drill passed 2026-10-19, prod built from `main` by release #75 (2026-10-20).
    <!-- source: README.md "Change flow", "Status"; knowledge/rebuild-drill-2026-10-19b.md -->

## 4. Commands

| Purpose | Command | Notes |
| --- | --- | --- |
| Install dependencies | - | Tools expected on the laptop: `git`, `gh`, `terraform`, `ansible`, `ansible-lint`, `docker`, `virsh`, `virt-install`, `openssl` (`README.md` "Where to start") |
| Build | - | nothing to build |
| Test (all) | `utils/run-tests.sh --env dev --suite all` | `README.md` "Where to start"; `all` = smoke, infra, net, config, storage, ha (`utils/run-tests.sh:15`); `restore` is opt-in and not in `all` |
| Test (single) | `utils/run-tests.sh --env dev --suite <smoke\|infra\|net\|config\|storage\|ha\|restore>` | `utils/run-tests.sh:4`. Only `config` is static; `ha` talks to the Home Assistant API (`utils/ha.py`), the others reach DEV hosts over SSH |
| Lint / format | `terraform fmt -check -recursive`; `terraform validate`; `ansible-lint ansible/playbooks/`; `docker compose --profile auth --profile media config` (in `compose/core`, needs placeholder env values); `./utils/pve-attach-nas-disks.sh --self-test`; `python3 utils/pve-network.py --self-test`; `python3 utils/bw-store.py --self-test`; `python3 utils/tf-plan-risk.py --self-test`; `python3 utils/ha.py --self-test`; `python3 utils/backup/check-fresh.py --self-test`; `python3 utils/pve-backup-job.py --self-test`; `python3 utils/gen-proxy-config.py --self-test`; `python3 utils/kuma-sync.py --self-test`; `python3 utils/bootstrap/beszel_config.py --self-test`; `python3 utils/prepare-infra.py --self-test` | `.github/workflows/ci-validate.yml` (step "Script self-tests") |
| Kit check | `python3 scripts/validate_kit.py` | agent kit |
| Run locally | - | |
| Deploy | through GitHub Actions on push | Never run by the agent without an explicit request |

## 5. Local conventions

- Repository layout: `README.md` "Repository layout"; knowledge base in `knowledge/` (layout in
  `knowledge/README.md`); plan in `docs/plan/`; audits of the takeover in `docs/audit/`.
- Naming: follow the existing code and files. <!-- source: operator, 2026-10-18 -->
- Code style: follow the existing code of the file being changed. <!-- source: operator, 2026-10-18 -->
- Scripting language for tooling: new tooling in Python; Bash only for thin wrappers and for
  extending the existing scripts in `utils/`. <!-- source: operator, 2026-10-18 -->
- Toolchain mangles non-ASCII characters: no evidence; the repository already uses UTF-8
  typography in docs and scripts.
- Release notes / change log file: none.
- README reference examples: app pages follow `knowledge/apps/<app>.md`; adding an app is
  `config/services.yml` -> compose -> `knowledge/apps/<app>.md`. <!-- source: README.md "Applications" -->
- Commits: `type(scope): subject`, scope = phase (`f1` ... `f10`) when there is one.
  <!-- source: git log main..homelab-v2 -->
- Branching and review: `homelab-v2` = DEV, `main` = prod. Agent work happens on a feature branch
  and reaches `homelab-v2` through a PR that merges itself when `validate` and `plan` pass (ruleset
  without bypass). A release is a PR `homelab-v2` -> `main` that the operator merges; prod asks for
  one approval on Infra Apply Prod (`prod-approve`), plus `prod-gate` when the Terraform plan is risky. A successful apply starts Apps Deploy Prod with no second click.
  <!-- source: operator decisions 2026-10-18 and 2026-10-20; knowledge/decisions/0004-ci-autonomy-and-prod-risk-gate.md -->
- Tools that talk to outside services (rclone, Terraform, ...): the newest stable upstream release,
  pinned by version and SHA256 (Terraform: `utils/pve-ci-runner-lxc.sh`, rclone:
  `ansible/playbooks/deploy-storage.yml`), not the distribution package, which lags years behind
  (Ubuntu ships rclone 1.60.1 from 2022, also in 26.04).
  <!-- source: operator 2026-10-21 -->
- Language: answers in the operator's language (Polish); repository content in English,
  including `docs/plan/`.
- Deviations from `AGENTS.md`: none. The knowledge base keeps its own page layout, described in
  `knowledge/README.md`.

## 6. Environments

| Name | Host / location | Purpose | Agent may change it? |
| --- | --- | --- | --- |
| dev | Laptop libvirt `192.168.122.0/24`; nested Proxmox; `ubuntu-apps-dev` `192.168.122.50` (SSH user `ubuntu-dev`, key `~/.ssh/homelab_dev_ed25519`) | DEV, branch `homelab-v2` | yes - tests, SSH, deploys (operator, 2026-10-18); deleting data or replacing a VM still asked each time (`AGENTS.md` section 11) |
| prod | Proxmox host `192.168.20.20`; `ubuntu-apps` `192.168.50.30`; `ubuntu-nas` `192.168.20.12`; HA T620 `192.168.20.13` | prod, branch `main`; running (qm list, 2026-10-20) | no |
| router | OPNsense, VLAN gateways in `docs/network.md:23-28` | home network | no |

<!-- source: docs/network.md:10-12,23-47; ansible/environments/{dev,prod}/hosts.ini -->

## 7. Glossary

| Term | Meaning here | Source |
| --- | --- | --- |
| F0-F10 | Plan phases (F0 manual setup ... F9 audits and merge gate, F10 monitoring after prod) | `docs/plan/greenfield-notes.md` "Phases / sprints" |
| P0 / P1 / P2 | Application priority tiers | `docs/apps-sources.md:8,25` |
| greenfield / v2 | The rebuild on `homelab-v2`; pre-v2 code is legacy | `README.md` title; `docs/plan/greenfield-notes.md` "Git strategy — branch `homelab-v2`" |
| F9 gate | Conditions for merging `homelab-v2` into `main` | `knowledge/rebuild-drill-2026-09-10.md:7,48-55` |
| IOT / APP / WireGuard | Prod VLANs and the VPN network | `docs/network.md:23-28` |

## 8. Open questions

- `utils/bootstrap-secrets.sh` (F1 one-shot, no dry run) overwrites live `dev` and `prod` secrets
  with random values and sets `PROXMOX_API_TOKEN_ID` to `homelab-<env>@pam!terraform`, a user the
  nested DEV PVE does not have (DEV uses `root@pam!terraform`). Retire it or guard it - operator
  decision.
  <!-- source: utils/bootstrap-secrets.sh:34-42; pveum user token list homelab-dev@pam on 192.168.122.219 (2026-10-20) -->
- Is the ISP public address static? Nothing on the router updates the Cloudflare A record of
  `grocery.dkhomelabserver.xyz` (no dynamic DNS section in `/conf/config.xml`, 2026-10-20).
- `docs/wireguard.md` and `docs/opnsense-baseline.md` give APP as `192.168.50.0/24`, which also
  covers the DMZ `.64/28`; APP is `192.168.50.0/26` (`ifconfig vlan07`, `config.xml` opt6). Should
  WireGuard clients reach the DMZ? Operator decision before the docs change.

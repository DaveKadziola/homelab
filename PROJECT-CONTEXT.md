# PROJECT-CONTEXT.md

Facts of this project for the agent rules in `AGENTS.md`. Every filled field names its source.
An empty field is unknown: the agent asks about it and assumes nothing.

Status: draft (takeover 2026-10-18; operator answers recorded 2026-10-18)
Last reviewed: 2026-10-18

## 1. Goal

- What this project is for: self-hosted homelab on Proxmox - Terraform + Ansible + Docker
  Compose, deployed through GitHub Actions with two self-hosted runners.
  <!-- source: README.md:3 -->
- Plan and phases: `docs/plan/greenfield-plan.md` (phases F0-F10; copied from Cursor, its todo
  statuses are older than the code). Current status: `README.md` "Roadmap" table.
  <!-- source: docs/plan/greenfield-plan.md "Fazy / sprinty"; README.md "Roadmap" -->
- Who uses it: the operator (user and admin); later 1-2 occasional users of single apps such as
  the photo gallery and the shopping list. <!-- source: operator, 2026-10-18 -->
- What is out of scope: <ask>

## 2. Stack

| Area | Choice and version | Source |
| --- | --- | --- |
| Languages | Bash (`utils/`, `tests/`), Python helpers (`tests/lib/hlconfig.py`, `utils/bootstrap/homarr_board.py`), HCL, YAML | repository tree |
| Runtime / OS | Ubuntu VMs `ubuntu-apps`, `ubuntu-nas` on a physical Proxmox host; DEV: nested Proxmox in laptop libvirt. VMs run the Ubuntu 24.04 (noble) cloud image | `README.md` architecture; `docs/network.md:6-13`; `terraform/environments/dev/terraform.tfvars:41`; `terraform/environments/prod/terraform.tfvars:40,66` |
| Infrastructure as code | Terraform `>= 1.8.0`, provider `bpg/proxmox` `0.77.1`; Terraform Cloud org `dkhomelabserver`, workspaces `homelab` (prod) and `homelab-dev` (DEV), chosen by `TF_WORKSPACE`, execution mode local | `terraform/versions.tf:2,6-7`; `terraform/cloud.tf` |
| Configuration | Ansible (`ansible/playbooks/`, inventories `ansible/environments/{dev,prod}/hosts.ini`), ansible-lint profile `production`. Ansible version: not pinned | `ansible/ansible.cfg`; `.ansible-lint` |
| Applications | Docker Compose (`compose/core`, `compose/grocery`); services declared once in `config/services.yml`, accounts and secret names in `config/identities.yml` | `README.md` "Applications" |
| CI | GitHub Actions on self-hosted runners `homelab-dev` (laptop) and `homelab-prod` (LXC `ci-runner` on the prod Proxmox host) | `.github/workflows/*.yml` `runs-on`; `utils/pve-ci-runner-lxc.sh` |
| Secrets | Generated locally -> Bitwarden `homelab/<NAME>/<env>` -> `gh secret set`; app secrets from `utils/gen-app-credentials.sh`; local copies in `~/.homelab-secrets/<env>/` | `README.md:76,78,146` |

## 3. Constraints

- Hard limits: the physical prod host is offline until F3 metal is done, so prod checks SKIP.
  <!-- source: tests/README.md:50; README.md "Roadmap" -->
- Security: secret values never enter git; names only in `docs/secrets-inventory.md`. gitleaks
  runs in CI. OPNsense `config.xml` backups stay in the gitignored `opnsense/backups/`.
  The repository is **public**: anything committed is published.
  <!-- source: README.md:76; .github/workflows/ci-validate.yml:54; .gitignore -->
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
  - Merging `homelab-v2` into `main` while the F9 gate is FAIL.
    <!-- source: knowledge/rebuild-drill-2026-09-10.md:7 -->

## 4. Commands

| Purpose | Command | Notes |
| --- | --- | --- |
| Install dependencies | - | Tools expected on the laptop: `git`, `gh`, `terraform`, `ansible`, `ansible-lint`, `docker`, `virsh`, `virt-install`, `openssl` (`README.md:72`) |
| Build | - | nothing to build |
| Test (all) | `utils/run-tests.sh --env dev --suite all` | `README.md:119`; `restore` is opt-in and not in `all` |
| Test (single) | `utils/run-tests.sh --env dev --suite <smoke\|infra\|net\|config\|restore>` | `utils/run-tests.sh:4`. Only `config` is static; the others reach DEV hosts over SSH |
| Lint / format | `terraform fmt -check -recursive`; `terraform validate`; `ansible-lint ansible/playbooks/`; `docker compose --profile auth --profile media config` (in `compose/core`, needs placeholder env values); `./utils/pve-attach-nas-disks.sh --self-test`; `python3 utils/pve-network.py --self-test`; `python3 utils/bw-store.py --self-test`; `python3 utils/tf-plan-risk.py --self-test`; `python3 utils/ha.py --self-test`; `python3 utils/backup/check-fresh.py --self-test`; `python3 utils/pve-backup-job.py --self-test`; `python3 utils/gen-proxy-config.py --self-test`; `python3 utils/kuma-sync.py --self-test` | `.github/workflows/ci-validate.yml` (step "Script self-tests") |
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
  `config/services.yml` -> compose -> `knowledge/apps/<app>.md`. <!-- source: README.md:143 -->
- Commits: `type(scope): subject`, scope = phase (`f1` ... `f10`) when there is one.
  <!-- source: git log main..homelab-v2 -->
- Branching and review: `homelab-v2` = DEV, `main` = prod. Agent work happens on a feature branch
  and reaches `homelab-v2` through a PR that merges itself when `validate` and `plan` pass (ruleset
  without bypass). A release is a PR `homelab-v2` -> `main` that the operator merges; prod asks for
  approval only when the Terraform plan is risky (environment `prod-gate`).
  <!-- source: operator decisions 2026-10-18 and 2026-10-20; knowledge/decisions/0004-ci-autonomy-and-prod-risk-gate.md -->
- Language: answers in the operator's language (Polish); repository content in English. The plan
  in `docs/plan/` is in Polish and stays so.
- Deviations from `AGENTS.md`: none. The knowledge base keeps its own page layout, described in
  `knowledge/README.md`.

## 6. Environments

| Name | Host / location | Purpose | Agent may change it? |
| --- | --- | --- | --- |
| dev | Laptop libvirt `192.168.122.0/24`; nested Proxmox; `ubuntu-apps-dev` `192.168.122.50` (SSH user `ubuntu-dev`, key `~/.ssh/homelab_dev_ed25519`) | DEV, branch `homelab-v2` | yes - tests, SSH, deploys (operator, 2026-10-18); deleting data or replacing a VM still asked each time (`AGENTS.md` section 11) |
| prod | Proxmox host `192.168.20.20`; `ubuntu-apps` `192.168.50.30`; `ubuntu-nas` `192.168.20.12`; HA T620 `192.168.20.13` | prod, branch `main`; not built yet (F3 metal) | no |
| router | OPNsense, VLAN gateways in `docs/network.md:23-28` | home network | no |

<!-- source: docs/network.md:10-12,23-47; ansible/environments/{dev,prod}/hosts.ini -->

## 7. Glossary

| Term | Meaning here | Source |
| --- | --- | --- |
| F0-F10 | Plan phases (F0 manual setup ... F9 audits and merge gate, F10 monitoring after prod) | `docs/plan/greenfield-plan.md` "Fazy / sprinty" |
| P0 / P1 / P2 | Application priority tiers | `docs/apps-sources.md:8,25` |
| greenfield / v2 | The rebuild on `homelab-v2`; pre-v2 code is legacy | `README.md:10` |
| F9 gate | Conditions for merging `homelab-v2` into `main` | `knowledge/rebuild-drill-2026-09-10.md:7,48-55` |
| IOT / APP / WireGuard | Prod VLANs and the VPN network | `docs/network.md:23-28` |

## 8. Open questions

- APP network CIDR is written three ways; not to be guessed - fix at F3 metal.
  <!-- source: knowledge/repo-audit-2026-09-10.md:158 -->
- DEV Proxmox token ID: `utils/dev-apply-local.sh:21` and `tests/infra/run.sh:103` default to
  `root@pam!terraform`, `utils/bootstrap-f1-secrets.sh:40` sets `homelab-dev@pam!terraform`;
  which one nested DEV uses is unknown. Prod is `homelab-prod@pam!terraform`.
  <!-- source: knowledge/repo-audit-2026-09-10.md:159, docs/f3-proxmox.md:25 -->
- Plan todo statuses in `docs/plan/greenfield-plan.md` lag the code; to be reconciled in the plan
  audit.

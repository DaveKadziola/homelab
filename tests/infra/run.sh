#!/usr/bin/env bash
# Infra suite (F7-C / C2) — is the running infrastructure still what the code says?
#
#   terraform/plan        `terraform plan` reports no changes (dev: local state,
#                         cloud block moved aside like utils/dev-apply-local.sh)
#   terraform/state       terraform state matches environments/<env>/terraform.tfvars
#   ansible/check         `ansible-playbook --check` changes nothing
#   vm/ram|cpu|disk|ip    the guest really has what tfvars asks for
#   network/*             IP, gateway, VLAN and prefix agree with docs/network.md
#
# Read-only: plan without -out, ansible in check mode, everything else is a
# fact query over SSH.

set -uo pipefail

# shellcheck source=../lib/common.sh
source "$HL_REPO_ROOT/tests/lib/common.sh"

hl_env_load

TF_RAM=""; TF_CPU_CORES=""; TF_CPU_TYPE=""; TF_STORAGE_SIZE=""
TF_CIDR=""; TF_GATEWAY=""; TF_DNS=""; TF_VLAN_TAG=""; TF_VM_ID=""; TF_VM_NAME=""
if tfvars_out="$(hl_config tfvars "$HL_ENV" apps 2>/dev/null)"; then
  eval "$tfvars_out"
else
  report FAIL "terraform/tfvars" "cannot read vm_config.apps from terraform/environments/$HL_ENV/terraform.tfvars"
fi

# --------------------------------------------------------------------------
# config vs docs (no host needed)
# --------------------------------------------------------------------------
while IFS=$'\t' read -r status ident message; do
  [[ -z "$status" ]] && continue
  report "$status" "$ident" "$message"
done < <(hl_config check-network "$HL_ENV")

# --------------------------------------------------------------------------
# terraform state vs tfvars — works without any Proxmox access
# --------------------------------------------------------------------------
STATE="$HL_REPO_ROOT/terraform/environments/$HL_ENV/terraform.tfstate"
if [[ ! -f "$STATE" ]]; then
  report SKIP "terraform/state" "no local state at terraform/environments/$HL_ENV/terraform.tfstate (env uses HCP Terraform)"
elif ! command -v jq >/dev/null 2>&1; then
  report SKIP "terraform/state" "jq is not installed"
else
  state_vm="$(jq -r --arg name "$TF_VM_NAME" '
    .resources[]? | select(.type == "proxmox_virtual_environment_vm")
    | .instances[]? | .attributes
    | select(.name == $name or .name == ($name + "-" + "dev"))
    | [ (.memory[0].dedicated // "?"), (.cpu[0].cores // "?"), (.cpu[0].type // "?"),
        (.disk[0].size // "?"),
        (.initialization[0].ip_config[0].ipv4[0].address // "?") ]
    | @tsv' "$STATE" 2>/dev/null | head -1)"
  if [[ -z "$state_vm" ]]; then
    report SKIP "terraform/state" "no proxmox_virtual_environment_vm for '$TF_VM_NAME' in the local state"
  else
    IFS=$'\t' read -r s_ram s_cores s_cputype s_disk s_ip <<<"$state_vm"
    mismatch=()
    [[ "$s_ram" != "$TF_RAM" ]] && mismatch+=("ram state=$s_ram tfvars=$TF_RAM")
    [[ "$s_cores" != "$TF_CPU_CORES" ]] && mismatch+=("cpu_cores state=$s_cores tfvars=$TF_CPU_CORES")
    [[ "$s_cputype" != "$TF_CPU_TYPE" ]] && mismatch+=("cpu_type state=$s_cputype tfvars=$TF_CPU_TYPE")
    [[ "$s_disk" != "$TF_STORAGE_SIZE" ]] && mismatch+=("disk state=${s_disk}G tfvars=${TF_STORAGE_SIZE}G")
    [[ "$s_ip" != "$TF_CIDR" ]] && mismatch+=("ip state=$s_ip tfvars=$TF_CIDR")
    if [[ ${#mismatch[@]} -eq 0 ]]; then
      report PASS "terraform/state" "state matches tfvars (ram=$TF_RAM cores=$TF_CPU_CORES cpu=$TF_CPU_TYPE disk=${TF_STORAGE_SIZE}G)"
    else
      report FAIL "terraform/state" "state was applied with different inputs: ${mismatch[*]}"
    fi
  fi
fi

# --------------------------------------------------------------------------
# terraform plan drift
# --------------------------------------------------------------------------
terraform_plan_dev() {
  local pve_ip="${DEV_PROXMOX_IP:-192.168.122.219}"
  local token_file="${HOME}/.homelab-pve-dev-token-secret"
  local pass_file="${HOME}/.homelab-pve-dev-root-pass"

  if ! command -v terraform >/dev/null 2>&1; then
    report SKIP "terraform/plan" "terraform is not installed"
    return
  fi
  if [[ -z "${TF_VAR_proxmox_api_token_secret:-}" && ! -f "$token_file" ]]; then
    report SKIP "terraform/plan" "no Proxmox API token (TF_VAR_proxmox_api_token_secret or $token_file)"
    return
  fi
  if ! curl -sk -o /dev/null -m 5 "https://${pve_ip}:8006/"; then
    report SKIP "terraform/plan" "nested Proxmox API https://${pve_ip}:8006 is not reachable (run utils/ensure-dev-proxmox.sh)"
    return
  fi

  export TF_VAR_environment=dev
  export TF_VAR_proxmox_node_name="${TF_VAR_proxmox_node_name:-dev}"
  export TF_VAR_proxmox_api_url="${TF_VAR_proxmox_api_url:-https://${pve_ip}:8006/api2/json}"
  export TF_VAR_proxmox_api_token_id="${TF_VAR_proxmox_api_token_id:-root@pam!terraform}"
  export TF_VAR_proxmox_ssh_username="${TF_VAR_proxmox_ssh_username:-root}"
  [[ -z "${TF_VAR_proxmox_api_token_secret:-}" ]] &&
    export TF_VAR_proxmox_api_token_secret="$(cat "$token_file")"
  [[ -z "${TF_VAR_proxmox_ssh_password:-}" && -f "$pass_file" ]] &&
    export TF_VAR_proxmox_ssh_password="$(cat "$pass_file")"
  [[ -z "${TF_VAR_ubuntu_docker_ssh_pub:-}" && -f "${HOME}/.ssh/homelab_dev_ed25519.pub" ]] &&
    export TF_VAR_ubuntu_docker_ssh_pub="$(cat "${HOME}/.ssh/homelab_dev_ed25519.pub")"
  if [[ -z "${TF_VAR_ubuntu_docker_password:-}" && -f "${HOME}/.homelab-ubuntu-apps-dev-pass" ]]; then
    # Deterministic salt: a fresh `openssl passwd -6` salt on every run would
    # look like drift in cloud-init even when nothing changed.
    local plain salt
    plain="$(cat "${HOME}/.homelab-ubuntu-apps-dev-pass")"
    salt="$(printf '%s' "$plain" | sha256sum | cut -c1-16)"
    export TF_VAR_ubuntu_docker_password="$(openssl passwd -6 -salt "$salt" "$plain")"
  fi

  terraform_plan_run
}

# Runs plan with the HCP Terraform cloud block moved aside, exactly like
# utils/dev-apply-local.sh and infra-plan-dev.yml do, and always puts it back.
restore_cloud_tf() {
  if [[ "${CLOUD_TF_MOVED:-0}" -eq 1 && -f "$HL_REPO_ROOT/terraform/cloud.tf.off" ]]; then
    mv "$HL_REPO_ROOT/terraform/cloud.tf.off" "$HL_REPO_ROOT/terraform/cloud.tf"
    CLOUD_TF_MOVED=0
  fi
}
trap restore_cloud_tf EXIT

terraform_plan_run() {
  local log="$HL_ARTIFACTS/terraform-plan-$HL_ENV.log"
  local init_log="$HL_ARTIFACTS/terraform-init-$HL_ENV.log"
  local rc=0 summary=""

  cd "$HL_REPO_ROOT/terraform" || return
  if [[ -f cloud.tf ]]; then
    mv cloud.tf cloud.tf.off && CLOUD_TF_MOVED=1
  fi

  if terraform init -reconfigure -input=false >"$init_log" 2>&1; then
    terraform plan -input=false -lock=false -no-color -detailed-exitcode \
      -state="environments/$HL_ENV/terraform.tfstate" \
      -var-file="environments/$HL_ENV/terraform.tfvars" >"$log" 2>&1
    rc=$?
    summary="$(grep -aoE 'Plan: [0-9]+ to add, [0-9]+ to change, [0-9]+ to destroy' "$log" | tail -1)"
  else
    rc=99
  fi
  restore_cloud_tf
  cd "$HL_REPO_ROOT" || return

  case "$rc" in
    0) report PASS "terraform/plan" "no changes — infrastructure matches the code" ;;
    2) report FAIL "terraform/plan" "drift: ${summary:-changes planned} (full plan: $log)" ;;
    99) report FAIL "terraform/plan" "terraform init failed — see $init_log" ;;
    *) report FAIL "terraform/plan" "terraform plan exited $rc — see $log" ;;
  esac
}

if [[ "$HL_ENV" == "dev" ]]; then
  terraform_plan_dev
  cd "$HL_REPO_ROOT" || exit 1
elif [[ -n "${TF_API_TOKEN:-}" ]] && curl -sk -o /dev/null -m 5 "https://192.168.20.20:8006/"; then
  report SKIP "terraform/plan" "prod plan runs in HCP Terraform (workspace homelab) — see infra-plan.yml"
else
  report "$(hl_unreachable_status)" "terraform/plan" \
    "prod plan needs HCP Terraform + the physical Proxmox host — not reachable from here"
fi

# --------------------------------------------------------------------------
# ansible --check
# --------------------------------------------------------------------------
ansible_check() {
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    report SKIP "ansible/check" "ansible-playbook is not installed"
    return
  fi
  if ! hl_host_up; then
    report "$(hl_unreachable_status)" "ansible/check" "host ${HL_HOST} unreachable"
    return
  fi

  # The playbook renders .env from deploy secrets; without them every run would
  # report the .env task as changed, which says nothing about drift.
  if [[ -z "${POSTGRES_PASSWORD:-}" && "$HL_ENV" == "dev" && -f "$HOME/.homelab-postgres-dev-pass" ]]; then
    POSTGRES_PASSWORD="$(cat "$HOME/.homelab-postgres-dev-pass")"
  fi
  if [[ -z "${IMMICH_DB_PASSWORD:-}" && "$HL_ENV" == "dev" && -f "$HOME/.homelab-immich-db-dev-pass" ]]; then
    IMMICH_DB_PASSWORD="$(cat "$HOME/.homelab-immich-db-dev-pass")"
  fi
  if [[ -z "${POSTGRES_PASSWORD:-}" ]]; then
    report SKIP "ansible/check" "POSTGRES_PASSWORD is not available here — .env content cannot be compared"
    return
  fi
  # Same value the deploy workflow passes, taken from config/services.yml.
  if [[ -z "${LINKWARDEN_URL:-}" ]]; then
    local lw_port
    lw_port="$(hl_config services "$HL_ENV" | awk -v FS="$HL_FS" '$1=="linkwarden" {print $6}')"
    [[ -n "$lw_port" ]] && LINKWARDEN_URL="http://${HL_HOST}:${lw_port}"
  fi

  local log="$HL_ARTIFACTS/ansible-check-$HL_ENV.log"
  POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
    IMMICH_DB_PASSWORD="${IMMICH_DB_PASSWORD:-}" \
    LINKWARDEN_URL="${LINKWARDEN_URL:-}" \
    ansible-playbook -i "environments/$HL_ENV/hosts.ini" playbooks/deploy-core.yml \
    --check --diff >"$log" 2>&1
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    report FAIL "ansible/check" "ansible-playbook --check exited $rc — see $log"
    return
  fi
  local changed
  changed="$(hl_config ansible-changed <"$log" | paste -sd';' - | sed 's/;/; /g')"
  if [[ -z "$changed" ]]; then
    report PASS "ansible/check" "check mode changes nothing on ${HL_HOST}"
  else
    report FAIL "ansible/check" "check mode would change: $changed (see $log)"
  fi
}

(cd "$HL_REPO_ROOT/ansible" && ansible_check)

# --------------------------------------------------------------------------
# the guest really has what tfvars asks for
# --------------------------------------------------------------------------
if ! hl_host_up; then
  status="$(hl_unreachable_status)"
  for check in ram cpu-cores cpu-type disk ip; do
    report "$status" "vm/$check" "host ${HL_HOST} unreachable — cannot read guest facts"
  done
  exit 0
fi

FACTS="$HL_TMP/guest-facts.txt"
hl_ssh 'nproc; awk "/MemTotal/{print \$2}" /proc/meminfo; lsblk -bdno NAME,SIZE -e7,11 | sort -k2 -n | tail -1; grep -m1 "^model name" /proc/cpuinfo | cut -d: -f2-; grep -m1 ^flags /proc/cpuinfo | grep -c sse4_2; ip -o -4 addr show scope global | awk "{print \$4; exit}"' >"$FACTS" 2>/dev/null

G_CORES="$(sed -n 1p "$FACTS")"
G_MEM_KB="$(sed -n 2p "$FACTS")"
G_DISK="$(sed -n 3p "$FACTS")"
G_MODEL="$(sed -n 4p "$FACTS" | sed 's/^ *//')"
G_SSE42="$(sed -n 5p "$FACTS")"
G_CIDR="$(sed -n 6p "$FACTS")"

# RAM — the guest always reports slightly less than the configured amount.
if [[ -z "$G_MEM_KB" || -z "$TF_RAM" ]]; then
  report SKIP "vm/ram" "guest MemTotal or tfvars ram unavailable"
else
  g_mib=$((G_MEM_KB / 1024))
  floor=$((TF_RAM * 90 / 100))
  if [[ "$g_mib" -ge "$floor" && "$g_mib" -le "$TF_RAM" ]]; then
    report PASS "vm/ram" "guest sees ${g_mib} MiB, tfvars ram=${TF_RAM} MiB"
  else
    report FAIL "vm/ram" "guest sees ${g_mib} MiB, tfvars ram=${TF_RAM} MiB (allowed ${floor}-${TF_RAM})"
  fi
fi

if [[ "$G_CORES" == "$TF_CPU_CORES" ]]; then
  report PASS "vm/cpu-cores" "nproc=$G_CORES matches tfvars cpu_cores"
else
  report FAIL "vm/cpu-cores" "nproc=$G_CORES but tfvars cpu_cores=$TF_CPU_CORES"
fi

if [[ "$TF_CPU_TYPE" == "host" ]]; then
  if [[ "$G_SSE42" == "1" && "$G_MODEL" != *QEMU* && "$G_MODEL" != *"Common KVM"* ]]; then
    report PASS "vm/cpu-type" "cpu_type=host in effect: '$G_MODEL' with sse4_2 (x86-64-v2, needed by Immich ML)"
  else
    report FAIL "vm/cpu-type" "tfvars cpu_type=host but the guest reports '$G_MODEL' (sse4_2=$G_SSE42)"
  fi
else
  report PASS "vm/cpu-type" "tfvars cpu_type=${TF_CPU_TYPE:-default}; guest reports '$G_MODEL'"
fi

g_disk_bytes="${G_DISK##* }"
if [[ -z "$g_disk_bytes" || -z "$TF_STORAGE_SIZE" ]]; then
  report SKIP "vm/disk" "guest disk size or tfvars storage_size unavailable"
else
  g_gib=$((g_disk_bytes / 1073741824))
  if [[ "$g_gib" -eq "$TF_STORAGE_SIZE" ]]; then
    report PASS "vm/disk" "${G_DISK%% *} is ${g_gib} GiB, tfvars storage_size=${TF_STORAGE_SIZE}"
  else
    report FAIL "vm/disk" "${G_DISK%% *} is ${g_gib} GiB but tfvars storage_size=${TF_STORAGE_SIZE}"
  fi
fi

if [[ "$G_CIDR" == "$TF_CIDR" ]]; then
  report PASS "vm/ip" "guest address $G_CIDR matches tfvars cloud_init_cidr"
else
  report FAIL "vm/ip" "guest address $G_CIDR but tfvars cloud_init_cidr=$TF_CIDR"
fi

exit 0

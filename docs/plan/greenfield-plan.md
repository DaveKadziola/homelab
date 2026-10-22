---
name: Homelab greenfield dummy
overview: Greenfield homelab v2 — iter.
todos:
  - id: secrets-gh
    content: "F0-10 ✅ docs/secrets-inventory.md + manual-setup + apps-sources (4d0ab71)"
    status: completed
  - id: secrets-vault
    content: "A10 ✅ Bitwarden PM + 2FA + folder homelab + TF_API_TOKEN/prod (user 2026-06-11)"
    status: completed
  - id: hardware
    content: "A5 as-built ✅ 2026-06-30; MAC-i PVE i T620 na routerze (docs/network.md:43,45), prod zbudowany 2026-10-20 (VM 101/102, CT 110)"
    status: completed
  - id: apps-decisions
    content: "Zamknięte iter. #2: P0/P1/P2, Trillium, Actual, Navidrome, Syncthing P1, Jellyfin P1, Zotify defer"
    status: completed
  - id: apps-inventory
    content: Tabela aplikacji — fazy P0/P1/P2 ✅ iter.
    status: completed
  - id: apps-repo-verify
    content: "Gate A16: zweryfikować GitHub/źródło każdej appki; docs/apps-sources.md; checkboxy w planie"
    status: completed
  - id: backup-dr
    content: "A15 ✅ sizing; A9 partial (konto pCloud 500GB wolne, brak rclone OAuth — F5); retention ✅"
    status: completed
  - id: security
    content: "B3/B4/B14 ✅; Grocery public: grocery.dkhomelabserver.xyz (A6 ✅ 2026-06-11)"
    status: completed
  - id: phases
    content: P0/P1/P2 ✅ iter.
    status: completed
  - id: gha-cleanup-secrets
    content: "F0/A0: wyczyszczone legacy GH secrets/variables (2026-06-11)"
    status: completed
  - id: gha-pipelines
    content: "F1: GHA dual runner; homelab-v2→dev, main→prod; workflowy v2 (ci-validate, deploy-dev, …) — zaimplementowane; CI nie działa od 2026-07-01 (brak runnera) → R1 — ✅ 2026-10-18: CI Validate, Infra Plan/Apply Dev, Apps Deploy Dev i Tests Dev działają na runnerze homelab-dev"
    status: completed
  - id: gha-runner-bootstrap
    content: "F1 ✅ dev runner laptop (systemd); prod runner w LXC CT 110 ci-runner na hoście PVE (utils/pve-ci-runner-lxc.sh, #60/#63), runner laptopowy wyrejestrowany"
    status: completed
  - id: branch-v2
    content: "F0-09/10 ✅ homelab-v2 + docs commit 4d0ab71"
    status: completed
  - id: manual-setup-f0
    content: "Sprint F0 ✅ F0-01…F0-12 complete (gate 2026-06-11); docs English cdc77f7"
    status: completed
  - id: readme-docs
    content: README.md — pełna dokumentacja projektu (architektura, setup, deploy, DR, sekrety) — ✅ README + knowledge/ (audyt 2026-10-18)
    status: completed
  - id: preflight
    content: "Gate F0→F1 ✅ 2026-06-11; A9 rclone OAuth → F5; A5 MAC → F3"
    status: completed
  - id: implement
    content: "F1 ✅ CI; F2 ✅ router skryptami f2 (#26-#33, #55); F3 ✅ prod zbudowany z main (#75)"
    status: completed
  - id: identities
    content: "Iter. #3: config/identities.yml + generator credentiali (admin/prod/dev/notification) — F7 — ✅ e28840f, 5f37cd4; config suite PASS 2026-10-18"
    status: completed
  - id: config-as-code
    content: "Iter. #3 ✅ macierz + bootstrap/ (9f8afe2); prod: Apps Deploy Prod 39462592254 - tabela bootstrap Failed: 0"
    status: completed
  - id: tests-auto
    content: "Iter. #3 ✅ tests/ (smoke, infra, net, config, storage, ha, restore); prod 151/0/11 (39462592254), dev 147/0/16 (39460389233)"
    status: completed
  - id: knowledge-base
    content: "Iter. #3: docs/kb/ + lessons-learned (append-only, wpisy z F3/F4 dev) — F8 — ✅ 151d4e4; od 2026-10-18 w knowledge/"
    status: completed
  - id: rebuild-runbook
    content: "Iter. #3 ✅ knowledge/rebuild.md + drill na nested DEV (knowledge/rebuild-drill-2026-10-19b.md: pass bez zmian w kodzie)"
    status: completed
  - id: audit-final
    content: "F9: audyt prod 2026-10-20 (knowledge/security-audit-2026-10-20.md): S7 z LAN/IOT/APP ✅; zostało: skan z WG i WAN, poprawki S16-S27 (osobno, za zgodą)"
    status: in_progress
  - id: restore-ci
    content: "Iter. #4 R1: ponowna rejestracja runnera homelab-dev jako usługa; CI Validate + Infra Plan Dev zielone, Tests Dev się uruchamia — ✅ 2026-10-18: runner jako usługa systemd; CI Validate i Infra Plan Dev zielone; Tests Dev uruchamia się (#9–#13)"
    status: completed
  - id: restore-dev
    content: "Iter. #4 R2: nested Proxmox z IP (utils/ensure-dev-proxmox.sh) + ubuntu-apps-dev; run-tests --env dev --suite all bez FAIL — ✅ 2026-10-18: przyczyna zawieszeń = pełna pula LVM-thin; stan w HCP homelab-dev; run-tests 161 PASS / 0 FAIL"
    status: completed
  - id: f9-gate-dev
    content: "Iter. #4 R3 ✅ drill 10-19b z prawdziwym wymazaniem DEV przeszedł bez zmian w kodzie; restore suite ✅"
    status: completed
  - id: monitoring-alerts
    content: "Zrobione 2026-10-22: SMTP działa, operator dostaje maile. Diun ma DIUN_NOTIF_MAIL_* w diun.env na prod. W logu 48 h nie było nowego tagu do wysłania, były timeouty rejestru."
    status: completed
  - id: ai-log-analysis
    content: "F10-B (Paczka 2, operator 2026-10-20): streszczenia AI przez OpenRouter z oczyszczonych wyników audytu i logów (allowlist, agregacja); nic surowego do publicznego repo"
    status: pending
  - id: project-cleanup
    content: "Zrobione 2026-10-22: worktree homelab-grocery-prod zdjęte. Z origin zeszły feat/grocery-v2-prod (ta sama poprawka jest na homelab-v2 jako 6c13608) i fix/grocery-no-debug (zdanie o rewrite grocery jest w docs/network.md). Lokalne gałęzie po zmergowanych PR skasowane. ansible/docker-containers.yml, utils/create-dev-vm.sh i ansible/user-setup.yml nie ma w drzewie od 07bb30e. origin/dev zostaje: 26 commitów nie wchodzi w tag legacy-pre-v2. docs/opnsense-ui-walkthrough.md zostaje, bo baseline i f2-verify na niego wskazują."
    status: completed
  - id: docs-readme
    content: "Zrobione 2026-10-22: README.md już mówi co to jest, jak jest zbudowane i od czego zacząć. Osobnego przepisywania nie było."
    status: completed
  - id: docs-diagrams
    content: "Później (operator 2026-10-20): schematy draw.io — flow zmian (homelab-v2 → DEV, main → prod, approvals), sieć (VLAN-y, firewall, porty), backupy"
    status: pending
  - id: security-public-repo
    content: "2026-10-20: fork PR all_external_contributors, rulesety bez bypass, akcje przypięte do SHA (sha_pinning_required), model zagrożeń CI w knowledge/security.md. Decyzja 2026-10-22: mapa domu wychodzi z publicznego repo (public-map-split), potem jedno przepisanie historii (git-history-state)."
    status: in_progress
  - id: security-audit-hosts
    content: "Audyt prod 2026-10-20 zrobiony (knowledge/security-audit-2026-10-20.md, S16-S27); poprawki osobno, każda za zgodą"
    status: in_progress
  - id: app-network-access
    content: "Odczyt 2026-10-22, bez zmiany reguł. APP (vlan07) ma NFS i SSH na NAS oraz pass do wszystkiego poza PrivateNetworks, czyli cały VLAN wychodzi do internetu, nie pojedyncza aplikacja. Osobny audyt WAN (tylko WireGuard i Grocery) jest opnsense-wan-audit i czeka na końcu."
    status: pending
  - id: ci-autonomy
    content: "Zrobione 2026-10-22: reviewer zszedł ze środowiska prod. Infra Apply pyta raz (prod-approve), ryzykowny plan albo gate=true staje na prod-gate. Udany apply puszcza Apps Deploy bez drugiego kliknięcia (run 39806560198, job approve skipped). Ręczny deploy aplikacji nadal pyta raz."
    status: completed
  - id: homarr-links
    content: "Zrobione 2026-10-22: kafelki po nazwach, seed z deployu. Operator wszedł na prod Homarr (widget Beszela), więc konto admin w UI jest."
    status: completed
  - id: ha-as-code
    content: "Zrobione 2026-10-22: HA_TOKEN jest w środowisku prod, deploy odpala utils/ha.py, testy prod ha 5 PASS / 0 FAIL."
    status: completed
  - id: app-names-proxy
    content: "Zrobione 2026-10-22: CLOUDFLARE_API_TOKEN jest w środowisku prod, rewrite AdGuard są od 2026-10-21, nazwy HTTPS odpowiadają."
    status: completed
  - id: backups-nas-pve
    content: "Zrobione 2026-10-22: klucz OPNsense jest na routerze (wymuszona komenda), w GitHub env prod, w Bitwarden i na NAS. Pierwszy zrzut: /srv/purple/nas-backups/opnsense/config-20261022T131513Z.xml (mode 600). HA_TOKEN prod był już wcześniej."
    status: completed
  - id: weekly-security-audit
    content: "Paczka 2 (operator 2026-10-20): tygodniowy audyt na timerze - nmap S7 z IOT, Trivy obrazów, wersje, reguły OPNsense -> raport mailem i na NAS, nigdy w artefaktach publicznego repo"
    status: pending
  - id: nic-error-metrics
    content: "Zrobione 2026-10-22: cron na PVE codziennie 06:15. Wzrost idzie mailem przez SSH na host aplikacji (wymuszona komenda, sekret SMTP zostaje na 192.168.50.30). Istniejące liczniki nie alarmują, tylko wzrost. Cofnięcie: rm /etc/cron.d/homelab-nic-errors /usr/local/sbin/nic-errors.sh /var/lib/homelab/nic-errors.prev /root/.ssh/homelab-nic-mail /root/.ssh/homelab-nic-mail.pub i linia homelab-nic-mail w authorized_keys ubuntu-prod."
    status: completed
  - id: ubuntu-2604
    content: "Po wydaniu PR #78 (operator 2026-10-21): VM-ki apps i NAS z Ubuntu 24.04 na 26.04 - najpierw DEV z ćwiczeniem przebudowy i odtworzenia, potem prod jako osobne wydanie; zmiana obrazu (terraform/environments/*/terraform.tfvars image_url) to najpewniej wymiana VM (bramka ryzyka). Nie naprawia rclone: 26.04 ma w apt nadal 1.60.1, narzędzia przypinać do wersji upstream"
    status: pending
  - id: nfs-root-squash
    content: "Zostaje no_root_squash. Odczyt 2026-10-22: /export dla 192.168.50.0/26 i vzdump dla 192.168.20.20. Jellyfin na prod działa jako root i trzyma /media. root_squash zabrałby mu zapis. Eksportu nie zmieniano."
    status: completed
  - id: authelia-ip-bypass
    content: "Zamknięte 2026-10-22 (operator): aplikacje z własnym logowaniem mają auth_bypass all. Portów nie zwijamy na 127.0.0.1. Kuma na T620 sprawdza je TCP; zamknięcie IP dałoby maile, że żywa aplikacja jest down."
    status: completed
  - id: homarr-ha-domain
    content: "Zrobione 2026-10-22: prod kafelek Home Assistant to http://hass.dkhomelabserver.xyz/ (board na hoście, ping wyłączony)."
    status: completed
  - id: pr78-merge-checklist
    content: "Zamknięte 2026-10-22: checklista #78 cała odhaczona. Bramka po tym, jak Apps Deploy 39806560198 ruszył z jobem approve skipped. Wolumeny Zotify i BESZEL_KEY zdjęte."
    status: completed
  - id: deploy-prod-timeout
    content: "Zrobione 2026-10-22: job deploy-prod ma timeout-minutes 120. Apps Deploy Prod 39746487452 skończył deploy-prod w 21m45s, poniżej limitu."
    status: completed
  - id: ansible-python-interpreter
    content: "Zrobione 2026-10-22: ansible_python_interpreter=/usr/bin/python3 w inventory prod i dev. Ten sam Apps Deploy Prod przeszedł Ansible bez warningu discovery."
    status: completed
  - id: homarr-network-tiles
    content: "Zrobione 2026-10-22: na hoście prod są Proxmox :8006, AdGuard https://adguard.dkhomelabserver.xyz:8443/, OPNsense https://router.dkhomelabserver.xyz/, switch i access point. Deploy 39755554518. Switch na porcie 80 z laptopa nie odpowiedział."
    status: completed
  - id: diun-updates
    content: "Zrobione 2026-10-22: Diun mailuje nowe tagi kontenerów. Timer homelab-host-updates (niedziela 06:15) mailuje paczki apt i nowszy serial obrazu Ubuntu, gdy /etc/cloud/build.info różni się od cloud-images.ubuntu.com. Na prod apps i NAS serial to 20261017, taki sam jak opublikowany. Nowy serial to przebudowa VM, nie apt."
    status: completed
  - id: diun-homarr-access
    content: "Zrobione 2026-10-22: Diun 4.33.0 nie ma GUI (knowledge/apps/diun.md). Martwego kafelka nie ma. Wejście to log w Dozzle albo skrzynka. Przez 48 h Diun nie wysłał maila."
    status: completed
  - id: homarr-dashboard-widgets
    content: "Niewdrożone. homarr_board.py zapisuje tylko kafelek aplikacji. W obrazie Homarr 2.6.0 nie znaleziono schematu options dla pogody ani zegara. Nie zgadywano."
    status: pending
  - id: public-map-split
    content: "Operator 2026-10-22: publiczne repo zostaje portfolio (architektura, sposób deployu). Mapa domu (adresy, domena, maile) idzie do docs w .gitignore i/lub modułu z prywatnego repo. Aktualne pliki trzeba przepisać na przykładowe adresy. Historii jeszcze nie ruszać: jedno przepisanie jest w git-history-state, po tej zamianie, nie wcześniej."
    status: pending
  - id: git-history-state
    content: "Po public-map-split (operator 2026-10-22): wyciąć z całej historii terraform/terraform.tfstate i terraform/terraform.tfstate.backup (dodane w 18dd8c6, zdjęte w ce25d3a; sześć adresów 192.168, bez haseł) oraz starą mapę domu. Jedno przepisanie historii, force-push main i homelab-v2. git-filter-repo nie jest zainstalowany. Potem każdy klon jest nieaktualny; GitHub może trzymać stare obiekty, dopóki ich nie wyczyści. Nie robić tego przed zamianą plików, bo inaczej mapa wróci w nowych commitach."
    status: pending
  - id: opnsense-wan-audit
    content: "Na końcu (operator 2026-10-22): audyt reguł OPNsense. Na WAN ma wychodzić tylko WireGuard i Grocery. Odczyt reguł, porównanie z docs/network.md (WAN 443/tcp i 51820/udp). Bez zmiany konfiguracji, dopóki audyt nie pokaże różnicy i operator jej nie zatwierdzi."
    status: pending
  - id: subnet-refactor
    content: "Na samym końcu, po opnsense-wan-audit (operator 2026-10-22): refaktoring podsieci. Operator uważa, że układ VLAN da się zrobić lepiej. Projektu jeszcze nie ma. Nic nie zmieniać, dopóki nie ma zatwierdzonego układu."
    status: pending
isProject: false
---

# Homelab — plan

Backlog jest w frontmatterze tego pliku. Reszta notatek z czerwca i lipca
jest w [`greenfield-notes.md`](greenfield-notes.md) i nie jest instrukcją.

# Networking Toolbox

| | |
|--|--|
| URL | `https://networking-toolbox.<domain>` (through Caddy + Authelia); DEV direct `http://192.168.122.50:8087` |
| Image | `lissy93/networking-toolbox:1.6.0` (MIT; container port 3000) |
| Login | none (Authelia in front) |
| Config-as-code | yes |

DNS, subnet, port and TLS tools, and domain / IP / ASN lookups over RDAP (diagnostics -> RDAP). It
replaced DumbWhois on 2026-10-20: DumbWhois asks port-43 WHOIS only, and from prod `.pl` answered
while `.com` and `.xyz` timed out after 15 s with port 43 open (owner's check, 2026-10-20). The
lookups leave the apps host as HTTPS to the registries (APP egress to the internet).

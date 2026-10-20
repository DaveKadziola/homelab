# Caddy with the Cloudflare DNS module: prod gets one wildcard certificate through the DNS challenge
# (knowledge/decisions/0007-app-names-caddy-authelia.md). DEV uses the same image with its internal CA.
FROM caddy:2.11.7-builder AS builder
RUN xcaddy build v2.11.7 --with github.com/caddy-dns/cloudflare@v0.2.4

FROM caddy:2.11.7
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

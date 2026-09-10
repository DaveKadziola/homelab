# Zotify — Spotify downloader (P2)

There is no headless login. Spotify issues an OAuth token interactively and
stores it in the `zotify_config` Docker volume. That is the only remaining
manual step in the P0–P2 stack.

## First login (dev)

```bash
ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@192.168.122.50
docker exec -it homelab-core-zotify-1 zotify
```

The OAuth callback listens on host `:4381` for the duration of that login.
Credentials never go in git; they stay in the volume.

## After login

```bash
docker exec -it homelab-core-zotify-1 zotify '<spotify-url>'
```

Optional env placeholders `ZOTIFY_USERNAME` / `ZOTIFY_TOKEN` in `.env` are not
used as a substitute for this flow.

# Zotify — Spotify downloader (P2)

There is no headless login. Spotify issues an OAuth token interactively and
stores it in the `zotify_config` Docker volume. That is the only remaining
manual step in the P0–P2 stack.

| | |
|--|--|
| UI | none |
| Callback | host `:4381` during login only |
| Login | interactive Spotify OAuth |
| Secret | none in git / GH |

## First login (dev)

```bash
ssh -i ~/.ssh/homelab_dev_ed25519 ubuntu-dev@192.168.122.50
docker exec -it homelab-core-zotify-1 zotify
```

Credentials stay in the volume. Optional `.env` placeholders `ZOTIFY_USERNAME` / `ZOTIFY_TOKEN` are not a substitute.

## After login

```bash
docker exec -it homelab-core-zotify-1 zotify '<spotify-url>'
```

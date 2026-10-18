# Linkwarden

| | |
|--|--|
| URL (dev) | http://192.168.122.50:3001 |
| Login | username `admin` (email is the env mailbox; older rows had empty email) |
| Secret | `LINKWARDEN_ADMIN_PASSWORD` |
| Also | `LINKWARDEN_SECRET` (`NEXTAUTH_SECRET`) |
| DB | `linkwarden` on shared Postgres |
| Bootstrap | `utils/bootstrap/linkwarden.sh` |

`NEXTAUTH_URL` must match the URL you open (`LINKWARDEN_URL`). Bootstrap updates the first `User` row (hash + email + username) and verifies NextAuth cookies.

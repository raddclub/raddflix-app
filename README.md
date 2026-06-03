# RaddFlix — Pakistan ka Entertainment, Data-Free

**RaddFlix** is a Pakistani streaming platform built for Jazz SIM users. Content is streamed via JazzDrive CDN (`cloud.jazzdrive.com.pk`) which Jazz zero-rates at the network level — no data bundle needed.

## What's in this repo

| Folder | What it is |
|--------|-----------|
| `radd-hub/` | Flask admin panel — content management, user management, subscriptions, analytics |
| `raddflix_flutter/` | Flutter mobile app — the user-facing Android streaming app |
| `agent-hub/` | Core architecture & feature specs (streaming, player, security, zero-rating) |
| `scripts/` | Post-merge and workspace utility scripts |

## Live Infrastructure

| Component | Details |
|-----------|---------|
| Oracle Ubuntu Server | `ubuntu@92.4.95.252` |
| Radd Hub (admin + API) | nginx port 80 → Flask port 5000 |
| Supervisor service | `raddflix_radd` |
| GitHub repo | `raddclub/raddflix-app` (main branch) |
| CI / APK build | GitHub Actions → `.github/workflows/build-apk.yml` |

## Key scripts

```bash
bash push_to_github.sh          # commit & push to GitHub
bash push_to_oracle.sh          # git pull + restart on Oracle
```

## Agent quick-start

1. Add secrets: `GITHUB_TOKEN` and `ORACLE_SSH_KEY`
2. Restore SSH key and verify Oracle:
   ```bash
   node -e "const raw=process.env.ORACLE_SSH_KEY;const m=raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);if(m)require('fs').writeFileSync('/tmp/oracle_key',m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',{mode:0o600})"
   ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "curl -s http://localhost:5000/api/app/version"
   ```
3. Read architecture: `agent-hub/STREAMING_ARCHITECTURE.md`
4. Read product context: `agent-hub/PRODUCT_CONTEXT.md`

## Architecture (one-liner)

```
Phone → Oracle (auth/catalog/subs) + JazzDrive CDN (video, zero-rated)
```

Oracle never proxies video. JazzDrive API calls go phone→CDN directly (zero-rated).

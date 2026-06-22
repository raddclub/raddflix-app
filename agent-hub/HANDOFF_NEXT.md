# Handoff — Next Agent

> Date: 2026-06-22 | Build: #1219 (in progress) | Commit: `0748417f`

---

## Current State

**player_screen.dart** — 7033 lines, 21 classes  
GitHub: `raddclub/raddflix-app` → `raddflix_flutter/lib/screens/player_screen.dart`

### What was just done (Phase 17)
- Center of video is now **completely empty** (cinematic experience)
- All playback controls (skip/prev/play/next/skip) moved to **compact row below seek bar**
- Top bar stripped of 5 redundant buttons (all in sidebar)  
- All right-side panels are now **55% width** (was 45%)
- Sidebar **auto-hides** when any panel is open, respects manual close state
- Both brightness + volume indicators on **LEFT side** (sidebar is on right)
- Subtitle `sub-opacity` property fix (was calling fake `sub-ass-fade-in-time`)
- Subtitle bottom margin range extended to 200px

---

## Environment Quick-Reference
```bash
# Fetch latest player_screen.dart
mkdir -p /tmp/raddflix && node -e "
const https=require('https'),fs=require('fs'),T=process.env.GITHUB_TOKEN;
function api(p){return new Promise((r,j)=>{const o={hostname:'api.github.com',path:p,method:'GET',headers:{'Authorization':'Bearer '+T,'Accept':'application/vnd.github.v3+json','User-Agent':'RaddFlix-Agent'}};const q=https.request(o,x=>{let b='';x.on('data',d=>b+=d);x.on('end',()=>{try{r(JSON.parse(b));}catch{r(b);}});});q.on('error',j);q.end();});}
api('/repos/raddclub/raddflix-app/contents/raddflix_flutter/lib/screens/player_screen.dart').then(r=>{
  fs.writeFileSync('/tmp/raddflix/player_screen.dart',Buffer.from(r.content,'base64').toString('utf8'));
  console.log('✅ sha:',r.sha.slice(0,8));
}).catch(e=>console.error('❌',e.message));
"

# Push via /tmp/push.js (already written by previous agent — re-create if /tmp wiped)
node /tmp/push.js

# Check build status
curl -s -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=1 \
  | python3 -c "import sys,json; r=json.load(sys.stdin)['workflow_runs'][0]; print(r['status'],r['conclusion'],r['head_sha'][:8])"
```

---

## Critical Rules (MUST follow)
| Rule | |
|------|-|
| NO `vf=` property | Crashes HW decoder |
| NO `hwdec` change mid-play | Only when paused + duration==0 |
| NO local `_np` variable | Always use the field `_np` |
| Use `db.setting(k)` | NOT `db.get_setting(k)` |
| NO `androidAttachSurfaceAfterVideoParameters:true` | Black screen |
| `_panelOpen` must reset via `.then()` on showGeneralDialog | Never forget this |

---

## Priority Bugs for Next Agent
1. **Subtitle background color** — verify `#ffRRGGBB` format works on device; MPV might need `&Halpha_BB_GG_RR`
2. **One-handed mode center area** — now empty like normal mode; confirm user is OK with this
3. **Transport row in one-handed mode** — confirm the bottom area still renders correctly when `_oneHandedMode=true`

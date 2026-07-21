# RaddFlix — Brand, Business Logic & Product Presentation
> **Any AI agent reading this: this is the master document for what RaddFlix is as a
> product, how it presents itself to users, what it keeps internal, and how it should
> be marketed and branded. Read PRODUCT_CONTEXT.md and STREAMING_ARCHITECTURE.md
> alongside this for the technical layer. This doc covers the product/business layer.**
>
> Last updated: 2026-07-21

---

## 1. The Core Reality (Internal — Never Expose to Users)

### How Free Streaming Actually Works
Jazz Telecom zero-rates `cloud.jazzdrive.com.pk` at the network level.
RaddFlix hosts all video files on JazzDrive (Jazz's personal cloud storage service).
When a Jazz SIM user streams RaddFlix content, all traffic routes through
`cloud.jazzdrive.com.pk` — a domain Jazz does not charge data for.

**Result:** Jazz SIM users can open RaddFlix and watch a full movie with Rs. 0 balance,
no active data bundle, no active social package — nothing needed.

### What Users Pay For
Users do not pay for internet. They pay for **access to the RaddFlix content library**
(movies, dramas, shows). The zero-data streaming on Jazz SIM is a feature that comes
with the app's infrastructure choice — not a separate product or service being sold.

### CDN Load Distribution Strategy
- Content is hosted across **multiple JazzDrive accounts** (not one).
- Different movies and seasons are split across different accounts.
- Each user watches different content at different times.
- This keeps per-account traffic naturally low and undetectable as commercial use.
- If any account gets suspended or blocked: swap to a backup CDN source.
  The `raddflix_config.json` API base URL and the SQLite `share_url` values are
  the only things that need updating — no app rebuild required in most cases.

### Jazz Relationship
- RaddFlix has **no official partnership, affiliation, or agreement with Jazz**.
- We never claim one. We never deny one. We say nothing either way.
- If a user assumes affiliation, that is their inference. We do not correct it.
- We do not use Jazz logos, Jazz branding, Jazz color schemes, or Jazz slogans.
- We do not use the word "Jazz" in our app name, tagline, or UI copy.
- We are an independent Pakistani streaming app whose technical infrastructure
  happens to be zero-rated on the Jazz network.

### Scale (as of 2026-07-21)
- Target user base: **10–200 users in year one**, potentially 200+ after that.
- This is a controlled, small-scale rollout — not a public mass-market launch.
- Small user counts mean JazzDrive load stays negligible and undetectable.
- Growth is deliberate and slow. We do not advertise at scale until the product
  is fully battle-tested.

---

## 2. What We Tell Users (User-Facing Truth)

Everything below is **100% true, honest, and safe to say publicly.**

### The Core Message
> **"Stream Pakistani movies and dramas free on Jazz SIM.
> No data bundle needed. Just open and watch."**

This is the entire value proposition in two lines. Every piece of marketing,
onboarding, and in-app copy should orbit this.

### What "Free" Means to Users
- On Jazz SIM: streaming data is **free** (not counted against any balance or bundle).
- This is not "free with a bundle" — they don't need a bundle at all.
- It is not a trial. It does not expire after X days.
- The content subscription gives them access to the library; the zero-data is a
  permanent feature of streaming on Jazz SIM.

### What They Pay For
- A **RaddFlix content subscription** — access to the full movie and drama catalogue.
- Subscriptions are priced based on monthly streaming data quota:
  - **Lite** — 30 GB/month of streaming
  - **Standard** — 50 GB/month of streaming
  - **Radd** (Premium) — 100 GB/month of streaming
- These are RaddFlix plan tiers. They are not Jazz bundles. They are not activating
  anything on the Jazz network. They are purely RaddFlix content access tiers.

### The Comparison That Sells the Product
This is the marketing table. Use it on the onboarding screen, landing page, and
promotional materials:

| | Jazz Internet Bundle | RaddFlix Subscription |
|---|---|---|
| **30 GB/month** | ~Rs. 600 (data only, no content) | Less than Rs. 600 (data + full content library) |
| **50 GB/month** | ~Rs. 900 (data only) | Less than Rs. 900 (data + content) |
| **What you get** | Just internet data | Internet data equivalent + movies + dramas + shows |

The user pays less than a Jazz data-only bundle and gets the same data allowance
**plus** a full streaming library. This is the only price comparison we make.
We do not say "we are a Jazz bundle." We say "compare what you pay vs what you get."

### The SIMOSA Daily Bonus (Planned Feature)
SIMOSA (Jazz's self-care app, previously Jazz World) gives free daily MBs to users
who open it every day:
- Day 1: 25 MB, Day 2: 50 MB, Day 3: 75 MB, Day 4: 100 MB, Day 5: 125 MB,
  Day 6: 150 MB, Day 7: 200 MB → ~725 MB/week = ~2.9 GB/month free

RaddFlix will show a daily in-app nudge: "Collect today's free MBs from SIMOSA →"
with a deep link. We show a 7-day streak tracker in the app.
**We never imply RaddFlix gave the user those MBs. SIMOSA gave them. We just remind.**

---

## 3. What We Never Say or Show to Users

| What | Why We Hide It |
|---|---|
| "JazzDrive" | Never appear in any user-facing surface — UI, marketing, support, screenshots |
| `cloud.jazzdrive.com.pk` | Never show the CDN domain anywhere |
| "We host content on JazzDrive" | Exposes the mechanism; irrelevant to users; Jazz ToS risk |
| Multiple JazzDrive accounts | Internal infrastructure detail |
| "This is not an official Jazz product" | We don't bring it up; let users form their own view |
| "This might stop working if Jazz blocks it" | Never. Users pay for what works now. |
| Share URLs, file IDs, SQLite, API calls | Deep technical internals — never exposed |
| Server IP (92.4.95.252) | Internal infrastructure |
| Content licensing status | Never discussed in-app or in marketing |
| APK-only distribution (not Play Store) | Explain as "sideloading" or "direct install" only if asked. Never proactively flag. |

---

## 4. Brand Identity

### Name
**RaddFlix** — this is the permanent, final name.
Previous names (JazzMAX, Zeno) are dead. Never reference them publicly.

"Radd" (ردّ) is an Urdu word meaning "reply," "response," or "reaction" —
culturally rooted, short, punchy, modern. "Flix" signals streaming universally.
Together: a Pakistani streaming identity with an international form factor.

### Tagline Options (choose one per campaign; these are all honest and accurate)
- **"Pakistan ka apna streaming. Jazz pe bilkul free."** (primary — Urdu)
- **"Stream free. Watch more. Pay less."** (English version)
- **"No bundle. No balance. Just watch."** (punchy, Jazz SIM angle)
- **"Tamasha se sasta, Netflix se behtar."** (competitive — use carefully; Tamasha
  comparison is fair since Tamasha is Jazz's own paid streaming app)

### Visual Identity Rules
- **Do not** use Jazz red (#E50914-adjacent reds) as the primary color in marketing.
  We use RaddFlix cardinal red (#C41E3A) which is our own brand color.
- **Do not** use Jazz logo, Jazz name, Jazz color system in any marketing asset.
- **Do** use distinctly Pakistani visual language: cultural references, Urdu typography,
  Pakistani drama poster aesthetics — this differentiates us from global apps.
- The signal-green (`#3DDC97`) is our data-free identity color. Use it as an
  accent in marketing to represent the "free streaming" proposition.
  Example: the ⚡ icon, "data-free" badges, and the data-saved counter on Home.

### Tone of Voice
- Confident, local, a little cheeky.
- Urdu-first for in-app microcopy; English for technical/support text.
- Never corporate or formal.
- Reference Pakistani dramas, cricket, and local culture freely.
- Never reference Jazz, telecom, or network infrastructure in copy.

### App Icon / Logo Direction
- Icon: bold, dark background, the "R" or "RF" wordmark in crimson/white.
- Should read clearly at 48px (launcher icon) and 16px (notification icon).
- No satellite dish, no signal bars, no wifi icons — those suggest telecom, not streaming.
- Cinematic feel: film frame edge, screen glow, or clapperboard reference is fine.

---

## 5. User-Facing Plan Names & Pricing Logic

### Plan Names (rename from Basic/Standard/Premium)
| Internal Name | User-Facing Name | Data Quota | Positioning |
|---|---|---|---|
| Free | Free | Limited catalogue, capped data | Guest/expired users |
| Basic | **Lite** | 30 GB/month | "Same data as Jazz 30GB bundle, plus all our content" |
| Standard | **Standard** | 50 GB/month | Most popular; hero plan |
| Premium | **Radd** | 100 GB/month | Power users; cinephiles |

### Pricing Positioning Rule
RaddFlix plans must always be **priced below the Jazz equivalent data-only bundle**:
- Lite: must be cheaper than Jazz's ~Rs. 600 / 30GB plan
- Standard: must be cheaper than Jazz's ~Rs. 900 / 50GB plan
- Radd: must be cheaper than Jazz's ~Rs. 1,500 / 100GB plan
This comparison is the core marketing proof point. The moment our prices exceed
the Jazz data-only equivalent, the value proposition collapses.

### What to Show on the Plan Selection Screen
For each plan, show:
1. Plan name + price
2. Data quota (e.g. "30 GB streaming / month")
3. A one-line Jazz comparison: "Jazz charges ~Rs. 600 for 30GB of data alone"
4. "With RaddFlix Lite: same data + full movie & drama library for less."
5. Never use the word "bundle" (implies Jazz activation). Use "plan" or "subscription."

---

## 6. Onboarding Flow (What Users See First)

### Rule: Content Before Registration (Volume I Reciprocity)
A user must be able to browse real content before hitting any login/signup wall.
This is non-negotiable. Apps that gate immediately create distrust and bounce.

### Recommended Onboarding Sequence
1. **Splash** → app logo + tagline (1.5s, then auto-advance)
2. **Jazz SIM Detect Screen** (if Jazz SIM detected):
   > "⚡ Jazz SIM detected!
   > Streaming is completely free for you — no data bundle needed.
   > Browse our full library below."
   → CTA: "Explore Free" (no login required)
3. **Non-Jazz SIM Screen** (if no Jazz SIM):
   > "Stream Pakistani movies and dramas.
   > Jazz SIM users stream free. Other networks need a data bundle."
   → CTA: "Explore" + "I have Jazz SIM" (for cases where detection fails)
4. **Browse Screen** — show full catalogue (free + paid tiles visible; paid tiles
   show a lock icon but are visible, not hidden)
5. **Tap a paid title** → soft login prompt:
   > "Sign in to unlock. Already a member? Log in."
6. **Login / Registration** → standard flow
7. **Plan Selection** → show comparison table + plans

### What to NEVER do in Onboarding
- Never say "RaddFlix is powered by Jazz" or "in partnership with Jazz"
- Never show a Jazz logo or badge
- Never say "activate your Jazz bundle" — we don't activate anything on their SIM
- Never ask for Jazz SIM number or Jazz account login

---

## 7. In-App Surfaces That Reference "Free Streaming"

### Home Screen Hero
- Show the data-saved counter (signalNumeral: "⚡ 4.2 GB saved this month")
- This is visible proof of the value proposition — not marketing copy, but live fact.
- Position it bottom-left of the hero as per Volume V layout spec.

### "Free to Watch ⚡" Rail
- Second rail on Home (after Trending or Continue Watching)
- Content with `is_free = 1` — freely accessible even on Free plan
- The ⚡ badge on each card signals data-free availability
- Rail label: "Free Hai ⚡" or "Free to Watch ⚡"

### Player Data-Saved Toast
- After playback ends (or at the 30-minute mark), show a subtle toast:
  > "⚡ 1.4 GB saved this session"
- This reinforces the zero-data value at exactly the moment users feel it.

### Settings / Account Screen
- "Data Saved This Month: 12.7 GB" — a running total
- "On Jazz SIM: Streaming is free (no data bundle used)"
- Never say HOW it's free. Just confirm that it is.

---

## 8. Support & FAQ Copy (User-Visible)

**Q: How is streaming free on Jazz SIM?**
A: "RaddFlix content is delivered through a network that Jazz doesn't charge data for.
   As long as you have a Jazz SIM, you can stream without any active bundle."
   *(True. Does not mention JazzDrive by name.)*

**Q: Is RaddFlix an official Jazz app?**
A: "RaddFlix is an independent Pakistani streaming app. We're not part of Jazz, but our
   content delivery works seamlessly on Jazz SIMs at zero data cost."
   *(Honest. Clears the record without damaging the perception.)*

**Q: Will it work on other networks (Zong, Telenor, Ufone)?**
A: "RaddFlix works on all networks, but data-free streaming is currently only available
   on Jazz SIM. Other network users will need an active data bundle to stream."
   *(True. Honest. Positions Jazz SIM as the premium use case.)*

**Q: Why isn't RaddFlix on the Play Store?**
A: "We're in early access right now. Download the APK directly from our website to
   get access before the official launch."
   *(True. Makes early access feel exclusive, not a limitation.)*

**Q: What happens when I run out of my monthly data quota?**
A: "Your plan includes X GB of streaming per month. Once you hit your limit, streaming
   pauses until your plan renews. You can upgrade your plan anytime."

---

## 9. Marketing Channels (for Controlled Early Rollout)

Given the 10–200 user target scale, mass marketing is not the goal yet.
These are the appropriate channels for controlled growth:

### WhatsApp (Primary)
- Share APK download link via trusted groups (family, close friends, uni groups)
- WhatsApp bot already exists for support — extend it for onboarding
- Word of mouth is the only safe marketing channel at this scale

### Private Telegram Channel / Group
- Controlled membership (invite-only or via link)
- Announcement channel for new content, app updates
- Support group for bug reports

### Instagram / TikTok (Soft, No Scale)
- Create accounts under the RaddFlix brand
- Post content-related clips (drama teasers, movie highlights) — no ads
- Never post technical explanations; only lifestyle/entertainment content
- Do not run paid ads at this stage

### What NOT to Do (Until Scale is Larger and Legal Footing is Clear)
- No YouTube ads
- No Google Play listing
- No App Store listing
- No press coverage / tech blog outreach
- No influencer partnerships
- No Jazz-adjacent marketing (no posts like "save your Jazz data" etc.)

---

## 10. The One-Sentence Pitch (Internal Reference)

> **RaddFlix is a Pakistani streaming app that gives Jazz SIM users a full movie and
> drama library with zero data cost, priced below what Jazz charges for data alone.**

Every agent, developer, designer, and marketer working on this product should be
able to say this sentence from memory. If a feature or decision doesn't serve this
sentence, question whether it belongs in the roadmap.

---

*Document owner: Product (human). Last updated by: AI agent session 2026-07-21.*
*Update this document whenever the business model, pricing, positioning, or brand
direction changes. It is the source of truth for product presentation.*

# relieve

Hosted app: https://relieve-slckyy.pages.dev/
Public fictional quote demo: https://relieve-slckyy.pages.dev/quote/

One shared, phone-first customer-workflow PWA with tenant-isolated Supabase PostgreSQL/Auth and Cloudflare Pages Functions. Website submissions enter the Automan Automotives demonstration business automatically. Manual Acquisition remains available. Notes exist only inside each opportunity's customer details and persist through Lost, recovery, Done, and Archive.

## Owner walkthrough

Read `docs/HOW TO USE RELIEVE — FROM CUSTOMER ADDED FROM WEBSITE TO GOOGLE REVIEW SENT.txt`.
Passwords are not in this repository. A private owner/worker sign-in file is on the operator's PC.

## Development

Node 24 and pnpm. Run `pnpm install --frozen-lockfile`, `pnpm build`, then `pnpm dev`. Copy `.env.example` to `.dev.vars` and supply your own project configuration. Never commit `.dev.vars` or `.secrets`.

The frontend's publishable Supabase configuration is `public/config.js`; update its CSP host in `public/_headers` when using another project. These are browser-safe values under enforced RLS. Privileged secrets only belong in the server environment.

Apply SQL files in `supabase/migrations` in filename order to a new Supabase project. All tables use RLS, no authenticated user can directly write core business tables, and transactional `command` operations enforce membership, business scope, explicit approvals, version conflicts and idempotency. The website's destination is chosen by server configuration, never visitor input.

## Checks

- `pnpm test`: four isolated worker request-boundary checks.
- `pnpm build`: bundles app + Worker and verifies all eleven approved assets.
- `node test/live.mjs`: 20 actual database workflow/access checks. Requires private `.secrets/project.json` and `.secrets/demo.json` produced by operator demo provisioning.
- `node test/hosted.mjs`: seven deployed HTTPS + real-database integration checks.
- `node test/additional.mjs`: five invitation/access/date/correction checks.

Live tests create explicitly fictional records in the demo, never real-business records. Run them only against a configured rehearsal project; inspect the target first. Reports in `docs/*test-results.json` record executed results. Tests never send customer messages. See `docs/VERIFICATION.md` for physical-device and failure-simulation limits.

## Deploy

The deployed Cloudflare project is `relieve-slckyy`, production branch `main`, on Pages Free. The quote site is the `/quote/` route. Supabase project: `gzdhcvlhugeziscbtucv`, Free. See `docs/HOSTING.md` for configuration, rollback, backup scope, onboarding, quota monitoring and limitations. No local PC process is needed after deployment.

## Design and ownership

Approved assets come from the user's `for codex` folder. The supplied SANCTION visual/motion modules were reused and adapted in relieve; SANCTION itself was not modified. Three.js attribution is in `THIRD_PARTY_NOTICES.txt` and its vendor header.

# Hosting and operations

## Live deployment

- App: https://relieve-slckyy.pages.dev/
- Quote website: https://relieve-slckyy.pages.dev/quote/
- GitHub: https://github.com/slckyy/relieve
- Cloudflare Pages project: `relieve-slckyy`, production `main`, direct upload, Pages/Workers Free.
- Supabase project: `gzdhcvlhugeziscbtucv`, organization `relieve-rehearsal`, Free/Nano, West US (Oregon).
- Production does not depend on the developer PC. PostgreSQL/Auth run in Supabase and API endpoints run on Cloudflare.

No paid resource, card, custom domain or subscription was activated by this build. Expected additional cost is $0 within the configured free allowances; this is not an unlimited-capacity or uptime promise.

## Configuration

Cloudflare production runtime uses compatibility date `2026-11-06`, `nodejs_compat`, and **Fail closed**. Only `/api/*` invokes the worker, leaving static pages outside the function quota.

Text environment variables: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `DEMO_BUSINESS_ID`, `VAPID_PUBLIC_KEY`, `APP_ORIGIN`.
Encrypted secret environment variables: `SUPABASE_SECRET_KEY`, `RATE_LIMIT_SALT`, `BACKUP_SIGNING_KEY`, `VAPID_PRIVATE_KEY`.

`APP_ORIGIN` is `https://relieve-slckyy.pages.dev`. The destination business is server-selected with `DEMO_BUSINESS_ID`; a visitor-supplied tenant ID is rejected. Cloudflare receives the service secret only in its encrypted server environment. No private key appears in frontend assets or Git. `.secrets` and `.dev.vars` are ignored.

Supabase Auth Site URL is the app origin, with redirects confined to `https://relieve-slckyy.pages.dev/**`. Staff setup/recovery links return to this app. Core tables enforce RLS. Users without an active membership cannot read business data or invoke mutations. Workers cannot change business settings or manage staff; the owner controls account actions.

## Build, publish, rollback

Use Node 24 + pnpm. Run `pnpm install --frozen-lockfile`, `pnpm test`, `pnpm build`.

After authenticating the official Cloudflare CLI, `pnpm deploy` uploads `dist` to `relieve-slckyy` production. Alternatively, Cloudflare Workers & Pages > relieve-slckyy > More actions > Create deployment > Production > upload a ZIP whose root is the CONTENTS of `dist` > Save and deploy. Runtime setting changes require redeployment. Do not upload source, `.secrets` or `.dev.vars`.

Git commits alone do not trigger this direct-upload project. Push source to GitHub and publish the matching built bundle as a separate step. Cloudflare Deployments records versions and offers rollback; database migrations are append-only and are not automatically rolled back with the frontend. Back up before a schema change. Inspect current production before rolling back to a version that predates a migration.

## Demo identities and onboarding

The private PC file `C:\Users\griffey\Documents\relieve-private\DEMO SIGN IN.txt` contains reusable owner and worker demonstration credentials. Never put it in a public share or Git. The reserved `.invalid` email identities cannot receive mail. Owners can change their password inside Account; an owner locked out of this demo needs the Supabase project administrator.

Owner-generated worker invitation and recovery links are copied privately, not automatically emailed. The deployed API invitation → token verification → password setup → worker membership path was exercised. Revoking a worker immediately denied direct database reads and writes. Existing owners cannot be overwritten through invitation.

No production SMTP provider is configured. Supabase's default mail service is constrained and is not a production onboarding/recovery guarantee. Before real paying customers, verify a suitable mail provider, delivery, rate limits and recovery ownership. The copied one-time staff-link path works without SMTP, but delivering it privately remains the owner's responsibility.

Future businesses share this same app and schema. Operator provisioning currently creates the business and owner membership, then binds their quote-site server environment to that business. Set `public/quote/settings.js` for website branding/demo-number validation; set the matching Cloudflare tenant environment. This is template configuration, not automatic multi-site provisioning. Use the actual business identity and a verified direct HTTPS Google review destination. Keep the current Automan demo isolated and fictional.

## Persistence, retry and limits

Database transactions serialize writes per business, retain audit history, check record versions and deduplicate request keys. Website retries preserve their request key in session storage. A newly submitted request always creates a new opportunity; a matching customer profile does not overwrite old work. Linked events are unique per job/type.

Public intake is JSON-only, bounded to 20 KB, same-origin when Origin is present, server-mapped, and limited in the database to 5 per minute / 40 per day per hashed IP plus 500 per day per business. No raw IP is stored. These controls reduce obvious abuse but are not a substitute for monitoring targeted attacks. Restore payloads are limited to 4 MB. The app loads lists in groups of 40 and polls for current activity every 10 seconds while visible.

Monitor Supabase database size, API egress and Auth usage; monitor Cloudflare Worker requests/CPU/errors. Free Supabase currently includes 500 MB database and 5 GB egress; low-activity projects can pause. Cloudflare Workers Free currently allows 100,000 requests/day with constrained CPU. The 27 MB model/artwork package is delivered by Pages static hosting and cached by the PWA, not stored in the database.

Sources checked 2026-11-06:
- https://supabase.com/pricing
- https://supabase.com/docs/guides/platform/free-project-pausing
- https://supabase.com/docs/guides/auth/auth-smtp
- https://supabase.com/kb/faqs/platform/free-plan-backups
- https://developers.cloudflare.com/pages/functions/pricing/
- https://developers.cloudflare.com/workers/platform/limits/

## Backup / restore scope

Account > EXPORT BUSINESS BACKUP generates a signed JSON snapshot of the current business, customer profiles, opportunities (including notes and archives), events and audit records. The owner downloads it; keep it private and separately backed up. Account > RESTORE BACKUP verifies the HMAC, owner and business before one transactional merge.

The tested restore restores matching customer/job/event fields and reinstates missing records with their original identifiers. It keeps records created after the snapshot and retains current audit history. Versions increase to invalidate stale edits. It does not restore business settings, staff/Auth accounts, passwords, push subscriptions, or an entirely deleted project. Exported audit history stays in the backup; it is not replayed into the current audit table. A restored deleted manual event is recreated. Matching events are updated, so export a fresh safety backup before a restore.

This is a tested same-business correction/recovery mechanism, not a full disaster-recovery or point-in-time system. Save the signing key securely with your operational recovery materials; losing it prevents the app from accepting old signed snapshots. The Free Supabase plan does not provide the paid automatic-backup guarantees. Before live production, establish independent database/Auth backups, retention, off-site storage and a separately exercised full-project restore. No unattended backup service is claimed configured.

## Notifications and phone actions

Saved Activity is the reliable source of history. VAPID Web Push is implemented through the service worker and encrypted device subscriptions. The hosted API was exercised, but the available browser had no subscribed physical device; zero accepted device deliveries is not a successful push-delivery test. Follow the final phone check in the owner guide. Notification failure cannot undo saved work.

Native phone and SMS links prepare actions on the user's device. The app never places a call, sends a text, verifies delivery, or infers that opening a draft means sent. `google.com` is explicitly a demo placeholder. No calls or customer texts were sent by these tests.

# Verification record — 2026-11-06

Executed against the real Supabase project and https://relieve-slckyy.pages.dev, not mocked responses:

- 20 database checks: `live-test-results.json` and `test/live.mjs`.
- 7 hosted integration checks: `hosted-test-results.json` and `test/hosted.mjs`.
- 5 extra invitation/revocation/date/correction checks: `additional-test-results.json` and `test/additional.mjs`.
- 4 isolated Worker boundary checks: `node --test test/worker.test.mjs` passed.
- `node scripts/build.js` passed, including all eleven original assets.

The hosted test submitted a fictional request over HTTPS, retrieved the persisted opportunity using independent owner/worker sessions, rejected another business, and walked the request through Quoting → Work → Review → Done. It checked quoting appointments, cancellation, work rescheduling, notes, audit entries and truthful review skipping. Both RPC and signed deployed-API backup restores were executed and verified; modified signatures and cross-business restores were rejected. Invitation verification/password setup was tested via the real Supabase Auth API with a disposable fictional identity; its access was then revoked and read/write denial verified.

Browser walkthrough on the deployed site: “Fictional Jordan Demo”, reserved (417) 555-0110, was submitted with the real three-field website form. It appeared in Acquisition with source and received time. A note was saved in its details, quoting was scheduled, work was approved and rescheduled, fictional completion was recorded, the exact populated review draft and placeholder warning were inspected, and “Skipped — Demonstration, no text sent” moved it to Done. Its note and historical tabs remained. Screenshot: `screenshots/completed-job-notes.png`.

Browser inspection used observed 430×932 mobile and 1280×720 desktop layouts. Forms, native date controls, lists, popups, model selector, live analytics, return navigation, details tabs, note saving and startup after refresh were exercised. An anchor-button overlap in the review draft was found and corrected before final publication. Additional narrow viewport requests were not applied by the environment, so a 360 px browser run is NOT claimed. Real touch-keyboard/safe-area behavior requires a physical phone.

NOT VERIFIED ON A PHYSICAL DEVICE: iOS/Android PWA installation, actual OS push delivery while closed, native dialer/SMS composer launch, touch gestures with real device GPU, and full-motion timing. The environment prefers reduced motion; that preference was preserved. No customer call/text was sent. Review Sent requires explicit confirmation; tests reject false confirmation, while walkthroughs use Skipped honestly. No SMS delivery can be inferred by this product.

Interrupted-response behavior: repeated identical website and command keys returned the same record; changed payload/key conflicts were rejected. Simultaneous stale worker edits were rejected with refresh guidance. Full airplane-mode, throttled-radio and service-outage browser fault injection was NOT available and is not claimed tested. The app preserves an open form on save error, refuses offline writes, offers startup retry/sign-out and shows a connectivity message. Verify those on the target phones before real production use.

Production caveats: no configured production SMTP or full-project automatic disaster backup; only same-business signed merge restore has been tested. Free-plan quotas and inactivity pause apply. Business and website onboarding remains operator-managed. This is a hosted, functional sales demo, not a claim of audited production readiness or guaranteed notification delivery.

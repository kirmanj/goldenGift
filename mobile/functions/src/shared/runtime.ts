/**
 * Runtime switches shared by every function.
 */

/**
 * SRS §7 / §8: callables enforce App Check. The apps activate App Check from
 * Phase 10 (mobile: Play Integrity / App Attest; web: reCAPTCHA Enterprise),
 * but enforcing before every client is registered in the Firebase console
 * would reject all calls — so it is a deploy-time switch, not code:
 * `ENFORCE_APP_CHECK=true` in functions/.env (or the CI environment), then
 * redeploy. Pass it as `enforceAppCheck: ENFORCE_APP_CHECK` to every `onCall`.
 * The emulator never enforces.
 */
export const ENFORCE_APP_CHECK =
  process.env.ENFORCE_APP_CHECK === 'true' && process.env.FUNCTIONS_EMULATOR !== 'true';

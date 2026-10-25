/**
 * `zainCashReturn` (HTTPS GET, SRS §7): ZainCash sends the customer's browser
 * here after the pay page — `?sid={sessionId}&token={JWT}` (no token when the
 * customer pressed "Cancel and go back").
 *
 * The token is verified with the merchant secret (HS256, algorithm and expiry
 * checked) and must name this session (`orderid` == sid) and its gateway
 * transaction; only then is the session settled (settlePayment.ts). Without a
 * verified token nothing changes — a pending session simply expires
 * (`expirePaymentSessions`) unless it is paid. With ZainCash's PUBLIC sandbox
 * merchant (whose secret everybody knows) a token proves nothing, so the outcome
 * is first confirmed with the gateway's own status check (`checkTransaction`); if
 * that check fails, nothing is settled now and the expiry job reconciles later.
 *
 * Only GET is served (the browser redirect); every value echoed into the page is
 * validated (`sid`: [A-Za-z0-9_-]) and HTML-escaped, and the only link is the
 * fixed `goldengift://payment` deep link — never a URL taken from the request.
 *
 * The response is a small trilingual page that opens the app at
 * `goldengift://payment?sid={sid}&status={paid|failed|pending|expired|error}`,
 * with a button and a fallback text. The app must treat `status` as a hint and
 * read `payment_sessions/{sid}` (or the order) for the truth.
 */
import { logger as functionsLogger } from 'firebase-functions/v2';
import { RETURN_PAGE_BUTTON, RETURN_PAGE_HINT, RETURN_PAGE_TEXT } from './paymentTexts';
import { settlePaymentSession, type SettleDeps } from './settlePayment';
import { GatewayTokenError, type PaymentGateway } from './zainCash';

export const APP_PAYMENT_DEEP_LINK = 'goldengift://payment';

export type ReturnStatus = keyof typeof RETURN_PAGE_TEXT;

export interface ReturnDeps extends SettleDeps {
  /** null = not configured: tokens cannot be verified. */
  gateway: PaymentGateway | null;
}

export interface ReturnResponse {
  httpStatus: number;
  sid: string | null;
  status: ReturnStatus;
  html: string;
}

const SESSION_ID = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * `sid` and `token` from the query. ZainCash appends `token` to the redirect URL;
 * if it appends it with a second `?` (`…?sid=X?token=Y`), `sid` holds both.
 */
export function parseReturnQuery(query: Record<string, unknown>): { sid: string | null; token: string | null } {
  const first = (v: unknown): string | null => {
    const s = Array.isArray(v) ? v[0] : v;
    return typeof s === 'string' && s.length > 0 ? s : null;
  };
  let sid = first(query.sid);
  let token = first(query.token);
  if (sid !== null && sid.includes('?')) {
    const [head, tail] = [sid.slice(0, sid.indexOf('?')), sid.slice(sid.indexOf('?') + 1)];
    sid = head;
    token ??= new URLSearchParams(tail).get('token');
  }
  return {
    sid: sid !== null && SESSION_ID.test(sid) ? sid : null,
    token: token !== null && token.length <= 8192 ? token : null,
  };
}

export async function handleZainCashReturn(deps: ReturnDeps, query: Record<string, unknown>): Promise<ReturnResponse> {
  const log = deps.logger ?? functionsLogger;
  const nowMs = (deps.now ?? Date.now)();
  const { sid, token } = parseReturnQuery(query);
  const respond = (httpStatus: number, status: ReturnStatus, id: string | null): ReturnResponse => ({
    httpStatus,
    sid: id,
    status,
    html: returnPage(id, status),
  });

  if (token === null) return respond(200, 'pending', sid);
  if (deps.gateway === null) {
    log.error('zainCashReturn: gateway not configured, token not verified', { sid });
    return respond(503, 'error', sid);
  }

  let verdict;
  try {
    verdict = deps.gateway.verifyReturn(token, nowMs);
  } catch (e) {
    if (e instanceof GatewayTokenError) {
      log.warn('zainCashReturn: token refused', { sid, reason: e.reason });
      return respond(400, 'error', sid);
    }
    throw e;
  }
  if (!SESSION_ID.test(verdict.reference) || (sid !== null && sid !== verdict.reference)) {
    log.warn('zainCashReturn: token names another session', { sid, reference: verdict.reference });
    return respond(400, 'error', sid);
  }
  if (deps.gateway.confirmsReturnServerSide === true && verdict.outcome !== 'pending') {
    try {
      const check = await deps.gateway.checkTransaction(verdict.transactionId, nowMs);
      if (check.reference !== null && check.reference !== verdict.reference) {
        log.warn('zainCashReturn: gateway check names another session', { sid: verdict.reference });
        return respond(400, 'error', verdict.reference);
      }
      verdict = { ...verdict, outcome: check.outcome, rawStatus: check.rawStatus || verdict.rawStatus };
    } catch (e) {
      log.warn('zainCashReturn: gateway status check failed, nothing settled', {
        sid: verdict.reference,
        error: e instanceof Error ? e.message : String(e),
      });
      return respond(503, 'pending', verdict.reference);
    }
  }

  const result = await settlePaymentSession(deps, verdict.reference, verdict);
  if (!result.found) {
    log.warn('zainCashReturn: unknown session', { sid: verdict.reference });
    return respond(404, 'error', verdict.reference);
  }
  if (result.mismatch) return respond(400, 'error', verdict.reference);
  if (result.changed) log.info('zainCashReturn', { sid: verdict.reference, status: result.status, effect: result.effect });
  return respond(200, result.status, verdict.reference);
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

/** The deep link back into the app. */
export function appDeepLink(sid: string | null, status: ReturnStatus): string {
  const params = new URLSearchParams({ ...(sid !== null && { sid }), status });
  return `${APP_PAYMENT_DEEP_LINK}?${params.toString()}`;
}

/** Self-contained page (inline CSS, one inline script), gold on white / gold on black. */
export function returnPage(sid: string | null, status: ReturnStatus): string {
  const link = escapeHtml(appDeepLink(sid, status));
  const title = RETURN_PAGE_TEXT[status];
  const ok = status === 'paid';
  const lines = (['en', 'ar', 'ku'] as const)
    .map((l) => {
      const dir = l === 'en' ? 'ltr' : 'rtl';
      const lang = l === 'ku' ? 'ckb' : l;
      return `<section dir="${dir}" lang="${lang}"><h1>${escapeHtml(title[l])}</h1><p>${escapeHtml(RETURN_PAGE_HINT[l])}</p></section>`;
    })
    .join('');
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Golden Gift</title>
<style>
:root{--bg:#FAFAF7;--card:#FFFFFF;--text:#1E1E2A;--muted:#6B6F80;--gold:#C9A227;--on-gold:#1F1A08;--mark:${ok ? '#2E9E5B' : '#D32F2F'}}
@media (prefers-color-scheme:dark){:root{--bg:#0E0E0F;--card:#1A1A1C;--text:#F4F1E8;--muted:#B0ADA3;--gold:#E3C04A}}
body{margin:0;background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:480px;margin:0 auto;padding:40px 16px;text-align:center}
.mark{width:56px;height:56px;border-radius:50%;margin:0 auto 16px;background:var(--mark)}
section{background:var(--card);border-radius:18px;padding:12px 16px;margin:12px 0}
h1{font-size:20px;margin:4px 0}p{color:var(--muted);margin:4px 0;font-size:14px}
a.btn{display:block;margin:24px 0 0;padding:16px;border-radius:999px;background:var(--gold);color:var(--on-gold);font-weight:700;text-decoration:none}
</style></head>
<body><main><div class="mark"></div>${lines}
<a class="btn" href="${link}">${escapeHtml(RETURN_PAGE_BUTTON.en)} · ${escapeHtml(RETURN_PAGE_BUTTON.ar)} · ${escapeHtml(RETURN_PAGE_BUTTON.ku)}</a>
</main><script>setTimeout(function(){location.href=${JSON.stringify(appDeepLink(sid, status))};},300);</script></body></html>`;
}

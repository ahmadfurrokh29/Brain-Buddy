// Brain Buddy nudge sender (Cloudflare Worker).
//
// POST /nudge  { squadId, toUid }   with header  Authorization: Bearer <Firebase ID token>
//
// 1. Verifies the caller's Firebase sign-in (so nobody can send nudges without an account).
// 2. Checks caller and friend are in the same squad.
// 3. Allows 3 nudges per person pair per hour.
// 4. Sends the push through Firebase Cloud Messaging. It has a notification part, so Android shows it
//    even when Brain Buddy is closed; when the app is open, the app shows it itself.
//
// The Firebase service-account key lives only here, as the secret FIREBASE_SERVICE_ACCOUNT.

const NUDGES_PER_WINDOW = 3;
const WINDOW_MS = 60 * 60 * 1000;
const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

export default {
  async fetch(request, env, ctx) {
    if (request.method !== 'POST' || new URL(request.url).pathname !== '/nudge') {
      return json({ error: 'not found' }, 404);
    }
    try {
      const projectId = env.FIREBASE_PROJECT_ID;
      const sa = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT);
      // Checking the sign-in and getting Google's access token don't depend on each other: do both at once.
      const [fromUid, token, body] = await Promise.all([
        verifyIdToken(request.headers.get('Authorization'), projectId),
        accessToken(sa),
        request.json().catch(() => ({})),
      ]);
      if (!fromUid) return json({ error: 'not signed in' }, 401);

      const { squadId, toUid } = body;
      if (typeof squadId !== 'string' || typeof toUid !== 'string' || toUid === fromUid) {
        return json({ error: 'bad request' }, 400);
      }

      const fs = (path) => `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/${path}`;
      const auth = { Authorization: `Bearer ${token}` };
      const pairPath = `nudges/${fromUid}_${toUid}`;

      // All four reads at once (they used to run one after another, which made nudges slow).
      const [squad, pair, tokenDoc, sender] = await Promise.all([
        getDoc(fs(`squads/${encodeURIComponent(squadId)}`), auth),
        getDoc(fs(pairPath), auth),
        getDoc(fs(`fcmTokens/${toUid}`), auth),
        getDoc(fs(`squads/${encodeURIComponent(squadId)}/members/${fromUid}`), auth),
      ]);

      // Same squad?
      const members = (squad?.fields?.memberUids?.arrayValue?.values ?? []).map((v) => v.stringValue);
      if (!members.includes(fromUid) || !members.includes(toUid)) return json({ error: 'not in this squad' }, 403);

      // Rate limit per pair: at most 3 in any hour.
      const now = Date.now();
      const recent = (pair?.fields?.times?.arrayValue?.values ?? [])
        .map((v) => Number(v.integerValue ?? 0))
        .filter((t) => now - t < WINDOW_MS)
        .sort((a, b) => a - b);
      if (recent.length >= NUDGES_PER_WINDOW) {
        const retryMs = recent[recent.length - NUDGES_PER_WINDOW] + WINDOW_MS - now;
        return json({ error: 'too soon', retryInMinutes: Math.max(1, Math.ceil(retryMs / 60000)) }, 429);
      }

      const pushToken = tokenDoc?.fields?.token?.stringValue;
      if (!pushToken) return json({ error: 'friend has no notifications' }, 404);

      const name = sender?.fields?.name?.stringValue ?? 'A friend';
      const avatar = sender?.fields?.avatar?.stringValue ?? '👋';

      const send = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
        method: 'POST',
        headers: { ...auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: {
            token: pushToken,
            notification: { title: `${avatar} Nudge from ${name}`, body: 'Time to put the reels down? Your squad believes in you!' },
            data: { type: 'nudge', squadId, fromName: name },
            android: { priority: 'high', notification: { channel_id: 'nudges' } },
          },
        }),
      });
      if (!send.ok) {
        const err = await send.text();
        // The friend uninstalled or the token expired: forget it.
        if (send.status === 404 || err.includes('UNREGISTERED')) {
          ctx.waitUntil(fetch(fs(`fcmTokens/${toUid}`), { method: 'DELETE', headers: auth }));
          return json({ error: 'friend has no notifications' }, 404);
        }
        return json({ error: 'push failed' }, 502);
      }

      // Remember this nudge for the rate limit after answering, so the sender doesn't wait for it.
      const times = [...recent, now].map((t) => ({ integerValue: String(t) }));
      ctx.waitUntil(fetch(fs(pairPath), {
        method: 'PATCH',
        headers: { ...auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ fields: { times: { arrayValue: { values: times } } } }),
      }));
      return json({ ok: true, left: NUDGES_PER_WINDOW - times.length });
    } catch (e) {
      return json({ error: 'server error' }, 500);
    }
  },
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

async function getDoc(url, headers) {
  const r = await fetch(url, { headers });
  return r.ok ? r.json() : null;
}

// ------------------------------------------------------------------ Firebase ID token check

let jwksCache = { keys: null, until: 0 };

async function verifyIdToken(header, projectId) {
  // Any malformed token is simply "not signed in".
  try {
    return await checkIdToken(header, projectId);
  } catch {
    return null;
  }
}

async function checkIdToken(header, projectId) {
  const token = header?.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return null;
  const [h, p, s] = token.split('.');
  if (!h || !p || !s) return null;
  const head = JSON.parse(b64urlText(h));
  const claims = JSON.parse(b64urlText(p));
  const now = Math.floor(Date.now() / 1000);
  if (head.alg !== 'RS256') return null;
  if (claims.aud !== projectId || claims.iss !== `https://securetoken.google.com/${projectId}`) return null;
  if (claims.exp < now || claims.iat > now + 300 || !claims.sub) return null;

  if (!jwksCache.keys || Date.now() > jwksCache.until) {
    const r = await fetch(JWKS_URL);
    jwksCache = { keys: (await r.json()).keys, until: Date.now() + 60 * 60 * 1000 };
  }
  const jwk = jwksCache.keys.find((k) => k.kid === head.kid);
  if (!jwk) return null;
  const key = await crypto.subtle.importKey('jwk', jwk, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);
  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, b64urlBytes(s), new TextEncoder().encode(`${h}.${p}`));
  return ok ? claims.sub : null;
}

// ------------------------------------------------------------------ Google access token from the service account

let tokenCache = { token: null, until: 0 };

async function accessToken(sa) {
  if (tokenCache.token && Date.now() < tokenCache.until) return tokenCache.token;
  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }));
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${claims}`));
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${header}.${claims}.${b64urlFromBytes(new Uint8Array(sig))}`,
  });
  const body = await r.json();
  tokenCache = { token: body.access_token, until: Date.now() + 50 * 60 * 1000 };
  return body.access_token;
}

// ------------------------------------------------------------------ base64url helpers

function b64url(text) {
  return b64urlFromBytes(new TextEncoder().encode(text));
}

function b64urlFromBytes(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlBytes(s) {
  const pad = s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4);
  return Uint8Array.from(atob(pad), (c) => c.charCodeAt(0));
}

function b64urlText(s) {
  return new TextDecoder().decode(b64urlBytes(s));
}

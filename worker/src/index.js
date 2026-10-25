// Brain Bean nudge sender (Cloudflare Worker).
//
// POST /nudge  { squadId, toUid }   with header  Authorization: Bearer <Firebase ID token>
//
// 1. Verifies the caller's Firebase sign-in (so nobody can send nudges without an account).
// 2. Checks caller and friend are in the same squad.
// 3. Allows 3 nudges per person pair per hour.
// 4. Sends the push through Firebase Cloud Messaging. It has a notification part, so Android shows it
//    even when Brain Bean is closed; when the app is open, the app shows it itself.
//
// Once a day (cron, see wrangler.toml) it also tidies squads: members whose app hasn't checked in for
// 30 days are removed, the owner role moves on if the owner was one of them, and empty squads are deleted.
// The app checks in daily even on days without reels, so people who simply stopped watching stay in.
//
// POST /delete-account (same Authorization header) deletes the caller's whole online account: squads
// (handing a squad over or deleting it if they were the last one), nickname, cloud backup, push address,
// nudge notes and finally the login. It runs here with admin rights because Firebase only lets an app
// delete a login that signed in minutes ago; this way one tap in the app is enough.
//
// The Firebase service-account key lives only here, as the secret FIREBASE_SERVICE_ACCOUNT.

const INACTIVE_MS = 30 * 24 * 60 * 60 * 1000;
// The free plan allows 50 outgoing requests per run; stop a little before that.
const CLEANUP_REQUEST_BUDGET = 45;
const NUDGES_PER_WINDOW = 3;
const WINDOW_MS = 60 * 60 * 1000;
const JWKS_URL = 'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(cleanUpSquads(env, fetch).then((r) => console.log('squad clean-up', JSON.stringify(r))));
  },

  async fetch(request, env, ctx) {
    const path = new URL(request.url).pathname;
    if (request.method === 'POST' && path === '/delete-account') return deleteAccount(request, env);
    if (request.method !== 'POST' || path !== '/nudge') {
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

// ------------------------------------------------------------------ deleting an account

async function deleteAccount(request, env) {
  try {
    const projectId = env.FIREBASE_PROJECT_ID;
    const uid = await verifyIdToken(request.headers.get('Authorization'), projectId);
    if (!uid) return json({ error: 'not signed in' }, 401);
    const token = await accessToken(JSON.parse(env.FIREBASE_SERVICE_ACCOUNT));
    const auth = { Authorization: `Bearer ${token}` };
    const dbPath = `projects/${projectId}/databases/(default)`;
    const docs = `https://firestore.googleapis.com/v1/${dbPath}/documents`;
    const writes = [];

    // Squads: leave each one. The last one out deletes it; an owner leaving hands it to the next member.
    const q = await fetch(`${docs}:runQuery`, {
      method: 'POST',
      headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: 'squads' }],
          where: { fieldFilter: { field: { fieldPath: 'memberUids' }, op: 'ARRAY_CONTAINS', value: { stringValue: uid } } },
        },
      }),
    });
    if (!q.ok) throw new Error(`squad query ${q.status}`);
    for (const row of await q.json()) {
      const squad = row.document;
      if (!squad) continue;
      const f = squad.fields ?? {};
      const others = (f.memberUids?.arrayValue?.values ?? []).map((v) => v.stringValue).filter((m) => m !== uid);
      if (others.length === 0) {
        for (const name of await listNames(`https://firestore.googleapis.com/v1/${squad.name}/members`, auth)) writes.push({ delete: name });
        if (f.code?.stringValue) writes.push({ delete: `${dbPath}/documents/codes/${f.code.stringValue}` });
        writes.push({ delete: squad.name });
      } else {
        const fields = { memberUids: { arrayValue: { values: others.map((m) => ({ stringValue: m })) } } };
        const mask = ['memberUids'];
        if (f.ownerUid?.stringValue === uid) {
          fields.ownerUid = { stringValue: others[0] };
          mask.push('ownerUid');
        }
        writes.push({ update: { name: squad.name, fields }, updateMask: { fieldPaths: mask } });
        writes.push({ delete: `${squad.name}/members/${uid}` });
      }
    }

    // Cloud backup, nickname, push address.
    for (const name of await listNames(`${docs}/users/${uid}/days`, auth)) writes.push({ delete: name });
    writes.push({ delete: `${dbPath}/documents/users/${uid}/backup/settings` });
    writes.push({ delete: `${dbPath}/documents/users/${uid}` });
    writes.push({ delete: `${dbPath}/documents/fcmTokens/${uid}` });

    // Nudge rate-limit notes this person sent or received ("from_to").
    for (const name of await listNames(`${docs}/nudges`, auth)) {
      const id = name.split('/').pop();
      if (id.startsWith(`${uid}_`) || id.endsWith(`_${uid}`)) writes.push({ delete: name });
    }

    // Firestore takes up to 500 writes per commit.
    for (let i = 0; i < writes.length; i += 450) {
      const c = await fetch(`https://firestore.googleapis.com/v1/${dbPath}/documents:commit`, {
        method: 'POST',
        headers: { ...auth, 'Content-Type': 'application/json' },
        body: JSON.stringify({ writes: writes.slice(i, i + 450) }),
      });
      if (!c.ok) throw new Error(`commit ${c.status}: ${await c.text()}`);
    }

    // Finally the login itself.
    const d = await fetch(`https://identitytoolkit.googleapis.com/v1/projects/${projectId}/accounts:delete`, {
      method: 'POST',
      headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({ localId: uid }),
    });
    if (!d.ok) throw new Error(`delete login ${d.status}: ${await d.text()}`);
    return json({ ok: true });
  } catch (e) {
    console.log('delete-account failed', String(e));
    return json({ error: 'server error' }, 500);
  }
}

/** Full names of all documents in a collection (just the names, no fields). */
async function listNames(collectionUrl, auth) {
  const names = [];
  let pageToken = '';
  do {
    const r = await fetch(`${collectionUrl}?pageSize=300&mask.fieldPaths=__name__${pageToken ? `&pageToken=${pageToken}` : ''}`, { headers: auth });
    if (!r.ok) {
      if (r.status === 404) return names;
      throw new Error(`list ${r.status}`);
    }
    const page = await r.json();
    for (const doc of page.documents ?? []) names.push(doc.name);
    pageToken = page.nextPageToken ?? '';
  } while (pageToken);
  return names;
}

// ------------------------------------------------------------------ daily squad clean-up

/** Removes inactive members from every squad. [http] is fetch (swappable in tests). */
export async function cleanUpSquads(env, http, now = Date.now()) {
  const result = { squads: 0, membersRemoved: 0, squadsDeleted: 0, stoppedEarly: false };
  let requests = 0;
  const call = async (url, init) => {
    requests++;
    return http(url, init);
  };
  const token = await accessToken(JSON.parse(env.FIREBASE_SERVICE_ACCOUNT));
  requests++; // the token request
  const auth = { Authorization: `Bearer ${token}` };
  const base = `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)/documents`;

  let pageToken = '';
  do {
    const r = await call(`${base}/squads?pageSize=100${pageToken ? `&pageToken=${pageToken}` : ''}`, { headers: auth });
    if (!r.ok) throw new Error(`listing squads failed: ${r.status}`);
    const page = await r.json();
    for (const squad of page.documents ?? []) {
      // Each squad needs up to 3 requests (read members, update squad, delete numbers).
      if (requests + 3 > CLEANUP_REQUEST_BUDGET) {
        result.stoppedEarly = true;
        return result;
      }
      result.squads++;
      await cleanSquad(squad, base, auth, now, call, result);
    }
    pageToken = page.nextPageToken ?? '';
  } while (pageToken);
  return result;
}

async function cleanSquad(squad, base, auth, now, call, result) {
  const squadUrl = `https://firestore.googleapis.com/v1/${squad.name}`;
  const f = squad.fields ?? {};
  const memberUids = (f.memberUids?.arrayValue?.values ?? []).map((v) => v.stringValue);
  const ownerUid = f.ownerUid?.stringValue;
  const code = f.code?.stringValue;

  // When each member's app last wrote its numbers (or joined). Someone with no numbers yet counts from
  // when the squad was made.
  const r = await call(`${squadUrl}/members?pageSize=50`, { headers: auth });
  if (!r.ok) return;
  const members = (await r.json()).documents ?? [];
  const lastSeen = new Map(members.map((m) => [m.name.split('/').pop(), Date.parse(m.updateTime)]));
  const created = Date.parse(squad.createTime);
  const inactive = memberUids.filter((uid) => now - (lastSeen.get(uid) ?? created) > INACTIVE_MS);
  if (inactive.length === 0) return;

  const keep = memberUids.filter((uid) => !inactive.includes(uid));
  const writes = [];
  if (keep.length === 0) {
    // Nobody left: delete the squad, its invite code and everyone's numbers in one go.
    for (const m of members) writes.push({ delete: m.name });
    if (code) writes.push({ delete: `${base.replace('https://firestore.googleapis.com/v1/', '')}/codes/${code}` });
    writes.push({ delete: squad.name });
    result.squadsDeleted++;
  } else {
    const fields = { memberUids: { arrayValue: { values: keep.map((uid) => ({ stringValue: uid })) } } };
    const mask = ['memberUids'];
    if (inactive.includes(ownerUid)) {
      // The owner left for good: the longest-standing remaining member takes over.
      fields.ownerUid = { stringValue: keep[0] };
      mask.push('ownerUid');
    }
    writes.push({ update: { name: squad.name, fields }, updateMask: { fieldPaths: mask } });
    for (const uid of inactive) if (lastSeen.has(uid)) writes.push({ delete: `${squad.name}/members/${uid}` });
  }
  result.membersRemoved += inactive.length;

  const dbPath = squad.name.split('/documents/')[0];
  const commit = await call(`https://firestore.googleapis.com/v1/${dbPath}/documents:commit`, {
    method: 'POST',
    headers: { ...auth, 'Content-Type': 'application/json' },
    body: JSON.stringify({ writes }),
  });
  if (!commit.ok) console.log('squad clean-up failed for', squad.name, commit.status, await commit.text());
}

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
    // datastore: Firestore. firebase.messaging: pushes. identitytoolkit: deleting a login.
    scope: 'https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging '
      + 'https://www.googleapis.com/auth/identitytoolkit',
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

/**
 * Strand's roast gateway.
 *
 * The Gemini key lives here, never in the app. The app sends its Firebase ID
 * token, this worker proves the token, proves the two people are friends,
 * reads the two nights straight from Firestore, and only then asks Gemini for
 * one roast. The result is cached in `narratives/{pairId}` so both people see
 * the same paragraph.
 *
 * Free-tier only: one fixed model, no paid fallback, no model switching. Any
 * quota or provider failure is reported as a failure and nothing is invented.
 */

const GEMINI_ENDPOINT =
  'https://generativelanguage.googleapis.com/v1beta/interactions';
const GEMINI_API_REVISION = '2026-05-20';
const SECURETOKEN_JWK_URL =
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com';
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const CLOUDFLARE_JSON_HEADERS = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*',
  'access-control-allow-headers': 'authorization, content-type',
  'access-control-allow-methods': 'POST, GET, OPTIONS',
  'cache-control': 'no-store',
};

const MAX_DAY_COUNT = 3;
const CLAIM_TTL_MS = 120 * 1000;
const ERROR_RETRY_MS = 10 * 60 * 1000;
const GEMINI_TIMEOUT_MS = 65 * 1000;

/**
 * Bump this whenever the prompt changes shape.
 *
 * The version is part of the cache fingerprint, so a bump makes every stored
 * paragraph stale exactly once: the next request rewrites it in the new
 * format, and every request after that reuses the rewrite. Without this an
 * old paragraph would live forever, because the sleep data it describes has
 * not changed and the fingerprint would still match.
 */
const PROMPT_VERSION = 2;

const SYSTEM_PROMPT = `You are the Night Roast Master for Strand, a sleep journal.

Two people have shared their sleep reports. You are the witty friend who has seen both nights and cannot resist commenting.

YOUR VOICE
- Warm, sharp, conversational. One playful roast, never cruel.
- Never insult appearance, intelligence, worth, relationships, health, or identity.
- No generic AI phrasing ("Let's dive in", "Interestingly", "It's worth noting").

WHAT TO WRITE
- 45-65 words. Three or four short sentences. One paragraph.
- Compare both people's sleep using only the supplied facts.
- Include one interesting observation drawn from those numbers.
- Include one playful, intelligent roast.
- End with one useful, meaningful takeaway.
- Use both names exactly as given.
- No bullet points, headings, lists, or line breaks. No metric-by-metric rundown. No greeting or sign-off.
- Never invent a number, event, dream, or comparison. If a value is missing, ignore it.
- A sleep stage does not prove what anyone dreamed. Dream jokes only as clear speculation, never as recorded fact.
- No medical, diagnostic, or health conclusions. Do not imply a stage is unhealthy.

Return only the paragraph. No preamble, no quotation marks, no markdown.`;

/**
 * The dream interpreter.
 *
 * This is deliberately a different voice from the roast. A dream is something
 * the writer chose to hand over, so the answer is warm and careful rather than
 * funny: one grounded reading of the images, hedged, and never a diagnosis or
 * a prediction. The phone stores the words beside the dream, so this text has
 * to stand on its own without the sleep numbers.
 */
const DREAM_SYSTEM_PROMPT = `You are Strand's dream companion, a thoughtful sleep journal.

Someone has written down a dream. Read it and answer with one short interpretation.

YOUR VOICE
- Warm, grounded, curious. The tone of a perceptive friend, not a clinician.
- Plain, everyday language. No mystical jargon, no horoscopes, no predictions.

WHAT TO WRITE
- 55-95 words. Two or three sentences. One paragraph.
- Pick one or two images or feelings that are actually in the dream and say what they might reflect about the writer's waking life.
- Offer a possible reading, never a verdict. Use "may", "might", "could".
- Never diagnose, never predict the future, never give medical or health advice.
- Never invent a detail, a person, or an event that the dream does not contain.
- No bullet points, headings, lists, or line breaks. No greeting or sign-off.

Return only the paragraph. No preamble, no quotation marks, no markdown.`;

/* ------------------------------------------------------------------ */
/* Small helpers                                                       */
/* ------------------------------------------------------------------ */

const encoder = new TextEncoder();
const decoder = new TextDecoder();

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: CLOUDFLARE_JSON_HEADERS,
  });
}

function bytesToB64url(bytes) {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlToBytes(value) {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function pemToBytes(pem) {
  const body = String(pem)
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  return b64urlToBytes(body.replace(/\+/g, '-').replace(/\//g, '_'));
}

function displayName(raw) {
  const value = String(raw == null ? '' : raw).trim();
  if (!value) return '';
  return value.replace(/(^|[\s'’-])(\p{L})/gu, (_match, lead, letter) =>
    lead + letter.toUpperCase(),
  );
}

function pickName(friendship, uid) {
  const members = Array.isArray(friendship.members) ? friendship.members : [];
  const raw =
    members[0] === uid ? friendship.nameA : friendship.nameB;
  return displayName(raw) || 'One of you';
}

/* ------------------------------------------------------------------ */
/* Firebase ID token verification                                      */
/* ------------------------------------------------------------------ */

let jwkCache = { keys: new Map(), expiresAt: 0 };
let serviceKeyCache = null;
let accessTokenCache = { token: '', expiresAt: 0 };

async function secureTokenKeys() {
  if (jwkCache.keys.size > 0 && Date.now() < jwkCache.expiresAt) {
    return jwkCache.keys;
  }
  const response = await fetch(SECURETOKEN_JWK_URL, {
    headers: { accept: 'application/json' },
  });
  if (!response.ok) throw new Error('jwk_unavailable');
  const body = await response.json();
  const keys = new Map();
  for (const jwk of body.keys || []) {
    if (!jwk.kid || jwk.kty !== 'RSA') continue;
    keys.set(jwk.kid, jwk);
  }
  const cacheControl = response.headers.get('cache-control') || '';
  const match = cacheControl.match(/max-age=(\d+)/);
  const maxAge = match ? Number(match[1]) : 3600;
  jwkCache = {
    keys,
    expiresAt: Date.now() + Math.max(300, maxAge - 60) * 1000,
  };
  return keys;
}

async function verifyIdToken(idToken, projectId) {
  const parts = String(idToken || '').split('.');
  if (parts.length !== 3) throw new Error('token_malformed');
  const [headerPart, payloadPart, signaturePart] = parts;
  const header = JSON.parse(decoder.decode(b64urlToBytes(headerPart)));
  const payload = JSON.parse(decoder.decode(b64urlToBytes(payloadPart)));
  if (header.alg !== 'RS256' || !header.kid) throw new Error('token_alg');

  const keys = await secureTokenKeys();
  const jwk = keys.get(header.kid);
  if (!jwk) throw new Error('token_kid');

  const key = await crypto.subtle.importKey(
    'jwk',
    { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  const valid = await crypto.subtle.verify(
    'RSASSA-PKCS1-v1_5',
    key,
    b64urlToBytes(signaturePart),
    encoder.encode(`${headerPart}.${payloadPart}`),
  );
  if (!valid) throw new Error('token_signature');

  const now = Math.floor(Date.now() / 1000);
  if (payload.aud !== projectId) throw new Error('token_audience');
  if (payload.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new Error('token_issuer');
  }
  if (typeof payload.exp !== 'number' || payload.exp <= now) {
    throw new Error('token_expired');
  }
  if (typeof payload.iat !== 'number' || payload.iat > now + 120) {
    throw new Error('token_issued');
  }
  if (!payload.sub || typeof payload.sub !== 'string') {
    throw new Error('token_subject');
  }
  return payload.sub;
}

/* ------------------------------------------------------------------ */
/* Google service-account token (server-only Firestore access)         */
/* ------------------------------------------------------------------ */

async function serviceAccountKey(env) {
  if (serviceKeyCache) return serviceKeyCache;
  const pem = env.FIREBASE_PRIVATE_KEY;
  if (!pem) throw new Error('missing_service_account_key');
  serviceKeyCache = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(pem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  return serviceKeyCache;
}

async function accessToken(env) {
  if (accessTokenCache.token && Date.now() < accessTokenCache.expiresAt) {
    return accessTokenCache.token;
  }
  const email = env.FIREBASE_CLIENT_EMAIL;
  if (!email) throw new Error('missing_service_account_email');
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = bytesToB64url(
    encoder.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })),
  );
  const claims = bytesToB64url(
    encoder.encode(
      JSON.stringify({
        iss: email,
        scope: 'https://www.googleapis.com/auth/datastore',
        aud: GOOGLE_TOKEN_URL,
        iat: issuedAt,
        exp: issuedAt + 3600,
      }),
    ),
  );
  const unsigned = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    await serviceAccountKey(env),
    encoder.encode(unsigned),
  );
  const assertion = `${unsigned}.${bytesToB64url(new Uint8Array(signature))}`;
  const response = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body:
      'grant_type=' +
      encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer') +
      '&assertion=' +
      encodeURIComponent(assertion),
  });
  if (!response.ok) throw new Error(`service_token_${response.status}`);
  const body = await response.json();
  if (!body.access_token) throw new Error('service_token_empty');
  accessTokenCache = {
    token: body.access_token,
    expiresAt: Date.now() + Math.max(60, (body.expires_in || 3600) - 120) * 1000,
  };
  return accessTokenCache.token;
}

/* ------------------------------------------------------------------ */
/* Firestore REST                                                      */
/* ------------------------------------------------------------------ */

function firestoreBase(env) {
  return `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/databases/(default)`;
}

function toField(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toField) } };
  }
  if (typeof value === 'object') {
    return { mapValue: { fields: toFields(value) } };
  }
  return { nullValue: null };
}

function toFields(object) {
  const fields = {};
  for (const [key, value] of Object.entries(object)) {
    fields[key] = toField(value);
  }
  return fields;
}

function fromField(field) {
  if (!field || typeof field !== 'object') return null;
  if ('nullValue' in field) return null;
  if ('stringValue' in field) return field.stringValue;
  if ('integerValue' in field) return Number(field.integerValue);
  if ('doubleValue' in field) return Number(field.doubleValue);
  if ('booleanValue' in field) return field.booleanValue;
  if ('timestampValue' in field) return field.timestampValue;
  if ('mapValue' in field) return fromFields(field.mapValue.fields || {});
  if ('arrayValue' in field) {
    return (field.arrayValue.values || []).map(fromField);
  }
  return null;
}

function fromFields(fields) {
  const out = {};
  for (const [key, value] of Object.entries(fields || {})) {
    out[key] = fromField(value);
  }
  return out;
}

async function firestoreGet(env, path) {
  const token = await accessToken(env);
  const response = await fetch(`${firestoreBase(env)}/documents/${path}`, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`firestore_get_${response.status}`);
  const body = await response.json();
  return {
    data: fromFields(body.fields),
    updateTime: body.updateTime,
  };
}

async function firestorePatch(env, path, data, precondition) {
  const token = await accessToken(env);
  const mask = Object.keys(data)
    .map((key) => `updateMask.fieldPaths=${encodeURIComponent(key)}`)
    .join('&');
  let query = mask;
  if (precondition && precondition.updateTime) {
    query += `&currentDocument.updateTime=${encodeURIComponent(
      precondition.updateTime,
    )}`;
  } else if (precondition && precondition.create) {
    query += '&currentDocument.exists=false';
  }
  const response = await fetch(
    `${firestoreBase(env)}/documents/${path}?${query}`,
    {
      method: 'PATCH',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ fields: toFields(data) }),
    },
  );
  if (response.status === 409 || response.status === 412) return null;
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`firestore_patch_${response.status}:${text.slice(0, 160)}`);
  }
  const body = await response.json();
  return { data: fromFields(body.fields), updateTime: body.updateTime };
}

async function latestNight(env, uid) {
  const token = await accessToken(env);
  const url =
    `${firestoreBase(env)}/documents/users/${encodeURIComponent(uid)}/nights` +
    '?orderBy=date%20desc&pageSize=1';
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`firestore_nights_${response.status}`);
  const body = await response.json();
  const document = (body.documents || [])[0];
  if (!document) return null;
  return { data: fromFields(document.fields), updateTime: document.updateTime };
}

/* ------------------------------------------------------------------ */
/* Data shaping                                                        */
/* ------------------------------------------------------------------ */

function dayKeyInLosAngeles(now) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Los_Angeles',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now);
}

function minutesToClock(minutes) {
  if (typeof minutes !== 'number' || !Number.isFinite(minutes)) return null;
  const value = ((Math.round(minutes) % 1440) + 1440) % 1440;
  const hours = String(Math.floor(value / 60)).padStart(2, '0');
  const mins = String(value % 60).padStart(2, '0');
  return `${hours}:${mins}`;
}

/** Only facts the app actually recorded. Missing stays missing. */
function nightReport(night) {
  const n = night || {};
  const minutes = (ms) =>
    typeof ms === 'number' && Number.isFinite(ms)
      ? Math.max(0, Math.round(ms / 60000))
      : null;
  const report = {
    date: n.date || null,
    asleep_minutes: minutes(n.asleepMs),
    deep_minutes: minutes(n.deepMs),
    rem_minutes: minutes(n.remMs),
    light_minutes: minutes(n.lightMs),
    awake_minutes: minutes(n.awakeMs),
    time_in_bed_minutes: minutes(n.timeInBedMs),
    bed_time: minutesToClock(n.bedMinutes),
    wake_time: minutesToClock(n.wakeMinutes),
    sessions: typeof n.sessionCount === 'number' ? n.sessionCount : null,
    stage_spans: Array.isArray(n.spans) ? n.spans.length : null,
  };
  for (const key of Object.keys(report)) {
    if (report[key] === null) delete report[key];
  }
  return report;
}

function fingerprint(nightA, nightB) {
  return JSON.stringify({
    // The prompt version is part of the fingerprint on purpose: a new prompt
    // invalidates old text even when the nights are unchanged.
    v: PROMPT_VERSION,
    a: nightReport(nightA),
    b: nightReport(nightB),
  });
}

function isUsableRoast(text) {
  if (typeof text !== 'string') return false;
  const clean = text
    .replace(/^["“”']+|["“”']+$/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!clean) return false;
  if (clean.length > 900) return false;
  if (clean.includes('```') || clean.includes('**')) return false;
  const words = clean.split(/\s+/).filter(Boolean).length;
  // The prompt asks for 45-65. The accepted band is wider so a good paragraph
  // a few words over is kept rather than thrown away and regenerated.
  return words >= 30 && words <= 85;
}

function cleanRoast(text) {
  return text
    .replace(/^["“”']+|["“”']+$/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function isUsableDream(text) {
  if (typeof text !== 'string') return false;
  const clean = text
    .replace(/^["“”']+|["“”']+$/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!clean) return false;
  if (clean.length > 1200) return false;
  if (clean.includes('```') || clean.includes('**')) return false;
  const words = clean.split(/\s+/).filter(Boolean).length;
  // The prompt asks for 55-95. The band is wider on both sides so a good
  // reading that runs a little short or long is kept, not discarded.
  return words >= 25 && words <= 120;
}

/* ------------------------------------------------------------------ */
/* Gemini                                                              */
/* ------------------------------------------------------------------ */

/**
 * One request to the fixed model. Nothing here decides *what* was asked for;
 * the two callers below own their prompts and their own validation, because a
 * roast that fails its rules and a dream reading that fails its rules mean
 * different things and are reported differently.
 */
async function callGemini(env, systemInstruction, input, maxOutputTokens) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), GEMINI_TIMEOUT_MS);
  try {
    const response = await fetch(GEMINI_ENDPOINT, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': env.GEMINI_API_KEY,
        'Api-Revision': GEMINI_API_REVISION,
      },
      body: JSON.stringify({
        model: env.GEMINI_MODEL,
        system_instruction: systemInstruction,
        input,
        generation_config: {
          thinking_level: 'low',
          max_output_tokens: maxOutputTokens,
        },
        store: false,
      }),
      signal: controller.signal,
    });

    if (response.status === 429) return { status: 'quota' };
    if (!response.ok) return { status: 'error' };

    const body = await response.json();
    if (body.status !== 'completed') return { status: 'error' };

    const text = (body.steps || [])
      .filter((step) => step && step.type === 'model_output')
      .flatMap((step) => step.content || [])
      .filter((part) => part && part.type === 'text' && part.text)
      .map((part) => part.text)
      .join(' ');

    return { status: 'ok', text };
  } catch (_) {
    return { status: 'error' };
  } finally {
    clearTimeout(timer);
  }
}

async function generateRoast(env, nameA, nameB, nightA, nightB) {
  const userText =
    'Here are the two sleep reports for the same sleep period.\n\n' +
    `${nameA}:\n${JSON.stringify(nightReport(nightA))}\n\n` +
    `${nameB}:\n${JSON.stringify(nightReport(nightB))}\n\n` +
    'Write the roast now. Follow the system instruction exactly.';

  const result = await callGemini(env, SYSTEM_PROMPT, userText, 3000);
  if (result.status !== 'ok') return result;
  if (!isUsableRoast(result.text)) return { status: 'error' };
  return { status: 'ok', text: cleanRoast(result.text) };
}

async function generateDream(env, dream) {
  const userText =
    'The dream, exactly as the writer recorded it:\n\n' +
    `${dream}\n\n` +
    'Write the interpretation now. Follow the system instruction exactly.';

  const result = await callGemini(env, DREAM_SYSTEM_PROMPT, userText, 1200);
  if (result.status !== 'ok') return result;
  if (!isUsableDream(result.text)) return { status: 'error' };
  return { status: 'ok', text: cleanRoast(result.text) };
}

/* ------------------------------------------------------------------ */
/* The one endpoint                                                    */
/* ------------------------------------------------------------------ */

async function handleRoast(request, env) {
  const projectId = env.FIREBASE_PROJECT_ID;
  if (!projectId || !env.GEMINI_API_KEY || !env.GEMINI_MODEL) {
    return json({ status: 'error' }, 500);
  }

  const authorization = request.headers.get('authorization') || '';
  const idToken = authorization.startsWith('Bearer ')
    ? authorization.slice(7).trim()
    : '';
  if (!idToken) return json({ status: 'unauthorized' }, 401);

  let uid;
  try {
    uid = await verifyIdToken(idToken, projectId);
  } catch (_) {
    return json({ status: 'unauthorized' }, 401);
  }

  let friendUid = '';
  try {
    const body = await request.json();
    friendUid = typeof body.friendUid === 'string' ? body.friendUid.trim() : '';
  } catch (_) {
    return json({ status: 'bad_request' }, 400);
  }
  if (!friendUid || friendUid === uid) {
    return json({ status: 'bad_request' }, 400);
  }

  const members = [uid, friendUid].sort();
  const pairId = `${members[0]}_${members[1]}`;

  const friendship = await firestoreGet(env, `friendships/${pairId}`);
  const friendMembers = friendship ? friendship.data.members || [] : [];
  if (
    !friendship ||
    friendMembers.length !== 2 ||
    !friendMembers.includes(uid) ||
    !friendMembers.includes(friendUid)
  ) {
    return json({ status: 'not_friends' }, 403);
  }

  const [myNight, theirNight] = await Promise.all([
    latestNight(env, members[0]),
    latestNight(env, members[1]),
  ]);
  if (!myNight || !theirNight) {
    return json({ status: 'unavailable' });
  }

  const nightA = myNight.data;
  const nightB = theirNight.data;
  if (!nightA.date || !nightB.date) {
    return json({ status: 'unavailable' });
  }

  const nameA = pickName(friendship.data, members[0]);
  const nameB = pickName(friendship.data, members[1]);
  const print = fingerprint(nightA, nightB);
  const dateKeyA = String(nightA.date);
  const dateKeyB = String(nightB.date);
  const path = `narratives/${pairId}`;

  const existingDoc = await firestoreGet(env, path);
  const existing = existingDoc ? existingDoc.data : null;
  const sameFingerprint = Boolean(existing && existing.fingerprint === print);

  if (sameFingerprint) {
    if (existing.status === 'ready' && existing.text) {
      return json({ status: 'ok', text: existing.text });
    }
    if (existing.status === 'generating') {
      const age = Date.now() - Number(existing.claimedAt || 0);
      if (age < CLAIM_TTL_MS) return json({ status: 'generating' });
    }
    if (existing.status === 'quota') {
      return json({ status: 'quota' });
    }
    if (existing.status === 'error') {
      const age = Date.now() - Number(existing.claimedAt || 0);
      if (age < ERROR_RETRY_MS) return json({ status: 'error' });
    }
  }

  const today = dayKeyInLosAngeles(new Date());
  const previousCount = sameFingerprint
    ? Number(existing.dayCount || 0)
    : existing && existing.dayKey === today
      ? Number(existing.dayCount || 0)
      : 0;

  if (previousCount >= MAX_DAY_COUNT) {
    await firestorePatch(
      env,
      path,
      {
        members,
        dateKeyA,
        dateKeyB,
        fingerprint: print,
        status: 'quota',
        text: '',
        dayKey: today,
        dayCount: previousCount,
        claimedAt: Date.now(),
        generatedAt: Number(existing && existing.generatedAt) || 0,
      },
      existingDoc ? { updateTime: existingDoc.updateTime } : { create: true },
    );
    return json({ status: 'quota' });
  }

  const dayCount = previousCount + 1;
  const claimedAt = Date.now();
  const claim = {
    members,
    dateKeyA,
    dateKeyB,
    fingerprint: print,
    status: 'generating',
    text: '',
    dayKey: today,
    dayCount,
    claimedAt,
    generatedAt: Number(existing && existing.generatedAt) || 0,
  };

  const claimed = await firestorePatch(
    env,
    path,
    claim,
    existingDoc ? { updateTime: existingDoc.updateTime } : { create: true },
  );

  if (!claimed) {
    // Someone else claimed first. Report what they left behind.
    const latestDoc = await firestoreGet(env, path);
    const latest = latestDoc ? latestDoc.data : null;
    if (latest && latest.fingerprint === print) {
      if (latest.status === 'ready' && latest.text) {
        return json({ status: 'ok', text: latest.text });
      }
      if (latest.status === 'quota') return json({ status: 'quota' });
      if (latest.status === 'error') return json({ status: 'error' });
    }
    return json({ status: 'generating' });
  }

  const result = await generateRoast(env, nameA, nameB, nightA, nightB);

  if (result.status !== 'ok') {
    await firestorePatch(
      env,
      path,
      {
        members,
        dateKeyA,
        dateKeyB,
        fingerprint: print,
        status: result.status,
        text: '',
        dayKey: today,
        dayCount,
        claimedAt: Date.now(),
        generatedAt: Number(claimed.data.generatedAt) || 0,
      },
      { updateTime: claimed.updateTime },
    );
    return json({ status: result.status });
  }

  const finalDoc = await firestorePatch(
    env,
    path,
    {
      members,
      dateKeyA,
      dateKeyB,
      fingerprint: print,
      status: 'ready',
      text: result.text,
      dayKey: today,
      dayCount,
      claimedAt,
      generatedAt: Date.now(),
    },
    { updateTime: claimed.updateTime },
  );

  if (!finalDoc) {
    const latestDoc = await firestoreGet(env, path);
    const latest = latestDoc ? latestDoc.data : null;
    if (latest && latest.status === 'ready' && latest.text) {
      return json({ status: 'ok', text: latest.text });
    }
    return json({ status: 'error' });
  }

  return json({ status: 'ok', text: result.text });
}

/* ------------------------------------------------------------------ */
/* Dream interpretation                                                */
/* ------------------------------------------------------------------ */

function bearerToken(request) {
  const authorization = request.headers.get('authorization') || '';
  return authorization.startsWith('Bearer ')
    ? authorization.slice(7).trim()
    : '';
}

/**
 * Interprets one dream for the person who wrote it.
 *
 * No Firestore document and no cache: a dream belongs to one person and is
 * written once. Only the Firebase token is required, and the Gemini key still
 * never leaves the worker. There is no friend check here because nothing is
 * shared — the text never touches another account.
 */
async function handleDream(request, env) {
  const projectId = env.FIREBASE_PROJECT_ID;
  if (!projectId || !env.GEMINI_API_KEY || !env.GEMINI_MODEL) {
    return json({ status: 'error' }, 500);
  }

  const idToken = bearerToken(request);
  if (!idToken) return json({ status: 'unauthorized' }, 401);
  try {
    await verifyIdToken(idToken, projectId);
  } catch (_) {
    return json({ status: 'unauthorized' }, 401);
  }

  let dream = '';
  try {
    const body = await request.json();
    dream = typeof body.text === 'string' ? body.text.trim() : '';
  } catch (_) {
    return json({ status: 'bad_request' }, 400);
  }
  if (dream.length < 3 || dream.length > 4000) {
    return json({ status: 'bad_request' }, 400);
  }

  const result = await generateDream(env, dream);
  if (result.status !== 'ok') return json({ status: result.status });
  return json({ status: 'ok', text: result.text });
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CLOUDFLARE_JSON_HEADERS });
    }
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/health') {
      return json({ ok: true, model: env.GEMINI_MODEL || null });
    }
    if (request.method === 'POST' && url.pathname === '/dream') {
      try {
        return await handleDream(request, env);
      } catch (error) {
        return json(
          {
            status: 'error',
            detail: String(error && error.message ? error.message : error).slice(
              0,
              180,
            ),
          },
          500,
        );
      }
    }
    if (request.method !== 'POST' || url.pathname !== '/roast') {
      return json({ status: 'not_found' }, 404);
    }
    try {
      return await handleRoast(request, env);
    } catch (error) {
      return json(
        {
          status: 'error',
          detail: String(error && error.message ? error.message : error).slice(
            0,
            180,
          ),
        },
        500,
      );
    }
  },
};

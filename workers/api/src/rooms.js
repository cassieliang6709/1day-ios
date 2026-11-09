/**
 * Rooms, members, clips, reactions, comments and pokes — everything that used
 * to live in CloudKit's public database, in D1, with videos and avatars in R2.
 *
 * Two rules hold everywhere:
 * - Whoever is signed in is the author. A body never names its own author;
 *   an id that has an author baked into it must have this caller's.
 * - Knowing a room's code is what lets you see it, as it was on CloudKit.
 */
import {
  bad,
  forbidden,
  HttpError,
  int,
  isUUID,
  json,
  notFound,
  readJson,
  recordName,
  roomCode,
  str,
  time,
} from './http.js';
import { notifyRoom } from './push.js';
import { mediaPrefix } from './media.js';

const NAME = 64;
const TITLE = 200;
const TEXT = 4000;
const CAPTIONS = 32 * 1024;
/** D1 allows 100 bound values per statement. */
const CHUNK = 50;

const chunks = (list, size = CHUNK) => {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
};
const marks = (n, from = 1) => Array.from({ length: n }, (_, i) => `?${i + from}`).join(',');

// MARK: - Row shapes

export function roomJson(r) {
  return {
    code: r.code,
    title: r.title,
    startDate: r.start_date,
    ownerID: r.owner_id,
    ownerName: r.owner_name,
    mode: r.mode,
    clipLength: r.clip_length,
    orientation: r.orientation,
    cameraStyle: r.camera_style ?? null,
    templateName: r.template_name ?? null,
    momentTitles: r.moment_titles ?? null,
  };
}

function memberJson(m) {
  return {
    userID: m.user_id,
    displayName: m.display_name,
    avatarKey: m.avatar_key ?? null,
    moodKind: m.mood_kind ?? null,
    moodDay: m.mood_day ?? null,
    roomTitle: m.room_title ?? null,
    roomTitleAt: m.room_title_at ?? null,
    joinedAt: m.joined_at,
    updatedAt: m.updated_at,
  };
}

function clipJson(c) {
  return {
    id: c.id,
    day: c.day,
    authorID: c.author_id,
    authorName: c.author_name,
    recordedAt: c.recorded_at,
    videoKey: c.video_key,
    overlayText: c.overlay_text ?? null,
    captionSticker: c.caption_sticker ?? null,
    captionsJSON: c.captions_json ?? null,
  };
}

function reactionJson(r) {
  return {
    id: r.id,
    day: r.day,
    emoji: r.emoji,
    authorID: r.author_id,
    authorName: r.author_name,
    targetAuthorID: r.target_author_id,
    createdAt: r.created_at,
  };
}

function commentJson(c) {
  return {
    id: c.id,
    roomCode: c.room_code,
    day: c.day ?? null,
    text: c.text,
    authorID: c.author_id,
    authorName: c.author_name,
    targetAuthorID: c.target_author_id ?? null,
    createdAt: c.created_at,
  };
}

// MARK: - Names the app derives (must match CloudKitService)

export const memberId = (code, userId) => `${code}_${userId}`;

export function clipIdBelongs(id, code, me, day) {
  const first = `${code}_${me}_day${day}`;
  return id === first || (id.startsWith(`${first}_`) && isUUID(id.slice(first.length + 1)));
}

/** Swift writes each unicode scalar's value, joined by `-`. */
export function reactionId(code, target, me, day, emoji) {
  const scalars = Array.from(emoji, (c) => String(c.codePointAt(0))).join('-');
  return `${code}_${target}_day${day}_${me}_${scalars}`;
}

export function pokeIdBelongs(id, code, me, target) {
  const prefix = `${code}_poke_${me}_${target}_`;
  return id.startsWith(prefix) && /^\d{4}-\d{2}-\d{2}$/.test(id.slice(prefix.length));
}

function ownMedia(key, me) {
  return typeof key === 'string' && key.startsWith(mediaPrefix(me)) && key.length < 300;
}

// MARK: - Rooms

async function createRoom(request, env, { me }) {
  const b = await readJson(request);
  const code = roomCode(b.code);
  const now = Date.now();
  const result = await env.DB.prepare(
    `INSERT INTO rooms (code, title, start_date, owner_id, owner_name, mode, clip_length,
       orientation, camera_style, template_name, moment_titles, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?3)
     ON CONFLICT (code) DO NOTHING`
  )
    .bind(
      code,
      str(b.title, TITLE),
      now,
      me,
      str(b.ownerName, NAME),
      str(b.mode, 32),
      str(b.clipLength, 32),
      str(b.orientation, 32),
      str(b.cameraStyle, 32, { optional: true }),
      str(b.templateName, TITLE, { optional: true }),
      str(b.momentTitles, TEXT, { optional: true })
    )
    .run();
  // The code is taken; the app picks another and tries again.
  if (!result.meta?.changes) throw new HttpError(409, 'code_taken');
  const room = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?1').bind(code).first();
  return json(roomJson(room), 201);
}

async function getRoom(env, code) {
  const room = await env.DB.prepare('SELECT * FROM rooms WHERE code = ?1').bind(code).first();
  if (!room) throw notFound();
  return json(roomJson(room));
}

/** Only the owner's name can change, and only by the owner — account
 * deletion replaces it with "deleted member". */
async function patchRoom(request, env, { me }, code) {
  const b = await readJson(request);
  const ownerName = str(b.ownerName, NAME);
  const room = await env.DB.prepare('SELECT owner_id FROM rooms WHERE code = ?1').bind(code).first();
  if (!room) throw notFound();
  if (room.owner_id !== me) throw forbidden();
  await env.DB.prepare('UPDATE rooms SET owner_name = ?2 WHERE code = ?1').bind(code, ownerName).run();
  return json({ ok: true });
}

async function myRooms(env, { me }) {
  const [members, owned] = await env.DB.batch([
    env.DB.prepare(
      'SELECT room_code, display_name, avatar_key FROM members WHERE user_id = ?1 ORDER BY updated_at DESC'
    ).bind(me),
    env.DB.prepare('SELECT * FROM rooms WHERE owner_id = ?1').bind(me),
  ]);
  const rows = members.results ?? [];
  return json({
    memberCodes: rows.map((m) => m.room_code),
    owned: (owned.results ?? []).map(roomJson),
    displayName: rows.find((m) => m.display_name)?.display_name ?? null,
    avatarKey: rows.find((m) => m.avatar_key)?.avatar_key ?? null,
  });
}

// MARK: - Members

async function listMembers(env, code) {
  const { results } = await env.DB.prepare('SELECT * FROM members WHERE room_code = ?1')
    .bind(code)
    .all();
  return json({ members: (results ?? []).map(memberJson) });
}

/**
 * Upsert my member record in a room. Every field is optional and a field left
 * out keeps what the record had — joining, the avatar and mood, and a rename
 * all write here, and none may undo another. An empty name means "not known
 * on this phone", never a new name.
 */
async function putMember(request, env, { me }, code) {
  const b = await readJson(request);
  const displayName = str(b.displayName, NAME, { optional: true }) ?? '';
  const joinedAt = time(b.joinedAt, { optional: true });
  const avatarKey = b.avatarKey ?? null;
  if (avatarKey !== null && !ownMedia(avatarKey, me)) throw bad('bad_media');
  const moodKind = str(b.moodKind, 32, { optional: true });
  const moodDay = time(b.moodDay, { optional: true });
  if ((moodKind === null) !== (moodDay === null)) throw bad();
  const roomTitle = str(b.roomTitle, TITLE, { optional: true });
  const roomTitleAt = time(b.roomTitleAt, { optional: true });
  if ((roomTitle === null) !== (roomTitleAt === null)) throw bad();

  const id = memberId(code, me);
  const now = Date.now();
  const old = await env.DB.prepare('SELECT avatar_key FROM members WHERE id = ?1').bind(id).first();
  await env.DB.prepare(
    `INSERT INTO members (id, room_code, user_id, display_name, joined_at, avatar_key,
       mood_kind, mood_day, room_title, room_title_at, updated_at)
     VALUES (?1, ?2, ?3, ?4, COALESCE(?5, ?11), ?6, ?7, ?8, ?9, ?10, ?11)
     ON CONFLICT (id) DO UPDATE SET
       display_name  = CASE WHEN excluded.display_name <> '' THEN excluded.display_name ELSE members.display_name END,
       joined_at     = CASE WHEN ?5 IS NOT NULL THEN excluded.joined_at ELSE members.joined_at END,
       avatar_key    = COALESCE(excluded.avatar_key, members.avatar_key),
       mood_kind     = COALESCE(excluded.mood_kind, members.mood_kind),
       mood_day      = COALESCE(excluded.mood_day, members.mood_day),
       room_title    = COALESCE(excluded.room_title, members.room_title),
       room_title_at = COALESCE(excluded.room_title_at, members.room_title_at),
       updated_at    = excluded.updated_at`
  )
    .bind(id, code, me, displayName, joinedAt, avatarKey, moodKind, moodDay, roomTitle, roomTitleAt, now)
    .run();
  if (avatarKey && old?.avatar_key && old.avatar_key !== avatarKey) {
    await deleteMediaIfUnused(env, [old.avatar_key]);
  }
  return json({ ok: true });
}

// MARK: - Clips

async function listClips(env, code) {
  const { results } = await env.DB.prepare(
    'SELECT * FROM clips WHERE room_code = ?1 ORDER BY day, recorded_at'
  )
    .bind(code)
    .all();
  return json({ clips: (results ?? []).map(clipJson) });
}

/** Upload, or upload again: a retried take lands on the same row. The video
 * itself went up first (`POST /media`); this points the clip at it. */
async function putClip(request, env, ctx, { me }, id) {
  const b = await readJson(request);
  const code = roomCode(b.roomCode);
  const day = int(b.day, { min: 0, max: 100_000 });
  if (!clipIdBelongs(id, code, me, day)) throw forbidden();
  const videoKey = b.videoKey;
  if (!ownMedia(videoKey, me)) throw bad('bad_media');
  const authorName = str(b.authorName, NAME);
  const old = await env.DB.prepare('SELECT video_key FROM clips WHERE id = ?1').bind(id).first();
  await env.DB.prepare(
    `INSERT INTO clips (id, room_code, day, author_id, author_name, recorded_at, video_key,
       overlay_text, caption_sticker, captions_json, updated_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
     ON CONFLICT (id) DO UPDATE SET
       author_name = excluded.author_name, recorded_at = excluded.recorded_at,
       video_key = excluded.video_key, overlay_text = excluded.overlay_text,
       caption_sticker = excluded.caption_sticker, captions_json = excluded.captions_json,
       updated_at = excluded.updated_at`
  )
    .bind(
      id,
      code,
      day,
      me,
      authorName,
      time(b.recordedAt),
      videoKey,
      str(b.overlayText, TEXT, { optional: true }),
      str(b.captionSticker, TEXT, { optional: true }),
      str(b.captionsJSON, CAPTIONS, { optional: true }),
      Date.now()
    )
    .run();
  if (old?.video_key && old.video_key !== videoKey) await deleteMediaIfUnused(env, [old.video_key]);
  ctx.waitUntil(
    notifyRoom(env, { kind: 'clip', code, authorID: me, authorName, day, recordName: id })
  );
  return json({ ok: true });
}

/** Just the words on a clip already in the room — no new video. A clip that
 * isn't up yet is 404, and the app lets the next upload carry the caption. */
async function patchClip(request, env, { me }, id) {
  const b = await readJson(request);
  const clip = await env.DB.prepare('SELECT author_id FROM clips WHERE id = ?1').bind(id).first();
  if (!clip) throw notFound();
  if (clip.author_id !== me) throw forbidden();
  await env.DB.prepare(
    'UPDATE clips SET overlay_text = ?2, captions_json = ?3, updated_at = ?4 WHERE id = ?1'
  )
    .bind(
      id,
      str(b.overlayText, TEXT, { optional: true }),
      str(b.captionsJSON, CAPTIONS, { optional: true }),
      Date.now()
    )
    .run();
  return json({ ok: true });
}

// MARK: - Reactions, comments, pokes

async function putReaction(request, env, ctx, { me }, id) {
  const b = await readJson(request);
  const code = roomCode(b.roomCode);
  const day = int(b.day, { min: 0, max: 100_000 });
  const emoji = str(b.emoji, 32);
  const target = str(b.targetAuthorID, 200);
  if (!emoji || id !== reactionId(code, target, me, day, emoji)) throw forbidden();
  const authorName = str(b.authorName, NAME);
  const result = await env.DB.prepare(
    `INSERT INTO reactions (id, room_code, day, emoji, author_id, author_name, target_author_id, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
     ON CONFLICT (id) DO NOTHING`
  )
    .bind(id, code, day, emoji, me, authorName, target, Date.now())
    .run();
  if (result.meta?.changes) {
    ctx.waitUntil(notifyRoom(env, { kind: 'reaction', code, authorID: me, authorName, day, recordName: id }));
  }
  return json({ ok: true });
}

async function deleteOwn(env, table, id, me) {
  const row = await env.DB.prepare(`SELECT author_id FROM ${table} WHERE id = ?1`).bind(id).first();
  // Already gone is what was asked for.
  if (!row) return json({ ok: true });
  if (row.author_id !== me) throw forbidden();
  await env.DB.prepare(`DELETE FROM ${table} WHERE id = ?1`).bind(id).run();
  return json({ ok: true });
}

async function listComments(env, code) {
  const { results } = await env.DB.prepare(
    'SELECT * FROM comments WHERE room_code = ?1 ORDER BY created_at'
  )
    .bind(code)
    .all();
  return (results ?? []).map(commentJson);
}

async function interactions(env, code) {
  const [reactions, comments] = await Promise.all([
    env.DB.prepare('SELECT * FROM reactions WHERE room_code = ?1').bind(code).all(),
    listComments(env, code),
  ]);
  return json({ reactions: (reactions.results ?? []).map(reactionJson), comments });
}

/** Room chat and per-clip comments. The id is the app's UUID, so sending the
 * same message twice is one message. */
async function putComment(request, env, ctx, { me }, id) {
  if (!isUUID(id)) throw bad('bad_id');
  const b = await readJson(request);
  const code = roomCode(b.roomCode);
  const text = str(b.text, TEXT);
  const authorName = str(b.authorName, NAME);
  const day = int(b.day, { optional: true, min: 0, max: 100_000 });
  const existing = await env.DB.prepare('SELECT author_id FROM comments WHERE id = ?1').bind(id).first();
  if (existing && existing.author_id !== me) throw forbidden();
  await env.DB.prepare(
    `INSERT INTO comments (id, room_code, day, text, author_id, author_name, target_author_id, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
     ON CONFLICT (id) DO UPDATE SET text = excluded.text, author_name = excluded.author_name`
  )
    .bind(
      id,
      code,
      day,
      text,
      me,
      authorName,
      str(b.targetAuthorID, 200, { optional: true }),
      time(b.createdAt, { optional: true }) ?? Date.now()
    )
    .run();
  if (!existing) {
    ctx.waitUntil(
      notifyRoom(env, { kind: 'comment', code, authorID: me, authorName, day, text, recordName: id })
    );
  }
  return json({ ok: true });
}

/** Which of these message ids the room has no record of. Only an id that is
 * really absent counts — the app deletes its copy on this answer. */
async function missingComments(request, env, code) {
  const b = await readJson(request);
  if (!Array.isArray(b.ids) || b.ids.length > 1000 || !b.ids.every(isUUID)) throw bad();
  const present = new Set();
  for (const part of chunks(b.ids)) {
    const { results } = await env.DB.prepare(
      `SELECT id FROM comments WHERE room_code = ?1 AND id IN (${marks(part.length, 2)})`
    )
      .bind(code, ...part)
      .all();
    for (const row of results ?? []) present.add(row.id);
  }
  // An id that exists in another room is not "missing" either; it just
  // isn't this room's.
  const elsewhere = new Set();
  const rest = b.ids.filter((id) => !present.has(id));
  for (const part of chunks(rest)) {
    const { results } = await env.DB.prepare(
      `SELECT id FROM comments WHERE id IN (${marks(part.length)})`
    )
      .bind(...part)
      .all();
    for (const row of results ?? []) elsewhere.add(row.id);
  }
  return json({
    missing: rest.filter((id) => !elsewhere.has(id)),
    elsewhere: [...elsewhere],
  });
}

async function putPoke(request, env, ctx, { me }, id) {
  const b = await readJson(request);
  const code = roomCode(b.roomCode);
  const target = str(b.targetAuthorID, 200);
  if (!pokeIdBelongs(id, code, me, target)) throw forbidden();
  const authorName = str(b.authorName, NAME);
  const result = await env.DB.prepare(
    `INSERT INTO pokes (id, room_code, author_id, author_name, target_author_id, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6)
     ON CONFLICT (id) DO NOTHING`
  )
    .bind(id, code, me, authorName, target, Date.now())
    .run();
  if (result.meta?.changes) {
    ctx.waitUntil(
      notifyRoom(env, { kind: 'poke', code, authorID: me, authorName, targetAuthorID: target, day: 1, recordName: id })
    );
  }
  return json({ ok: true });
}

// MARK: - Leaving a room, deleting an account

/** Everything of mine in one room, by id: what leaving deletes. */
async function myRecordNames(env, { me }, code) {
  const rows = await env.DB.batch(
    ['clips', 'reactions', 'comments', 'pokes'].map((table) =>
      env.DB.prepare(`SELECT id FROM ${table} WHERE room_code = ?1 AND author_id = ?2`).bind(code, me)
    )
  );
  const names = [memberId(code, me)];
  for (const r of rows) for (const row of r.results ?? []) names.push(row.id);
  return json({ names });
}

const OWNED = [
  ['clips', 'author_id'],
  ['reactions', 'author_id'],
  ['comments', 'author_id'],
  ['pokes', 'author_id'],
  ['members', 'user_id'],
];

/**
 * Deletes by name and answers with the names now confirmed gone: mine that
 * were deleted, plus names nobody has. Someone else's record is neither
 * deleted nor confirmed — the caller's journal keeps it as not done.
 */
async function deleteRecords(request, env, { me }) {
  const b = await readJson(request);
  if (!Array.isArray(b.names) || b.names.length > 2000) throw bad();
  const names = [...new Set(b.names.map(recordName))];
  const media = [];
  for (const part of chunks(names, 40)) {
    const pick = marks(part.length, 2);
    const keys = await env.DB.batch([
      env.DB.prepare(`SELECT video_key AS k FROM clips WHERE author_id = ?1 AND id IN (${pick})`).bind(me, ...part),
      env.DB.prepare(`SELECT avatar_key AS k FROM members WHERE user_id = ?1 AND id IN (${pick}) AND avatar_key IS NOT NULL`).bind(me, ...part),
    ]);
    for (const r of keys) for (const row of r.results ?? []) media.push(row.k);
    await env.DB.batch(
      OWNED.map(([table, owner]) =>
        env.DB.prepare(`DELETE FROM ${table} WHERE ${owner} = ?1 AND id IN (${pick})`).bind(me, ...part)
      )
    );
  }
  const remaining = new Set();
  for (const part of chunks(names, 40)) {
    const pick = marks(part.length);
    const found = await env.DB.batch(
      OWNED.map(([table]) => env.DB.prepare(`SELECT id FROM ${table} WHERE id IN (${pick})`).bind(...part))
    );
    for (const r of found) for (const row of r.results ?? []) remaining.add(row.id);
  }
  await deleteMediaIfUnused(env, media);
  return json({ confirmed: names.filter((n) => !remaining.has(n)) });
}

/** A video or avatar goes once no row points at it any more. */
export async function deleteMediaIfUnused(env, keys) {
  const unique = [...new Set(keys.filter(Boolean))];
  if (!unique.length || !env.MEDIA) return;
  const used = new Set();
  for (const part of chunks(unique, 40)) {
    const pick = marks(part.length);
    const found = await env.DB.batch([
      env.DB.prepare(`SELECT video_key AS k FROM clips WHERE video_key IN (${pick})`).bind(...part),
      env.DB.prepare(`SELECT avatar_key AS k FROM members WHERE avatar_key IN (${pick})`).bind(...part),
    ]);
    for (const r of found) for (const row of r.results ?? []) used.add(row.k);
  }
  const gone = unique.filter((k) => !used.has(k));
  if (gone.length) await env.MEDIA.delete(gone);
}

// MARK: - Routing

/**
 * @returns a Response, or null when the path isn't one of these.
 * `who` is `{ userId, me }` from the session token.
 */
export async function roomRoutes(request, env, ctx, who, segments) {
  const method = request.method;
  const [head, a, b, c] = segments;
  const one = (value) => decodeURIComponent(value);

  if (head === 'rooms') {
    if (!a && method === 'POST') return createRoom(request, env, who);
    if (!a) return null;
    const code = roomCode(one(a));
    if (!b) {
      if (method === 'GET') return getRoom(env, code);
      if (method === 'PATCH') return patchRoom(request, env, who, code);
      return null;
    }
    if (b === 'members' && !c && method === 'GET') return listMembers(env, code);
    if (b === 'members' && c === 'me' && method === 'PUT') return putMember(request, env, who, code);
    if (b === 'clips' && !c && method === 'GET') return listClips(env, code);
    if (b === 'interactions' && !c && method === 'GET') return interactions(env, code);
    if (b === 'comments' && !c && method === 'GET') return json({ comments: await listComments(env, code) });
    if (b === 'comments' && c === 'missing' && method === 'POST') return missingComments(request, env, code);
    if (b === 'mine' && !c && method === 'GET') return myRecordNames(env, who, code);
    return null;
  }
  if (head === 'me' && a === 'rooms' && !b && method === 'GET') return myRooms(env, who);
  if (head === 'records' && a === 'delete' && !b && method === 'POST') return deleteRecords(request, env, who);
  if (!a || b) return null;
  const id = recordName(one(a));
  if (head === 'clips') {
    if (method === 'PUT') return putClip(request, env, ctx, who, id);
    if (method === 'PATCH') return patchClip(request, env, who, id);
  }
  if (head === 'reactions') {
    if (method === 'PUT') return putReaction(request, env, ctx, who, id);
    if (method === 'DELETE') return deleteOwn(env, 'reactions', id, who.me);
  }
  if (head === 'comments') {
    if (method === 'PUT') return putComment(request, env, ctx, who, id);
    if (method === 'DELETE') return deleteOwn(env, 'comments', id, who.me);
  }
  if (head === 'pokes' && method === 'PUT') return putPoke(request, env, ctx, who, id);
  return null;
}

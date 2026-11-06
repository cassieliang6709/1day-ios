/**
 * 心情日记 backup: one row per person per day, readable only by its owner —
 * what CloudKit's private database held. The newest `updatedAt` wins, on the
 * server as on the phone (`MoodStore.merge`).
 *
 * `seq` grows with every write, so a phone reads "everything after the last
 * seq I saw", the way it used to read CloudKit zone changes.
 */
import { bad, json, readJson, str, time } from './http.js';

const PAGE = 500;

async function fetchMoods(request, env, { me }) {
  const after = Number(new URL(request.url).searchParams.get('after') ?? 0);
  if (!Number.isInteger(after) || after < 0) throw bad();
  const { results } = await env.DB.prepare(
    'SELECT day, mood, note, updated_at, seq FROM moods WHERE user_id = ?1 AND seq > ?2 ORDER BY seq LIMIT ?3'
  )
    .bind(me, after, PAGE + 1)
    .all();
  const rows = results ?? [];
  const page = rows.slice(0, PAGE);
  return json({
    entries: page.map((r) => ({ day: r.day, mood: r.mood, note: r.note, updatedAt: r.updated_at })),
    cursor: page.length ? page[page.length - 1].seq : after,
    more: rows.length > PAGE,
  });
}

async function putMoods(request, env, { me }) {
  const b = await readJson(request);
  if (!Array.isArray(b.entries) || b.entries.length > PAGE) throw bad();
  const entries = b.entries.map((e) => {
    const day = str(e?.day, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw bad();
    return { day, mood: str(e.mood, 32), note: str(e.note ?? '', 4000), updatedAt: time(e.updatedAt) };
  });
  // One statement per entry, in order, so each takes the next seq.
  await env.DB.batch(
    entries.map((e) =>
      env.DB.prepare(
        `INSERT INTO moods (user_id, day, mood, note, updated_at, seq)
         VALUES (?1, ?2, ?3, ?4, ?5, (SELECT COALESCE(MAX(seq), 0) + 1 FROM moods WHERE user_id = ?1))
         ON CONFLICT (user_id, day) DO UPDATE SET
           mood = excluded.mood, note = excluded.note,
           updated_at = excluded.updated_at, seq = excluded.seq
         WHERE excluded.updated_at >= moods.updated_at`
      ).bind(me, e.day, e.mood, e.note, e.updatedAt)
    )
  );
  return json({ ok: true });
}

/** Account deletion: the diary and every registered phone. Rooms are
 * deleted by name through `/records/delete`, under the app's journal. */
async function deletePrivate(env, { me }) {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM moods WHERE user_id = ?1').bind(me),
    env.DB.prepare('DELETE FROM device_rooms WHERE token IN (SELECT token FROM devices WHERE user_id = ?1)').bind(me),
    env.DB.prepare('DELETE FROM devices WHERE user_id = ?1').bind(me),
  ]);
  return json({ ok: true });
}

export async function moodRoutes(request, env, who, segments) {
  if (segments[0] === 'moods' && segments.length === 1) {
    if (request.method === 'GET') return fetchMoods(request, env, who);
    if (request.method === 'PUT') return putMoods(request, env, who);
  }
  if (segments[0] === 'me' && segments[1] === 'private' && segments.length === 2 && request.method === 'DELETE') {
    return deletePrivate(env, who);
  }
  return null;
}


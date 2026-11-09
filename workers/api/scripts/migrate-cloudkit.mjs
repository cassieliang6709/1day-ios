#!/usr/bin/env node
/**
 * One-off: copies everything in CloudKit's public database (rooms, members,
 * clips with their videos, avatars, reactions, chat, pokes) into D1 and R2.
 * Ids, authors and times stay exactly as they were, so the app finds the
 * same rooms with the same clips under the same people.
 *
 * Not copied: the mood diary (each person's private iCloud — a server key
 * can't read it; the app uploads its local copy on first sync) and push
 * subscriptions (phones register again on their own).
 *
 * Needs a CloudKit server-to-server key (see README, "上线步骤"):
 *
 *   CK_KEY_ID=<key id> CK_KEY_FILE=eckey.pem node scripts/migrate-cloudkit.mjs
 *
 * Writes `migration-out/import.sql` and `migration-out/media/…`, touching
 * nothing remote. Add `--upload` to also run the wrangler commands that put
 * the media in R2 and the rows in D1. Safe to run again: rows are
 * INSERT OR REPLACE, keyed by their CloudKit record name.
 */
import { createHash, createSign, randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { mediaPrefix } from '../src/media.js';

const CONTAINER = process.env.CK_CONTAINER ?? 'iCloud.com.cassie.AISetlog';
const ENVIRONMENT = process.env.CK_ENV ?? 'production';
const KEY_ID = process.env.CK_KEY_ID;
const KEY = process.env.CK_KEY_FILE && readFileSync(process.env.CK_KEY_FILE, 'utf8');
const OUT = new URL('../migration-out/', import.meta.url).pathname;
const UPLOAD = process.argv.includes('--upload');

if (!KEY_ID || !KEY) {
  console.error('Set CK_KEY_ID and CK_KEY_FILE (the PEM private key for that server-to-server key).');
  process.exit(1);
}

// MARK: - CloudKit Web Services

async function ck(operation, body) {
  const subpath = `/database/1/${CONTAINER}/${ENVIRONMENT}/public/${operation}`;
  const text = JSON.stringify(body);
  const date = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
  const bodyHash = createHash('sha256').update(text).digest('base64');
  const signature = createSign('SHA256').update(`${date}:${bodyHash}:${subpath}`).sign(KEY, 'base64');
  const response = await fetch(`https://api.apple-cloudkit.com${subpath}`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'X-Apple-CloudKit-Request-KeyID': KEY_ID,
      'X-Apple-CloudKit-Request-ISO8601Date': date,
      'X-Apple-CloudKit-Request-SignatureV1': signature,
    },
    body: text,
  });
  const json = await response.json();
  if (!response.ok || json.serverErrorCode) {
    throw new Error(`${operation}: ${response.status} ${json.serverErrorCode ?? ''} ${json.reason ?? ''}`);
  }
  return json;
}

/** Every record of a type. A type nobody ever wrote answers an error, which
 * is "none". Needs `recordName` QUERYABLE on the type. */
async function all(recordType) {
  const records = [];
  let continuationMarker;
  do {
    let page;
    try {
      page = await ck('records/query', { query: { recordType }, resultsLimit: 200, continuationMarker });
    } catch (error) {
      if (/NOT_FOUND|did not find record type/i.test(error.message)) return records;
      throw error;
    }
    for (const r of page.records ?? []) if (!r.serverErrorCode) records.push(r);
    continuationMarker = page.continuationMarker;
  } while (continuationMarker);
  console.log(`${recordType}: ${records.length}`);
  return records;
}

const field = (r, name) => r.fields?.[name]?.value ?? null;

// MARK: - SQL

function sqlValue(v) {
  if (v === null || v === undefined) return 'NULL';
  if (typeof v === 'number') return Number.isFinite(v) ? String(Math.round(v)) : 'NULL';
  return `'${String(v).replace(/'/g, "''")}'`;
}

const lines = [];
function insert(table, row) {
  const cols = Object.keys(row);
  lines.push(`INSERT OR REPLACE INTO ${table} (${cols.join(', ')}) VALUES (${cols.map((c) => sqlValue(row[c])).join(', ')});`);
}

// MARK: - Media

const media = []; // [key, file, contentType]
async function copyAsset(asset, owner, extension, contentType) {
  if (!asset?.downloadURL) return null;
  const key = `${mediaPrefix(owner)}${randomUUID()}.${extension}`;
  const file = join(OUT, 'media', key);
  const url = asset.downloadURL.replace('${f}', `file.${extension}`);
  const response = await fetch(url);
  if (!response.ok) {
    console.warn(`  could not download an asset for ${owner}: ${response.status}`);
    return null;
  }
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, Buffer.from(await response.arrayBuffer()));
  media.push([key, file, contentType]);
  return key;
}

// MARK: - Copy

mkdirSync(OUT, { recursive: true });
const now = Date.now();

for (const r of await all('Room')) {
  insert('rooms', {
    code: r.recordName,
    title: field(r, 'title') ?? 'Challenge',
    start_date: field(r, 'startDate') ?? r.created?.timestamp ?? now,
    owner_id: field(r, 'ownerID') ?? '',
    owner_name: field(r, 'ownerName') ?? '',
    mode: field(r, 'mode') ?? 'sevenDay',
    clip_length: field(r, 'clipLength') ?? 'tiny',
    orientation: field(r, 'orientation') ?? 'portrait',
    camera_style: field(r, 'cameraStyle'),
    template_name: field(r, 'templateName'),
    moment_titles: field(r, 'momentTitles'),
    created_at: r.created?.timestamp ?? now,
  });
}

for (const r of await all('Member')) {
  const userId = field(r, 'userID');
  const code = field(r, 'roomCode');
  if (!userId || !code) continue;
  insert('members', {
    id: r.recordName,
    room_code: code,
    user_id: userId,
    display_name: field(r, 'displayName') ?? '',
    joined_at: field(r, 'joinedAt') ?? r.created?.timestamp ?? now,
    avatar_key: await copyAsset(field(r, 'avatar'), userId, 'png', 'image/png'),
    mood_kind: field(r, 'moodKind'),
    mood_day: field(r, 'moodDay'),
    room_title: field(r, 'roomTitle'),
    room_title_at: field(r, 'roomTitleAt'),
    updated_at: r.modified?.timestamp ?? now,
  });
}

for (const r of await all('Clip')) {
  const author = field(r, 'authorID');
  const code = field(r, 'roomCode');
  if (!author || !code) continue;
  const videoKey = await copyAsset(field(r, 'video'), author, 'mov', 'video/quicktime');
  if (!videoKey) continue; // a clip without its video shows nothing
  insert('clips', {
    id: r.recordName,
    room_code: code,
    day: field(r, 'day') ?? 0,
    author_id: author,
    author_name: field(r, 'authorName') ?? '',
    recorded_at: field(r, 'recordedAt') ?? r.created?.timestamp ?? now,
    video_key: videoKey,
    overlay_text: field(r, 'overlayText'),
    caption_sticker: field(r, 'captionSticker'),
    captions_json: field(r, 'captionsJSON'),
    updated_at: r.modified?.timestamp ?? now,
  });
}

for (const r of await all('Reaction')) {
  if (!field(r, 'emoji') || !field(r, 'roomCode')) continue;
  insert('reactions', {
    id: r.recordName,
    room_code: field(r, 'roomCode'),
    day: field(r, 'day') ?? 0,
    emoji: field(r, 'emoji'),
    author_id: field(r, 'authorID') ?? '',
    author_name: field(r, 'authorName') ?? '',
    target_author_id: field(r, 'targetAuthorID') ?? '',
    created_at: field(r, 'createdAt') ?? r.created?.timestamp ?? now,
  });
}

for (const r of await all('Comment')) {
  if (field(r, 'text') === null || !field(r, 'roomCode')) continue;
  insert('comments', {
    id: r.recordName,
    room_code: field(r, 'roomCode'),
    day: field(r, 'day'),
    text: field(r, 'text'),
    author_id: field(r, 'authorID') ?? '',
    author_name: field(r, 'authorName') ?? '',
    target_author_id: field(r, 'targetAuthorID'),
    created_at: field(r, 'createdAt') ?? r.created?.timestamp ?? now,
  });
}

for (const r of await all('Poke')) {
  if (!field(r, 'roomCode')) continue;
  insert('pokes', {
    id: r.recordName,
    room_code: field(r, 'roomCode'),
    author_id: field(r, 'authorID') ?? '',
    author_name: field(r, 'authorName') ?? '',
    target_author_id: field(r, 'targetAuthorID') ?? '',
    created_at: field(r, 'createdAt') ?? r.created?.timestamp ?? now,
  });
}

const sqlFile = join(OUT, 'import.sql');
writeFileSync(sqlFile, lines.join('\n') + '\n');
writeFileSync(join(OUT, 'media.json'), JSON.stringify(media, null, 2));
console.log(`\n${lines.length} rows → ${sqlFile}\n${media.length} files → ${join(OUT, 'media')}`);

if (!UPLOAD) {
  console.log('\nNothing uploaded. Run again with --upload to put them in R2 and D1.');
  process.exit(0);
}

// Media first: a row that points at a file not uploaded yet would show a
// clip that can't play.
for (const [key, file, type] of media) {
  if (!existsSync(file)) continue;
  execFileSync('wrangler', ['r2', 'object', 'put', `oneday-media/${key}`, '--file', file, '--content-type', type, '--remote'], { stdio: 'inherit' });
}
execFileSync('wrangler', ['d1', 'execute', 'oneday', '--remote', '--file', sqlFile], { stdio: 'inherit' });
console.log('Done.');

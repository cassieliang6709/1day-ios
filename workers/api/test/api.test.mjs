/**
 * The room API against a real schema (node:sqlite standing in for D1). Most
 * tests are about who may write what: the caller is whoever the session
 * token says, and nothing in a body can change that.
 *
 *   npm test
 */
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import worker from '../src/index.js';
import { issueSessionToken } from '../src/auth.js';
import { buildPayload, notifyRoom } from '../src/push.js';
import { reactionId } from '../src/rooms.js';
import { makeD1, makeR2 } from './support/d1.mjs';

const SECRET = 'y'.repeat(48);
const BASE = 'https://api.test';
const ALICE = 'apple:001.alice';   // app id "001.alice"
const BOB = 'google:bob';          // app id "google:bob"
const A = '001.alice';
const B = 'google:bob';

let env;
let waits;
const ctx = { waitUntil: (p) => waits.push(p) };

beforeEach(() => {
  env = {
    DB: makeD1(),
    MEDIA: makeR2(),
    SESSION_SECRET: SECRET,
    APPLE_AUDIENCES: 'com.cassie.AISetlog,com.cassie.AISetlog.dev',
  };
  waits = [];
});

async function call(user, method, path, body, headers = {}) {
  const init = { method, headers: { ...headers } };
  if (user) init.headers.authorization = `Bearer ${(await issueSessionToken(user, SECRET)).token}`;
  if (body instanceof Uint8Array) {
    init.body = body;
    init.headers['content-length'] = String(body.length);
  } else if (body !== undefined) {
    init.body = JSON.stringify(body);
    init.headers['content-type'] = 'application/json';
  }
  const response = await worker.fetch(new Request(BASE + path, init), env, ctx);
  await Promise.all(waits);
  const text = await response.text();
  let data = null;
  try { data = JSON.parse(text); } catch { data = text; }
  return { status: response.status, data };
}

const room = (code = 'ABCDEF') => ({
  code, title: '周末', ownerName: 'Alice', mode: 'sevenDay', clipLength: 'tiny', orientation: 'portrait',
});

async function uploadVideo(user) {
  const r = await call(user, 'POST', '/media', new Uint8Array([1, 2, 3]), { 'content-type': 'video/mp4' });
  assert.equal(r.status, 201);
  return r.data.key;
}

test('no token is 401; a token for nobody is 401', async () => {
  assert.equal((await call(null, 'GET', '/rooms/ABCDEF')).status, 401);
  const r = await worker.fetch(
    new Request(BASE + '/rooms/ABCDEF', { headers: { authorization: 'Bearer nope' } }), env, ctx);
  assert.equal(r.status, 401);
});

test('create a room, fetch it by code, the code can only be taken once', async () => {
  const made = await call(ALICE, 'POST', '/rooms', room());
  assert.equal(made.status, 201);
  assert.equal(made.data.ownerID, A, 'owner is the caller, Apple prefix dropped');
  assert.equal((await call(BOB, 'POST', '/rooms', room())).status, 409);
  const got = await call(BOB, 'GET', '/rooms/ABCDEF');
  assert.equal(got.status, 200);
  assert.equal(got.data.title, '周末');
  assert.equal((await call(BOB, 'GET', '/rooms/ZZZZZZ')).status, 404);
});

test('only the owner can rename the owner', async () => {
  await call(ALICE, 'POST', '/rooms', room());
  assert.equal((await call(BOB, 'PATCH', '/rooms/ABCDEF', { ownerName: 'x' })).status, 403);
  assert.equal((await call(ALICE, 'PATCH', '/rooms/ABCDEF', { ownerName: '已删除' })).status, 200);
  assert.equal((await call(BOB, 'GET', '/rooms/ABCDEF')).data.ownerName, '已删除');
});

test('member writes merge: a later write never undoes an earlier field', async () => {
  await call(ALICE, 'POST', '/rooms', room());
  await call(BOB, 'PUT', '/rooms/ABCDEF/members/me', { displayName: 'Bob', joinedAt: 1000 });
  const avatar = (await call(BOB, 'POST', '/media', new Uint8Array([9]), { 'content-type': 'image/png' })).data.key;
  await call(BOB, 'PUT', '/rooms/ABCDEF/members/me', { avatarKey: avatar, moodKind: 'happy', moodDay: 2000 });
  await call(BOB, 'PUT', '/rooms/ABCDEF/members/me', { displayName: '', roomTitle: '新名字', roomTitleAt: 3000 });
  const { data } = await call(ALICE, 'GET', '/rooms/ABCDEF/members');
  assert.equal(data.members.length, 1);
  const bob = data.members[0];
  assert.equal(bob.userID, B);
  assert.equal(bob.displayName, 'Bob', 'empty name keeps the old one');
  assert.equal(bob.joinedAt, 1000);
  assert.equal(bob.avatarKey, avatar);
  assert.equal(bob.moodKind, 'happy');
  assert.equal(bob.roomTitle, '新名字');
});

test('a member can only point at their own uploads', async () => {
  const alices = await uploadVideo(ALICE);
  const r = await call(BOB, 'PUT', '/rooms/ABCDEF/members/me', { avatarKey: alices });
  assert.equal(r.status, 400);
});

test('my rooms: member codes, owned rooms, newest name', async () => {
  await call(ALICE, 'POST', '/rooms', room('AAAAAA'));
  await call(ALICE, 'PUT', '/rooms/BBBBBB/members/me', { displayName: 'Ally', joinedAt: 1 });
  const { data } = await call(ALICE, 'GET', '/me/rooms');
  assert.deepEqual(data.memberCodes, ['BBBBBB']);
  assert.deepEqual(data.owned.map((r) => r.code), ['AAAAAA']);
  assert.equal(data.displayName, 'Ally');
});

test('clips: upload, list, re-upload replaces the video, caption-only patch', async () => {
  const key1 = await uploadVideo(ALICE);
  const id = `ABCDEF_${A}_day1`;
  const clip = { roomCode: 'ABCDEF', day: 1, authorName: 'Alice', recordedAt: 5000, videoKey: key1, overlayText: 'hi' };
  assert.equal((await call(ALICE, 'PUT', `/clips/${encodeURIComponent(id)}`, clip)).status, 200);
  const key2 = await uploadVideo(ALICE);
  await call(ALICE, 'PUT', `/clips/${encodeURIComponent(id)}`, { ...clip, videoKey: key2 });
  assert.equal(env.MEDIA.objects.has(key1), false, 'the replaced video is gone from R2');
  assert.equal((await call(ALICE, 'PATCH', `/clips/${encodeURIComponent(id)}`, { overlayText: 'yo', captionsJSON: '[]' })).status, 200);
  const { data } = await call(BOB, 'GET', '/rooms/ABCDEF/clips');
  assert.equal(data.clips.length, 1);
  assert.equal(data.clips[0].videoKey, key2);
  assert.equal(data.clips[0].overlayText, 'yo');
  assert.equal(data.clips[0].authorID, A);
  const video = await worker.fetch(new Request(BASE + '/media/' + key2, {
    headers: { authorization: `Bearer ${(await issueSessionToken(BOB, SECRET)).token}` } }), env, ctx);
  assert.equal(video.status, 200);
  assert.deepEqual([...new Uint8Array(await video.arrayBuffer())], [1, 2, 3]);
});

test('a clip id has to carry the caller: Bob cannot write as Alice', async () => {
  const key = await uploadVideo(BOB);
  const id = `ABCDEF_${A}_day1`;
  const r = await call(BOB, 'PUT', `/clips/${encodeURIComponent(id)}`,
    { roomCode: 'ABCDEF', day: 1, authorName: 'x', recordedAt: 1, videoKey: key });
  assert.equal(r.status, 403);
  const take = `ABCDEF_${B}_day1_6F9619FF-8B86-D011-B42D-00C04FC964FF`;
  assert.equal((await call(BOB, 'PUT', `/clips/${encodeURIComponent(take)}`,
    { roomCode: 'ABCDEF', day: 1, authorName: 'Bob', recordedAt: 1, videoKey: key })).status, 200);
  assert.equal((await call(BOB, 'PUT', `/clips/${encodeURIComponent(take + 'x')}`,
    { roomCode: 'ABCDEF', day: 1, authorName: 'Bob', recordedAt: 1, videoKey: key })).status, 403);
});

test('reactions: id must match the fields; on/off is idempotent', async () => {
  const id = reactionId('ABCDEF', A, B, 1, '❤️');
  assert.equal(id, `ABCDEF_${A}_day1_${B}_10084-65039`, 'same scalars as Swift');
  const body = { roomCode: 'ABCDEF', day: 1, emoji: '❤️', authorName: 'Bob', targetAuthorID: A };
  assert.equal((await call(BOB, 'PUT', `/reactions/${encodeURIComponent(id)}`, body)).status, 200);
  assert.equal((await call(BOB, 'PUT', `/reactions/${encodeURIComponent(id)}`, body)).status, 200);
  assert.equal((await call(ALICE, 'PUT', `/reactions/${encodeURIComponent(id)}`, body)).status, 403);
  assert.equal((await call(ALICE, 'DELETE', `/reactions/${encodeURIComponent(id)}`)).status, 403);
  assert.equal((await call(BOB, 'GET', '/rooms/ABCDEF/interactions')).data.reactions.length, 1);
  assert.equal((await call(BOB, 'DELETE', `/reactions/${encodeURIComponent(id)}`)).status, 200);
  assert.equal((await call(BOB, 'DELETE', `/reactions/${encodeURIComponent(id)}`)).status, 200);
  assert.equal((await call(BOB, 'GET', '/rooms/ABCDEF/interactions')).data.reactions.length, 0);
});

test('chat: send twice is one message, only the author deletes, missing ids', async () => {
  const id = '11111111-2222-3333-4444-555555555555';
  const other = '99999999-2222-3333-4444-555555555555';
  const msg = { roomCode: 'ABCDEF', text: '在吗', authorName: 'Alice', createdAt: 7 };
  await call(ALICE, 'PUT', `/comments/${id}`, msg);
  await call(ALICE, 'PUT', `/comments/${id}`, msg);
  assert.equal((await call(BOB, 'PUT', `/comments/${id}`, { ...msg, text: 'hacked' })).status, 403);
  const list = (await call(BOB, 'GET', '/rooms/ABCDEF/comments')).data.comments;
  assert.equal(list.length, 1);
  assert.equal(list[0].text, '在吗');
  assert.equal(list[0].day, null);
  const missing = await call(BOB, 'POST', '/rooms/ABCDEF/comments/missing', { ids: [id, other] });
  assert.deepEqual(missing.data.missing, [other]);
  assert.equal((await call(BOB, 'DELETE', `/comments/${id}`)).status, 403);
  assert.equal((await call(ALICE, 'DELETE', `/comments/${id}`)).status, 200);
  assert.equal((await call(BOB, 'GET', '/rooms/ABCDEF/comments')).data.comments.length, 0);
});

test('delete by name: mine go, absent count as gone, someone else\'s stay unconfirmed', async () => {
  await call(ALICE, 'POST', '/rooms', room());
  await call(ALICE, 'PUT', '/rooms/ABCDEF/members/me', { displayName: 'Alice', joinedAt: 1 });
  await call(BOB, 'PUT', '/rooms/ABCDEF/members/me', { displayName: 'Bob', joinedAt: 1 });
  const key = await uploadVideo(ALICE);
  const clipId = `ABCDEF_${A}_day1`;
  await call(ALICE, 'PUT', `/clips/${encodeURIComponent(clipId)}`,
    { roomCode: 'ABCDEF', day: 1, authorName: 'Alice', recordedAt: 1, videoKey: key });
  const mine = (await call(ALICE, 'GET', '/rooms/ABCDEF/mine')).data.names.sort();
  assert.deepEqual(mine, [`ABCDEF_${A}`, clipId].sort());
  const r = await call(ALICE, 'POST', '/records/delete', { names: [...mine, 'never-existed', `ABCDEF_${B}`] });
  assert.deepEqual(r.data.confirmed.sort(), [...mine, 'never-existed'].sort());
  assert.equal(env.MEDIA.objects.has(key), false);
  assert.equal((await call(BOB, 'GET', '/rooms/ABCDEF/members')).data.members.length, 1);
});

test('moods: private, newest wins, read after a cursor', async () => {
  await call(ALICE, 'PUT', '/moods', { entries: [{ day: '2026-11-01', mood: 'happy', note: 'a', updatedAt: 10 }] });
  await call(ALICE, 'PUT', '/moods', { entries: [{ day: '2026-11-01', mood: 'sad', note: 'old', updatedAt: 5 }] });
  const first = (await call(ALICE, 'GET', '/moods')).data;
  assert.equal(first.entries.length, 1);
  assert.equal(first.entries[0].mood, 'happy', 'an older write does not win');
  assert.equal((await call(BOB, 'GET', '/moods')).data.entries.length, 0, 'Bob sees none of it');
  await call(ALICE, 'PUT', '/moods', { entries: [{ day: '2026-11-02', mood: 'calm', note: '', updatedAt: 20 }] });
  const next = (await call(ALICE, 'GET', `/moods?after=${first.cursor}`)).data;
  assert.deepEqual(next.entries.map((e) => e.day), ['2026-11-02']);
  await call(ALICE, 'DELETE', '/me/private');
  assert.equal((await call(ALICE, 'GET', '/moods')).data.entries.length, 0);
});

test('push: others in the room hear it, the author does not, a poke reaches only its target', async () => {
  const alerts = {
    clip: { format: '%1$@ 刚拍了一段', args: ['authorName'] },
    comment: { format: '%1$@：%2$@', args: ['authorName', 'text'] },
    poke: { format: '%1$@ 拍了拍你', args: ['authorName'] },
  };
  const device = (token) => ({ token, topic: 'com.cassie.AISetlog', sandbox: false, alerts, rooms: [{ code: 'ABCDEF', title: '周末' }] });
  assert.equal((await call(ALICE, 'PUT', '/push/device', device('aa'.repeat(32)))).status, 200);
  assert.equal((await call(BOB, 'PUT', '/push/device', device('bb'.repeat(32)))).status, 200);
  assert.equal((await call(BOB, 'PUT', '/push/device', { ...device('cc'.repeat(32)), topic: 'com.evil' })).status, 400);

  const sent = [];
  const send = async (_env, d, payload) => { sent.push([d.user_id, payload]); return { status: 200, reason: '' }; };
  await notifyRoom(env, { kind: 'clip', code: 'ABCDEF', authorID: A, authorName: 'Alice', day: 2, recordName: 'x' }, { send });
  assert.deepEqual(sent.map((s) => s[0]), [B]);
  assert.deepEqual(sent[0][1].aps.alert, { title: '周末', 'loc-key': '%1$@ 刚拍了一段', 'loc-args': ['Alice'] });
  assert.equal(sent[0][1].oneday.roomCode, 'ABCDEF');

  sent.length = 0;
  await notifyRoom(env, { kind: 'poke', code: 'ABCDEF', authorID: B, authorName: 'Bob', targetAuthorID: 'someone-else', recordName: 'p' }, { send });
  assert.equal(sent.length, 0);

  // A dead token is dropped.
  const dead = async () => ({ status: 410, reason: 'Unregistered' });
  await notifyRoom(env, { kind: 'clip', code: 'ABCDEF', authorID: A, authorName: 'Alice', recordName: 'x' }, { send: dead });
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM devices').first()).n, 1);

  // Turning notifications off is an empty room list.
  await call(ALICE, 'PUT', '/push/device', { ...device('aa'.repeat(32)), rooms: [] });
  assert.equal((await env.DB.prepare('SELECT COUNT(*) AS n FROM devices').first()).n, 0);
});

test('push payload carries the message text, cut short', () => {
  const p = buildPayload({ kind: 'comment', code: 'ABCDEF', authorName: 'A', text: 'x'.repeat(900), day: 0 },
    { format: '%1$@: %2$@', args: ['authorName', 'text'] }, 'T');
  assert.equal(p.aps.alert['loc-args'][1].length, 500);
  assert.equal(p.oneday.day, 1);
});

test('refresh gives a new token for the same user', async () => {
  const r = await call(ALICE, 'POST', '/auth/refresh');
  assert.equal(r.status, 200);
  assert.equal(r.data.userId, ALICE);
  assert.equal((await call(null, 'POST', '/auth/refresh')).status, 401);
});

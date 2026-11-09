# api

1Day's own backend, replacing CloudKit: sign-in, rooms, members, clips,
reactions, room chat, pokes and the mood diary live in D1; videos and avatars
in R2; room alerts go straight to APNs.

Lives at `https://auth.liangyue.site`. Only the sign-in part is deployed so
far — see 上线步骤 below.

## 上线步骤（按顺序跑，每步都能单独重来）

1. 建数据库，把打印出来的 `database_id` 填进 `wrangler.toml`：
   ```bash
   wrangler d1 create oneday
   ```
2. 建表：
   ```bash
   wrangler d1 migrations apply oneday --remote
   ```
3. 建视频桶：
   ```bash
   wrangler r2 bucket create oneday-media
   ```
4. 推送用的 APNs key：developer.apple.com → Keys → 新建，勾 Apple Push
   Notifications service，下载 `.p8`。key id 填进 `wrangler.toml` 的
   `APNS_KEY_ID`，文件内容存成 secret：
   ```bash
   wrangler secret put APNS_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8
   ```
5. 部署：
   ```bash
   wrangler deploy
   ```
6. 搬老数据（CloudKit 公共库 → D1 + R2）。先在 CloudKit Console →
   Tokens & Keys 建一个 server-to-server key（按页面提示用 openssl 生成
   `eckey.pem`，把公钥贴进去），并在 Schema → Indexes 给 Room、Member、
   Clip、Reaction、Comment、Poke 的 `recordName` 各加一个 QUERYABLE 索引、
   Deploy to Production。然后：
   ```bash
   CK_KEY_ID=<key id> CK_KEY_FILE=eckey.pem node scripts/migrate-cloudkit.mjs
   ```
   先看一眼 `migration-out/` 里的行数和文件数，再加 `--upload` 真正写进去。
   心情日记不在这里：它在每个人自己的 iCloud 私有库，新版 App 第一次同步时
   会把手机上的全部条目传一次。

## Everything else

Each needs `Authorization: Bearer <token>`. Times are milliseconds since 1970.
The caller is the author of whatever they write; a body never names its own
author, and an id with an author in it must have the caller's.

| Route | What |
| --- | --- |
| `POST /auth/refresh` | a new token for the same user |
| `POST /rooms` | create; the app picks the code, `409` means taken |
| `GET /rooms/:code`, `PATCH /rooms/:code` | read; owner renames the owner |
| `GET /me/rooms` | rooms I'm a member of or own |
| `GET /rooms/:code/members`, `PUT /rooms/:code/members/me` | members; my row, merged field by field |
| `GET /rooms/:code/clips`, `PUT /clips/:id`, `PATCH /clips/:id` | clips; caption-only patch |
| `POST /media`, `GET /media/:key` | raw file up (→ `{key}`), down |
| `PUT /reactions/:id`, `DELETE /reactions/:id` | emoji on/off |
| `GET /rooms/:code/interactions` | reactions + comments |
| `GET /rooms/:code/comments`, `PUT /comments/:id`, `DELETE /comments/:id` | room chat |
| `POST /rooms/:code/comments/missing` | which of these ids the server has never heard of |
| `PUT /pokes/:id` | 拍一拍 |
| `GET /rooms/:code/mine`, `POST /records/delete` | leave a room / delete an account by record name |
| `GET /moods?after=`, `PUT /moods`, `DELETE /me/private` | the mood diary |
| `PUT /push/device`, `DELETE /push/device` | which rooms this phone wants alerts for |

## Sign-in

`POST /auth/apple` or `POST /auth/google`

```json
{ "identityToken": "<the token Apple or Google gave the app>" }
```

```json
{ "token": "<1Day session token>", "userId": "apple:001234.abcd…", "expiresAt": 1790000000 }
```

| Status | Meaning |
| --- | --- |
| `200` | Signed in. Send `token` as the bearer token on everything else. |
| `400` | No token in the body, or not JSON. |
| `401` | The token is not genuine, not for 1Day, or expired. Sign in again. |
| `502` | Apple's or Google's key set couldn't be fetched. Retry. |
| `503` | The Worker isn't configured (no session secret or no audiences). |

The user id comes out of the verified token, never from the request, so
nobody can claim to be someone else. A person who signs in with Apple and
later with Google is two users; linking them is not built.

## What it checks

An identity token is accepted only if all of these hold:

- signed with RS256 by a key in the provider's published key set (anything
  else in `alg`, including `none` and `HS256`, is refused before any key is
  looked at)
- `iss` is Apple's or Google's
- `aud` is one of ours: the bundle IDs in `APPLE_AUDIENCES`, the OAuth client
  IDs in `GOOGLE_AUDIENCES`
- `exp` hasn't passed (60s clock skew allowed)
- `sub` is present

The session token is an HS256 JWT signed with `SESSION_SECRET`, valid 90 days.
The app swaps it for a fresh one in its last 14 days (`/auth/refresh`).

## Setup

```bash
wrangler secret put SESSION_SECRET   # 32+ random characters: openssl rand -base64 48
```

The app uses `auth.liangyue.site` only. `*.workers.dev` is blocked in mainland
China, and on 2026-11-06 this account's workers.dev URLs answered `1101` for
every Worker, `suggest-prompts` included.

## Working on it

```bash
npm test       # no network; node:sqlite stands in for D1
npm run dev    # wrangler dev, needs .dev.vars (copy .dev.vars.example)
```

Locally, Apple's key URL answers `403` to the Workers runtime (curl and Node
from the same machine get `200`), so `/auth/apple` returns `502` under
`wrangler dev`. Google's works. Deployed, both work: a token with Apple's real
key id and a bad signature comes back `401`, which needs Apple's key set to
have been fetched.

Pushes only go out from the deployed Worker: `wrangler dev` has no HTTP/2,
and APNs needs it.

Tokens are never logged; a rejection logs the provider and the reason.

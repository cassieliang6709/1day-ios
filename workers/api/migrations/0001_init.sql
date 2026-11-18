
CREATE TABLE rooms (
  code          TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  start_date    INTEGER NOT NULL,
  owner_id      TEXT NOT NULL,
  owner_name    TEXT NOT NULL,
  mode          TEXT NOT NULL,
  clip_length   TEXT NOT NULL,
  orientation   TEXT NOT NULL,
  camera_style  TEXT,
  template_name TEXT,
  moment_titles TEXT,
  created_at    INTEGER NOT NULL
);
CREATE INDEX rooms_owner ON rooms (owner_id);

CREATE TABLE members (
  id             TEXT PRIMARY KEY,
  room_code      TEXT NOT NULL,
  user_id        TEXT NOT NULL,
  display_name   TEXT NOT NULL DEFAULT '',
  joined_at      INTEGER NOT NULL,
  avatar_key     TEXT,
  mood_kind      TEXT,
  mood_day       INTEGER,
  room_title     TEXT,
  room_title_at  INTEGER,
  updated_at     INTEGER NOT NULL
);
CREATE INDEX members_room ON members (room_code);
CREATE INDEX members_user ON members (user_id);

CREATE TABLE clips (
  id              TEXT PRIMARY KEY,
  room_code       TEXT NOT NULL,
  day             INTEGER NOT NULL,
  author_id       TEXT NOT NULL,
  author_name     TEXT NOT NULL,
  recorded_at     INTEGER NOT NULL,
  video_key       TEXT NOT NULL,
  overlay_text    TEXT,
  caption_sticker TEXT,
  captions_json   TEXT,
  updated_at      INTEGER NOT NULL
);
CREATE INDEX clips_room ON clips (room_code, day);
CREATE INDEX clips_author ON clips (author_id);

CREATE TABLE reactions (
  id               TEXT PRIMARY KEY,
  room_code        TEXT NOT NULL,
  day              INTEGER NOT NULL,
  emoji            TEXT NOT NULL,
  author_id        TEXT NOT NULL,
  author_name      TEXT NOT NULL,
  target_author_id TEXT NOT NULL,
  created_at       INTEGER NOT NULL
);
CREATE INDEX reactions_room ON reactions (room_code);
CREATE INDEX reactions_author ON reactions (author_id);

CREATE TABLE comments (
  id               TEXT PRIMARY KEY,
  room_code        TEXT NOT NULL,
  day              INTEGER,
  text             TEXT NOT NULL,
  author_id        TEXT NOT NULL,
  author_name      TEXT NOT NULL,
  target_author_id TEXT,
  created_at       INTEGER NOT NULL
);
CREATE INDEX comments_room ON comments (room_code, created_at);
CREATE INDEX comments_author ON comments (author_id);

CREATE TABLE pokes (
  id               TEXT PRIMARY KEY,
  room_code        TEXT NOT NULL,
  author_id        TEXT NOT NULL,
  author_name      TEXT NOT NULL,
  target_author_id TEXT NOT NULL,
  created_at       INTEGER NOT NULL
);
CREATE INDEX pokes_author ON pokes (author_id);

CREATE TABLE moods (
  user_id    TEXT NOT NULL,
  day        TEXT NOT NULL,
  mood       TEXT NOT NULL,
  note       TEXT NOT NULL DEFAULT '',
  updated_at INTEGER NOT NULL,
  seq        INTEGER NOT NULL,
  PRIMARY KEY (user_id, day)
);
CREATE INDEX moods_seq ON moods (user_id, seq);

CREATE TABLE devices (
  token      TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL,
  topic      TEXT NOT NULL,
  sandbox    INTEGER NOT NULL DEFAULT 0,
  alerts     TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX devices_user ON devices (user_id);

CREATE TABLE device_rooms (
  token     TEXT NOT NULL,
  room_code TEXT NOT NULL,
  title     TEXT NOT NULL,
  PRIMARY KEY (token, room_code)
);
CREATE INDEX device_rooms_room ON device_rooms (room_code);

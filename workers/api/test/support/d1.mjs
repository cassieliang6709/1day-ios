/**
 * Just enough of D1 and R2 for tests, on Node's built-in sqlite: the real
 * migration runs, so the SQL under test is the SQL that ships.
 */
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const MIGRATIONS = new URL('../../migrations/', import.meta.url).pathname;

class Statement {
  constructor(db, sql, params = []) {
    this.db = db;
    this.sql = sql;
    this.params = params;
  }
  bind(...params) {
    return new Statement(this.db, this.sql, params);
  }
  #named() {
    // D1 takes `?1`-style positions; node:sqlite wants them as an object.
    if (!/\?\d/.test(this.sql)) return [this.params];
    const named = {};
    this.params.forEach((value, i) => {
      named[String(i + 1)] = value === undefined ? null : value;
    });
    return [named];
  }
  #prepared() {
    const sql = this.sql.replace(/\?(\d+)/g, ':$1');
    return this.db.prepare(sql);
  }
  async first() {
    const [args] = this.#named();
    const row = Array.isArray(args) ? this.#prepared().get(...args) : this.#prepared().get(args);
    return row ? { ...row } : null;
  }
  async all() {
    const [args] = this.#named();
    const rows = Array.isArray(args) ? this.#prepared().all(...args) : this.#prepared().all(args);
    return { results: rows.map((r) => ({ ...r })), success: true };
  }
  async run() {
    const [args] = this.#named();
    const info = Array.isArray(args) ? this.#prepared().run(...args) : this.#prepared().run(args);
    return { success: true, meta: { changes: Number(info.changes) } };
  }
  async exec() {
    return /^\s*(SELECT|WITH)/i.test(this.sql) ? this.all() : this.run();
  }
}

export function makeD1() {
  const db = new DatabaseSync(':memory:');
  for (const file of readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort()) {
    db.exec(readFileSync(join(MIGRATIONS, file), 'utf8'));
  }
  return {
    raw: db,
    prepare: (sql) => new Statement(db, sql),
    async batch(statements) {
      db.exec('BEGIN');
      try {
        const out = [];
        for (const s of statements) out.push(await s.exec());
        db.exec('COMMIT');
        return out;
      } catch (error) {
        db.exec('ROLLBACK');
        throw error;
      }
    },
  };
}

export function makeR2() {
  const objects = new Map();
  return {
    objects,
    async put(key, body, options = {}) {
      const bytes = body ? new Uint8Array(await new Response(body).arrayBuffer()) : new Uint8Array();
      objects.set(key, { bytes, httpMetadata: options.httpMetadata ?? {} });
    },
    async get(key) {
      const o = objects.get(key);
      if (!o) return null;
      return { body: new Blob([o.bytes]).stream(), size: o.bytes.length, httpMetadata: o.httpMetadata, httpEtag: '"e"' };
    },
    async delete(keys) {
      for (const k of [].concat(keys)) objects.delete(k);
    },
  };
}

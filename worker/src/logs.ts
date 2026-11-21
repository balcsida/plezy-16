import { DurableObject } from "cloudflare:workers";
import { NO_STORE, text } from "./shared.ts";

// The log upload of upstream's server/main.go, with its limits and its answers,
// so the app talks to this Worker as it talks to that server.
export const MAX_BYTES = 1024 * 1024;
const MAX_AGE = 3 * 24 * 60 * 60 * 1000;
const MAX_LOGS = 500;
const MAX_LOGS_PER_SOURCE = 10;
const UPLOAD_INTERVAL = 60 * 1000;
const LOOKUP_BURST = 10; // then one a second
// Crockford base32: no i, l, o or u, so an ID read off a TV has one spelling.
const ID_CHARS = "0123456789abcdefghjkmnpqrstvwxyz";
const ID_LENGTH = 6;
const ID_PATTERN = new RegExp(`^[${ID_CHARS}]{${ID_LENGTH}}$`);

export class Logs extends DurableObject {
	constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
		super(ctx, env);
		ctx.storage.sql.exec(`
			CREATE TABLE IF NOT EXISTS logs (
				id TEXT PRIMARY KEY, source TEXT NOT NULL, created INTEGER NOT NULL, body BLOB NOT NULL);
			CREATE TABLE IF NOT EXISTS lookups (source TEXT PRIMARY KEY, tokens REAL NOT NULL, at INTEGER NOT NULL);
		`);
	}

	put(source: string, body: ArrayBuffer): Response {
		const sql = this.ctx.storage.sql;
		const now = Date.now();
		sql.exec("DELETE FROM logs WHERE created <= ?", now - MAX_AGE);
		const mine = sql
			.exec("SELECT COUNT(*) AS held, MAX(created) AS last FROM logs WHERE source = ?", source)
			.one();
		if (mine.last !== null && now - Number(mine.last) < UPLOAD_INTERVAL) {
			return text("Rate limited: 1 upload per minute", 429);
		}
		if (Number(mine.held) >= MAX_LOGS_PER_SOURCE)
			return text("Too many stored logs from this address", 429);
		if (Number(sql.exec("SELECT COUNT(*) AS held FROM logs").one().held) >= MAX_LOGS) {
			return text("Log store full", 503);
		}
		let id = newId();
		while (sql.exec("SELECT 1 FROM logs WHERE id = ?", id).toArray().length > 0) id = newId();
		sql.exec("INSERT INTO logs VALUES (?, ?, ?, ?)", id, source, now, body);
		return Response.json({ id }, { headers: NO_STORE });
	}

	get(source: string, typed: string): Response {
		const sql = this.ctx.storage.sql;
		const now = Date.now();
		// Every lookup is charged, a hit too, before the ID is looked at: the ID is
		// all that protects a log, and this budget is all that slows guessing.
		sql.exec("DELETE FROM lookups WHERE at <= ?", now - LOOKUP_BURST * 1000);
		const spent = sql.exec("SELECT tokens, at FROM lookups WHERE source = ?", source).toArray()[0];
		const tokens = spent
			? Math.min(LOOKUP_BURST, Number(spent.tokens) + (now - Number(spent.at)) / 1000)
			: LOOKUP_BURST;
		if (tokens < 1) return text("Too many lookups", 429);
		sql.exec("INSERT OR REPLACE INTO lookups VALUES (?, ?, ?)", source, tokens - 1, now);

		const id = canonicalId(typed);
		const log =
			id &&
			sql
				.exec("SELECT body FROM logs WHERE id = ? AND created > ?", id, now - MAX_AGE)
				.toArray()[0];
		if (!log) return text("Not found", 404);
		return new Response(log.body as ArrayBuffer, {
			headers: {
				...NO_STORE,
				"Content-Type": "text/plain; charset=utf-8",
				"X-Content-Type-Options": "nosniff",
			},
		});
	}
}

function newId(): string {
	return Array.from(
		crypto.getRandomValues(new Uint8Array(ID_LENGTH)),
		(byte) => ID_CHARS[byte & 31],
	).join("");
}

// An ID as typed, in its stored spelling: any case, with i and l read as 1 and o as 0.
function canonicalId(typed: string): string | null {
	const id = typed.toLowerCase().replace(/[il]/g, "1").replaceAll("o", "0");
	return ID_PATTERN.test(id) ? id : null;
}

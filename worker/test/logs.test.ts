import { SELF } from "cloudflare:test";
import { afterEach, expect, it, vi } from "vite-plus/test";

const upload = (from: string, body: BodyInit = "a log line\n") =>
	SELF.fetch("https://example.com/logs", {
		method: "POST",
		body,
		headers: { "CF-Connecting-IP": from },
	});
const read = (id: string, from = "198.51.100.1") =>
	SELF.fetch(`https://example.com/logs/${id}`, { headers: { "CF-Connecting-IP": from } });

afterEach(() => {
	vi.useRealTimers();
});

it("gives an uploaded log a short ID and returns it under any spelling of that ID", async () => {
	const response = await upload("192.0.2.1", "first line\nsecond line\n");
	expect(response.status).toBe(200);
	const { id } = await response.json<{ id: string }>();
	expect(id).toMatch(/^[0-9a-hjkmnp-tv-z]{6}$/);

	const log = await read(id.toUpperCase().replaceAll("0", "O").replaceAll("1", "l"));
	expect(log.status).toBe(200);
	expect(log.headers.get("Content-Type")).toBe("text/plain; charset=utf-8");
	expect(log.headers.get("Cache-Control")).toBe("private, no-store");
	expect(await log.text()).toBe("first line\nsecond line\n");
});

it("refuses what the server refuses", async () => {
	expect((await upload("192.0.2.2", "")).status).toBe(400);
	expect((await upload("192.0.2.2", new Uint8Array(1024 * 1024 + 1))).status).toBe(413);
	expect((await upload("192.0.2.2", new Uint8Array(1024 * 1024))).status).toBe(200);
	// One upload a minute from an address; an IPv6 address counts as its /64.
	expect((await upload("192.0.2.2")).status).toBe(429);
	expect((await upload("2001:db8:1:2::1")).status).toBe(200);
	expect((await upload("2001:db8:1:2:ffff::2")).status).toBe(429);
	expect((await upload("2001:db8:1:3::1")).status).toBe(200);

	expect((await read("zzzzzz")).status).toBe(404);
	expect((await read("not-an-id")).status).toBe(404);
	expect((await SELF.fetch("https://example.com/logs")).status).toBe(405);
	expect((await SELF.fetch("https://example.com/elsewhere")).status).toBe(404);
});

it("keeps ten logs an address, for three days, and slows guessing", async () => {
	vi.useFakeTimers({ toFake: ["Date"] });
	let id = "";
	for (let i = 0; i < 10; i++) {
		const response = await upload("192.0.2.3");
		expect(response.status).toBe(200);
		id ||= (await response.json<{ id: string }>()).id;
		vi.advanceTimersByTime(61_000);
	}
	expect((await upload("192.0.2.3")).status).toBe(429);
	expect((await upload("192.0.2.4")).status).toBe(200);

	// Ten lookups at once, then one a second, hits included.
	for (let i = 0; i < 10; i++) expect((await read(id, "198.51.100.2")).status).toBe(200);
	expect((await read(id, "198.51.100.2")).status).toBe(429);
	vi.advanceTimersByTime(1_000);
	expect((await read(id, "198.51.100.2")).status).toBe(200);

	// The budget never grows past ten, however long it rests after one lookup.
	expect((await read(id, "198.51.100.3")).status).toBe(200);
	vi.advanceTimersByTime(9_000);
	for (let i = 0; i < 10; i++) expect((await read(id, "198.51.100.3")).status).toBe(200);
	expect((await read(id, "198.51.100.3")).status).toBe(429);

	vi.advanceTimersByTime(3 * 24 * 60 * 60 * 1000);
	expect((await read(id)).status).toBe(404);
	expect((await upload("192.0.2.3")).status).toBe(200);
});

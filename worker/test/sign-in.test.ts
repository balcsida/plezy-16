import { runInDurableObject, SELF } from "cloudflare:test";
import { exports } from "cloudflare:workers";
import { afterEach, expect, it, vi } from "vite-plus/test";

// Each test signs in from addresses of its own, so their budgets do not mix.
const start = (from: string, body: BodyInit = JSON.stringify({ service: "mal" })) =>
	SELF.fetch("https://tv.example/auth/start", {
		method: "POST",
		body,
		headers: { "CF-Connecting-IP": from },
	});
const poll = (session: string, from: string) =>
	SELF.fetch(`https://tv.example/auth/result?session=${session}`, {
		headers: { "CF-Connecting-IP": from },
	});
const browse = (url: string) => SELF.fetch(url, { redirect: "manual" });
const started = async (from: string, service = "mal") => {
	const response = await start(from, JSON.stringify({ service }));
	expect(response.status).toBe(200);
	const { session, url } = await response.json<{ session: string; url: string }>();
	return { session, url, state: new URL(url).searchParams.get("state") ?? "" };
};

// Stands in for the provider's token endpoint and records what it was sent.
function provider(answer: () => Response) {
	const calls: { url: string; redirect?: string; form: Record<string, string> }[] = [];
	vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
		const form = init?.body instanceof URLSearchParams ? init.body : new URLSearchParams();
		calls.push({
			url: input instanceof Request ? input.url : input.toString(),
			// Never followed: a redirect would carry the secret wherever it points.
			redirect: init?.redirect,
			form: Object.fromEntries(form),
		});
		return answer();
	});
	return calls;
}

afterEach(() => {
	vi.restoreAllMocks();
	vi.useRealTimers();
});

it("signs a device in to MyAnimeList through a phone, and hands the tokens out once", async () => {
	const calls = provider(() =>
		Response.json({ access_token: "access", refresh_token: "refresh", expires_in: 3600 }),
	);
	const response = await start("203.0.113.1");
	expect(response.headers.get("Cache-Control")).toBe("private, no-store");
	const { session, url, expiresIn } = await response.json<{
		session: string;
		url: string;
		expiresIn: number;
	}>();
	expect(session).toMatch(/^[\w-]{24}$/);
	expect(url).toMatch(/^https:\/\/tv\.example\/auth\/mal\?state=[\w-]{24}$/);
	expect(expiresIn).toBe(600);

	const toProvider = await browse(url);
	expect(toProvider.status).toBe(302);
	const authorize = new URL(toProvider.headers.get("Location") ?? "");
	expect(authorize.origin + authorize.pathname).toBe("https://myanimelist.net/v1/oauth2/authorize");
	const state = authorize.searchParams.get("state") ?? "";
	const challenge = authorize.searchParams.get("code_challenge") ?? "";
	expect(challenge).toMatch(/^[\w.~-]{64}$/);
	expect(url.endsWith(state) && !url.includes(session) && state !== session).toBe(true);
	expect(Object.fromEntries(authorize.searchParams)).toEqual({
		response_type: "code",
		client_id: "mal-id",
		redirect_uri: "https://tv.example/auth/mal/callback",
		state,
		code_challenge: challenge,
		code_challenge_method: "plain",
	});

	// A return on the other provider's path is refused, and does not use up the right one.
	expect(
		(await browse(`https://tv.example/auth/anilist/callback?code=the-code&state=${state}`)).status,
	).toBe(404);
	const waiting = poll(session, "203.0.113.1");
	const back = await browse(`https://tv.example/auth/mal/callback?code=the-code&state=${state}`);
	expect(back.status).toBe(200);
	expect(await back.text()).toContain("Signed in to Plezy 16");
	expect(calls).toEqual([
		{
			url: "https://myanimelist.net/v1/oauth2/token",
			redirect: "manual",
			form: {
				grant_type: "authorization_code",
				code: "the-code",
				client_id: "mal-id",
				redirect_uri: "https://tv.example/auth/mal/callback",
				code_verifier: challenge,
			},
		},
	]);
	expect(back.headers.get("Cache-Control")).toBe("private, no-store");
	const result = await waiting;
	expect(result.status).toBe(200);
	expect(result.headers.get("Cache-Control")).toBe("private, no-store");
	expect(await result.json()).toEqual({
		accessToken: "access",
		refreshToken: "refresh",
		expiresIn: 3600,
	});

	// Once: neither the device's secret nor the browser's link works again.
	expect((await poll(session, "203.0.113.1")).status).toBe(410);
	expect(
		(await browse(`https://tv.example/auth/mal/callback?code=the-code&state=${state}`)).status,
	).toBe(404);
	expect((await browse(url)).status).toBe(404);
	expect(calls).toHaveLength(1);
});

it("sends AniList its secret, and takes the browser's return only once", async () => {
	const calls = provider(() => Response.json({ access_token: "access" }));
	const { session, url, state } = await started("203.0.113.2", "anilist");
	const authorize = new URL((await browse(url)).headers.get("Location") ?? "");
	expect(authorize.origin + authorize.pathname).toBe("https://anilist.co/api/v2/oauth/authorize");
	expect(Object.fromEntries(authorize.searchParams)).toEqual({
		response_type: "code",
		client_id: "anilist-id",
		redirect_uri: "https://tv.example/auth/anilist/callback",
		state,
	});

	const callback = `https://tv.example/auth/anilist/callback?code=the-code&state=${state}`;
	// Two returns at once, as a browser that reloads: one reaches the provider.
	const returns = await Promise.all([browse(callback), browse(callback)]);
	expect(returns.map((response) => response.status).sort((a, b) => a - b)).toEqual([200, 404]);
	expect(calls).toEqual([
		{
			url: "https://anilist.co/api/v2/oauth/token",
			redirect: "manual",
			form: {
				grant_type: "authorization_code",
				code: "the-code",
				client_id: "anilist-id",
				redirect_uri: "https://tv.example/auth/anilist/callback",
				client_secret: "anilist-secret",
			},
		},
	]);
	// The device asks only afterwards, and still gets its result.
	const result = await poll(session, "203.0.113.2");
	expect(await result.json()).toEqual({ accessToken: "access" });
});

it("tells the device why a sign-in failed, and the phone in plain words", async () => {
	const fails = async (
		from: string,
		query: string,
		status: number,
		shown: string,
		error: string,
	) => {
		const { session, state } = await started(from);
		const back = await browse(`https://tv.example/auth/mal/callback?${query}&state=${state}`);
		expect(back.status).toBe(status);
		expect(await back.text()).toContain(shown);
		expect(await (await poll(session, from)).json()).toEqual({ error });
	};
	let calls = provider(() => new Response("invalid_grant", { status: 400 }));
	await fails("203.0.113.3", "code=bad", 502, "Couldn't complete sign-in", "exchange_failed");
	expect(calls).toHaveLength(1);

	// An answer without a token, a redirect, and an answer too long to be one.
	for (const [index, answer] of [
		() => Response.json({ token_type: "Bearer" }),
		() =>
			new Response(null, { status: 302, headers: { Location: "https://elsewhere.example/token" } }),
		() => Response.json({ access_token: "access", padding: "x".repeat(64 * 1024) }),
	].entries()) {
		vi.restoreAllMocks();
		calls = provider(answer);
		await fails(
			`203.0.113.${30 + index}`,
			"code=odd",
			502,
			"Couldn't complete sign-in",
			"exchange_failed",
		);
	}

	vi.restoreAllMocks();
	calls = provider(() => Response.json({ access_token: "never asked for" }));
	await fails("203.0.113.5", "error=access_denied", 200, "Sign-in was cancelled.", "access_denied");
	await fails(
		"203.0.113.6",
		"error=server_error",
		200,
		"Sign-in failed. Please try again.",
		"authorization_failed",
	);
	await fails("203.0.113.7", "other=1", 400, "Sign-in response was incomplete", "missing_code");
	expect(calls).toHaveLength(0);
});

it("refuses what the server refuses", async () => {
	for (const [index, service] of ["trakt", "constructor", "__proto__", "", 7, null].entries()) {
		expect((await start(`203.0.113.${20 + index}`, JSON.stringify({ service }))).status).toBe(400);
	}
	expect((await SELF.fetch("https://tv.example/auth/start")).status).toBe(405);

	const { state } = await started("203.0.113.9");
	const gone = await browse("https://tv.example/auth/mal?state=unknown");
	expect(gone.status).toBe(404);
	expect(await gone.text()).toContain("no longer valid");
	expect((await browse(`https://tv.example/auth/anilist?state=${state}`)).status).toBe(404);
	expect(
		(await browse(`https://tv.example/auth/anilist/callback?code=c&state=${state}`)).status,
	).toBe(404);
	expect((await browse(`https://tv.example/auth/constructor?state=${state}`)).status).toBe(404);
	expect((await browse(`https://tv.example/auth/mal/callback/more?state=${state}`)).status).toBe(
		404,
	);
	expect((await browse(`https://tv.example/auth/mal/other?state=${state}`)).status).toBe(404);
	expect(
		(await SELF.fetch(`https://tv.example/auth/mal?state=${state}`, { method: "POST" })).status,
	).toBe(405);
	expect((await poll("not-a-session", "203.0.113.9")).status).toBe(410);
	expect((await browse("https://tv.example/auth/done")).status).toBe(200);

	// Three sessions at once from an address, and anything unreadable counts too.
	expect((await start("203.0.113.10", "not json")).status).toBe(400);
	expect(
		(await start("203.0.113.10", JSON.stringify({ service: "mal", padding: "x".repeat(512) })))
			.status,
	).toBe(400);
	expect((await start("203.0.113.10")).status).toBe(200);
	expect((await start("203.0.113.10")).status).toBe(429);
});

it("gives the result to the device's latest poll, and to nobody twice", async () => {
	provider(() => Response.json({ access_token: "access" }));
	const { session, state } = await started("203.0.113.13");
	// The first poll stands for a connection the device gave up on.
	const dropped = poll(session, "203.0.113.13");
	await scheduler.wait(50);
	const live = poll(session, "203.0.113.13");
	await scheduler.wait(50);
	await browse(`https://tv.example/auth/mal/callback?code=the-code&state=${state}`);
	expect((await dropped).status).toBe(204);
	expect(await (await live).json()).toEqual({ accessToken: "access" });
	expect((await poll(session, "203.0.113.13")).status).toBe(410);
});

it("holds a poll, limits polls, and forgets a session after ten minutes", async () => {
	// The clock is the test's; the hold is real time, cut from 50 seconds.
	vi.useFakeTimers({ toFake: ["Date"] });
	await runInDurableObject(exports.SignIn.getByName("sign-in"), (signIn) => {
		signIn.resultWait = 300;
	});
	const { session, url } = await started("203.0.113.11");

	let answered = false;
	const held = poll(session, "203.0.113.11");
	void held.then(() => (answered = true));
	await scheduler.wait(150);
	expect(answered).toBe(false);
	expect((await held).status).toBe(204);

	// A session nobody has is turned away without being charged to the address:
	// after twelve of those, its ten polls at once are still held.
	for (let i = 0; i < 12; i++)
		expect((await poll("not-a-session", "203.0.113.12")).status).toBe(410);
	const polls = await Promise.all(Array.from({ length: 11 }, () => poll(session, "203.0.113.12")));
	expect(polls.map((response) => response.status).sort((a, b) => a - b)).toEqual([
		...Array(10).fill(204),
		429,
	]);
	expect(polls.find((response) => response.status === 429)?.headers.get("Retry-After")).toBe("1");
	vi.advanceTimersByTime(1_000);
	expect((await poll(session, "203.0.113.12")).status).toBe(204);

	vi.advanceTimersByTime(10 * 60 * 1000);
	expect((await browse(url)).status).toBe(404);
	expect((await poll(session, "203.0.113.11")).status).toBe(410);
});

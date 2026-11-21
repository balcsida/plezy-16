import { DurableObject } from "cloudflare:workers";
import { NO_STORE, readUpTo, sourceOf, text } from "./shared.ts";

// The sign-in proxy of upstream's server/oauth.go, for a TV that has no browser.
// The app opens a session and shows its link as a QR code; a phone follows the
// link through the provider's own sign-in; the app, polling, is handed the
// tokens once. As there, sessions and tokens live in memory only and none of
// them is logged.
const SESSION_TTL = 10 * 60 * 1000;
const RESULT_WAIT = 50 * 1000;
const MAX_SESSIONS = 5000;
const START_BURST = 3; // sessions an address may open at once, then one a second
const RESULT_BURST = 10; // polls, likewise; a device polls about once per RESULT_WAIT
const PROVIDER_TIMEOUT = 15 * 1000;
const GONE = "This sign-in link is no longer valid. Start again from Plezy 16.";

type Provider = {
	clientId: string;
	clientSecret?: string;
	authorizeUrl: string;
	tokenUrl: string;
	pkce: boolean;
};
type Result = { accessToken?: string; refreshToken?: string; expiresIn?: number; error?: string };
type Session = {
	state: string; // what the browser carries
	poll: string; // the digest of what the device carries
	service: string;
	verifier: string; // MyAnimeList's PKCE; dropped once the code is exchanged
	created: number;
	claimed: boolean; // the browser's return counts once
	result?: Result;
	completed: boolean;
	done: PromiseWithResolvers<void>;
	polls: number; // how many polls this session has held
};

// A provider is on once its client ID is configured. A Map, not an object: the
// service name comes from the request, and "constructor" must find nothing.
function providersOf(env: {
	MAL_CLIENT_ID: string;
	ANILIST_CLIENT_ID: string;
	ANILIST_CLIENT_SECRET?: string;
}) {
	const providers = new Map<string, Provider>();
	if (env.MAL_CLIENT_ID) {
		providers.set("mal", {
			clientId: env.MAL_CLIENT_ID,
			authorizeUrl: "https://myanimelist.net/v1/oauth2/authorize",
			tokenUrl: "https://myanimelist.net/v1/oauth2/token",
			pkce: true,
		});
	}
	if (env.ANILIST_CLIENT_ID) {
		providers.set("anilist", {
			clientId: env.ANILIST_CLIENT_ID,
			clientSecret: env.ANILIST_CLIENT_SECRET,
			authorizeUrl: "https://anilist.co/api/v2/oauth/authorize",
			tokenUrl: "https://anilist.co/api/v2/oauth/token",
			pkce: false,
		});
	}
	return providers;
}

export class SignIn extends DurableObject<Cloudflare.Env> {
	#byState = new Map<string, Session>();
	#byPoll = new Map<string, Session>();
	#starts = new Budget(START_BURST);
	#polls = new Budget(RESULT_BURST);
	// A field so that a test need not wait the 50 seconds out.
	resultWait = RESULT_WAIT;

	async fetch(request: Request): Promise<Response> {
		const now = Date.now();
		for (const session of this.#byState.values()) {
			if (now - session.created > SESSION_TTL) this.#forget(session);
		}
		this.#starts.prune(now);
		this.#polls.prune(now);

		const url = new URL(request.url);
		const path = url.pathname.slice("/auth/".length);
		if (path === "start") return this.#start(request);
		if (path === "result") return this.#result(request, url);
		if (request.method !== "GET") return text("Method not allowed", 405);
		if (path === "done") return page(200);

		const [service = "", step, ...more] = path.split("/");
		const provider = this.#providers.get(service);
		if (!provider || more.length > 0 || (step !== undefined && step !== "callback"))
			return text("Not found", 404);
		const session = this.#byState.get(url.searchParams.get("state") ?? "");
		if (!session || session.service !== service) return page(404, GONE);
		return step === undefined
			? this.#authorize(provider, session)
			: this.#callback(provider, session, url.searchParams);
	}

	get #providers(): Map<string, Provider> {
		return providersOf(this.env);
	}

	#redirectUri(service: string): string {
		return `${this.env.BASE_URL}/auth/${service}/callback`;
	}

	// POST /auth/start: a session for the device, and the link it shows.
	async #start(request: Request): Promise<Response> {
		if (request.method !== "POST") return text("Method not allowed", 405);
		if (this.#starts.take(sourceOf(request), Date.now()) > 0) return text("Rate limited", 429);
		let service: unknown;
		try {
			const body = await readUpTo(request.body, 512);
			service = (JSON.parse(new TextDecoder().decode(body ?? undefined)) as { service?: unknown })
				.service;
		} catch {
			return text("Invalid JSON", 400);
		}
		const provider = typeof service === "string" ? this.#providers.get(service) : undefined;
		if (typeof service !== "string" || !provider) return text("Unknown service", 400);

		const secret = randomToken();
		const poll = await digest(secret);
		if (this.#byState.size >= MAX_SESSIONS) return text("Server busy", 503);
		const session: Session = {
			state: randomToken(),
			poll,
			service,
			verifier: provider.pkce ? randomVerifier() : "",
			created: Date.now(),
			claimed: false,
			completed: false,
			done: Promise.withResolvers(),
			polls: 0,
		};
		this.#byState.set(session.state, session);
		this.#byPoll.set(session.poll, session);
		return Response.json(
			{
				session: secret,
				url: `${this.env.BASE_URL}/auth/${service}?state=${session.state}`,
				expiresIn: SESSION_TTL / 1000,
			},
			{ headers: NO_STORE },
		);
	}

	// GET /auth/:service?state=: on to the provider's own sign-in.
	#authorize(provider: Provider, session: Session): Response {
		const query = new URLSearchParams({
			response_type: "code",
			client_id: provider.clientId,
			redirect_uri: this.#redirectUri(session.service),
			state: session.state,
		});
		if (provider.pkce) {
			// MyAnimeList takes only the plain method, where the challenge is the verifier.
			query.set("code_challenge", session.verifier);
			query.set("code_challenge_method", "plain");
		}
		return new Response(null, {
			status: 302,
			headers: { ...NO_STORE, Location: `${provider.authorizeUrl}?${query.toString()}` },
		});
	}

	// GET /auth/:service/callback: the provider sends the browser back with a code.
	async #callback(
		provider: Provider,
		session: Session,
		params: URLSearchParams,
	): Promise<Response> {
		// Claimed before the exchange: a replayed or doubled return must never
		// reach the provider again. The device still gets the one result.
		if (session.claimed) return page(404, GONE);
		session.claimed = true;

		const refused = params.get("error");
		if (refused) {
			const cancelled = refused === "access_denied";
			return this.#complete(session, {
				error: cancelled ? "access_denied" : "authorization_failed",
			})
				? page(200, cancelled ? "Sign-in was cancelled." : "Sign-in failed. Please try again.")
				: page(404, GONE);
		}
		const code = params.get("code");
		if (!code) {
			return this.#complete(session, { error: "missing_code" })
				? page(400, "Sign-in response was incomplete. Please try again.")
				: page(404, GONE);
		}
		let result: Result;
		try {
			result = await this.#exchange(provider, session, code);
		} catch (error) {
			// The reason only: the provider's answer may hold a token.
			console.error(
				`sign-in: ${session.service} token exchange failed: ${error instanceof Error ? error.message : "unknown"}`,
			);
			return this.#complete(session, { error: "exchange_failed" })
				? page(502, "Couldn't complete sign-in. Please try again.")
				: page(404, GONE);
		}
		return this.#complete(session, result) ? page(200) : page(404, GONE);
	}

	async #exchange(provider: Provider, session: Session, code: string): Promise<Result> {
		const form = new URLSearchParams({
			grant_type: "authorization_code",
			code,
			client_id: provider.clientId,
			redirect_uri: this.#redirectUri(session.service),
		});
		if (provider.clientSecret) form.set("client_secret", provider.clientSecret);
		if (provider.pkce) form.set("code_verifier", session.verifier);
		const response = await fetch(provider.tokenUrl, {
			method: "POST",
			body: form,
			headers: { Accept: "application/json" },
			// A redirect would carry the secret on to wherever it points.
			redirect: "manual",
			signal: AbortSignal.timeout(PROVIDER_TIMEOUT),
		});
		if (response.status !== 200) throw new Error(`provider HTTP ${response.status}`);
		let answer: { access_token?: unknown; refresh_token?: unknown; expires_in?: unknown } | null;
		try {
			answer = JSON.parse(
				new TextDecoder().decode((await readUpTo(response.body, 64 * 1024)) ?? undefined),
			);
		} catch {
			throw new Error("unreadable answer");
		}
		if (typeof answer?.access_token !== "string" || !answer.access_token)
			throw new Error("no access token");
		return {
			accessToken: answer.access_token,
			...(typeof answer.refresh_token === "string" && answer.refresh_token
				? { refreshToken: answer.refresh_token }
				: {}),
			...(Number.isInteger(answer.expires_in) && answer.expires_in !== 0
				? { expiresIn: answer.expires_in as number }
				: {}),
		};
	}

	// One result a session, and none for a session that has expired meanwhile.
	#complete(session: Session, result: Result): boolean {
		if (this.#byState.get(session.state) !== session || session.completed) return false;
		session.completed = true;
		session.result = result;
		session.verifier = "";
		session.done.resolve();
		return true;
	}

	#forget(session: Session): void {
		if (this.#byState.get(session.state) === session) this.#byState.delete(session.state);
		if (this.#byPoll.get(session.poll) === session) this.#byPoll.delete(session.poll);
	}

	// GET /auth/result?session=: held until the result is there, and handed out once.
	async #result(request: Request, url: URL): Promise<Response> {
		if (request.method !== "GET") return text("Method not allowed", 405);
		const poll = await digest(url.searchParams.get("session") ?? "");
		const session = this.#byPoll.get(poll);
		// An unknown session is turned away before the budget is charged, so junk
		// cannot starve an honest device; the secret is too long to guess.
		if (!session) return text("Session not found", 410);
		const wait = this.#polls.take(sourceOf(request), Date.now());
		if (wait > 0) return text("Rate limited", 429, { "Retry-After": String(wait) });

		// The result goes to the latest poll only. An earlier one that is still held
		// may be a connection the device gave up on, and would take the result with it.
		const turn = ++session.polls;
		let timer = 0;
		await Promise.race([
			session.done.promise,
			new Promise((resolve) => {
				timer = setTimeout(resolve, this.resultWait);
			}),
		]);
		clearTimeout(timer);
		// Not yet, or not this poll's to take: the device asks again.
		if (!session.completed || turn !== session.polls)
			return new Response(null, { status: 204, headers: NO_STORE });
		const result = session.result;
		if (this.#byPoll.get(poll) !== session || !result) return text("Session not found", 410);
		session.result = undefined;
		this.#forget(session);
		return Response.json(result.error ? { error: result.error } : result, { headers: NO_STORE });
	}
}

// What an address may do at once, refilling by one a second. In memory, like
// the sessions it guards.
class Budget {
	#spent = new Map<string, { tokens: number; at: number }>();
	#burst: number;

	constructor(burst: number) {
		this.#burst = burst;
	}

	// Takes one, or tells how many seconds until there is one to take.
	take(source: string, now: number): number {
		const spent = this.#spent.get(source);
		const tokens = spent
			? Math.min(this.#burst, spent.tokens + (now - spent.at) / 1000)
			: this.#burst;
		if (tokens < 1) return Math.ceil(1 - tokens);
		this.#spent.set(source, { tokens: tokens - 1, at: now });
		return 0;
	}

	prune(now: number): void {
		for (const [source, spent] of this.#spent) {
			if (now - spent.at >= this.#burst * 1000) this.#spent.delete(source);
		}
	}
}

// 144 bits, as 24 characters that are safe in a URL.
function randomToken(): string {
	const bytes = crypto.getRandomValues(new Uint8Array(18));
	return btoa(String.fromCharCode(...bytes))
		.replaceAll("+", "-")
		.replaceAll("/", "_");
}

function randomVerifier(): string {
	const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~";
	return Array.from(
		crypto.getRandomValues(new Uint8Array(64)),
		(byte) => alphabet[byte % alphabet.length],
	).join("");
}

// Only the digest of a device's secret is kept, as upstream keeps it.
async function digest(secret: string): Promise<string> {
	const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(secret));
	return Array.from(new Uint8Array(hash), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

const PAGE_HEAD =
	'<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;height:100%}body{display:flex;flex-direction:column;align-items:center;justify-content:center;font-family:-apple-system,system-ui,sans-serif;background:#fff;color:#1a1a1a;text-align:center;padding:1em;box-sizing:border-box}@media(prefers-color-scheme:dark){body{background:#0f0f0f;color:#f5f5f5}}svg{width:72px;height:72px;margin-bottom:20px}h2{margin:0 0 8px;font-weight:600;font-size:1.25rem}p{margin:0;opacity:.7;font-size:.95rem}</style>';
const SIGNED_IN = `<!doctype html>${PAGE_HEAD}<title>Signed in</title><body><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="#22c55e"/><path d="M7 12.5l3 3 7-7" stroke="#fff" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg><h2>Signed in to Plezy 16</h2><p>You can close this tab and return to the app.</p></body>`;
const FAILED = `<!doctype html>${PAGE_HEAD}<title>Sign-in failed</title><body><svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="10" fill="#ef4444"/><path d="M8 8l8 8M16 8l-8 8" stroke="#fff" stroke-width="2" fill="none" stroke-linecap="round"/></svg><h2>Sign-in failed</h2><p>`;

// What the phone's browser is shown: signed in, or why not. The reasons are the
// fixed texts above and below, never anything from the request.
function page(status: number, failure?: string): Response {
	return new Response(failure === undefined ? SIGNED_IN : `${FAILED}${failure}</p></body>`, {
		status,
		headers: { ...NO_STORE, "Content-Type": "text/html; charset=utf-8" },
	});
}

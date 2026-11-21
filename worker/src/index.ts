import { MAX_BYTES } from "./logs.ts";
import { readUpTo, sourceOf, text } from "./shared.ts";

export { Logs } from "./logs.ts";
export { SignIn } from "./sign-in.ts";

// What the TV build uses of upstream's server/: the log upload and the sign-in
// proxy for MyAnimeList and AniList. Each is one object that answers one step
// at a time, so two requests cannot both slip under a limit or claim one result.
export default {
	async fetch(request, _env, ctx) {
		const { pathname } = new URL(request.url);
		if (pathname === "/logs") {
			if (request.method !== "POST") return text("Method not allowed", 405);
			const body = await readUpTo(request.body, MAX_BYTES);
			if (!body) return text("Log too large (max 1MB)", 413);
			if (body.byteLength === 0) return text("Empty body", 400);
			return ctx.exports.Logs.getByName("logs").put(sourceOf(request), body);
		}
		if (pathname.startsWith("/logs/")) {
			if (request.method !== "GET") return text("Method not allowed", 405);
			return ctx.exports.Logs.getByName("logs").get(
				sourceOf(request),
				pathname.slice("/logs/".length),
			);
		}
		if (pathname.startsWith("/auth/"))
			return ctx.exports.SignIn.getByName("sign-in").fetch(request);
		return text("Not found", 404);
	},
} satisfies ExportedHandler;

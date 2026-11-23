import { bindings, defineConfig, exports } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

// Our registrations with the two providers. A provider is off while its ID is
// empty. The MyAnimeList ID is MAL_CLIENT_ID in scripts/tizen/defines.env too;
// it is an app of the type "other", which has no secret.
const MAL_CLIENT_ID: string = "1edda1cb4901e1e5571a2d189858e4de";
const ANILIST_CLIENT_ID: string = "57675";

export default defineConfig({
	worker: {
		// The address the TV build is given: tizenhat.<account subdomain>.workers.dev
		name: "tizenhat",
		compatibilityDate: "2026-11-17",
		entrypoint,
		env: {
			// That address. The sign-in links are built from it, and so are the
			// callbacks registered with the providers: <BASE_URL>/auth/mal/callback
			// and <BASE_URL>/auth/anilist/callback.
			BASE_URL: bindings.text("https://tizenhat.balcsida.workers.dev"),
			MAL_CLIENT_ID: bindings.text(MAL_CLIENT_ID),
			ANILIST_CLIENT_ID: bindings.text(ANILIST_CLIENT_ID),
			// Required once AniList is on, and a deploy fails without it. Set with:
			// cf workers secrets update ANILIST_CLIENT_SECRET --worker tizenhat --type secret_text
			ANILIST_CLIENT_SECRET: ANILIST_CLIENT_ID !== "" && bindings.secret(),
		},
		exports: {
			Logs: exports.durableObject({ storage: "sqlite" }),
			SignIn: exports.durableObject({ storage: "sqlite" }),
		},
	},
});

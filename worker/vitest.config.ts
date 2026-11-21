import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vite-plus";

export default defineConfig({
	plugins: [
		cloudflareTest({
			config: true,
			// The tests have providers of their own, whatever is registered for real.
			miniflare: {
				bindings: {
					BASE_URL: "https://tv.example",
					MAL_CLIENT_ID: "mal-id",
					ANILIST_CLIENT_ID: "anilist-id",
					ANILIST_CLIENT_SECRET: "anilist-secret",
				},
			},
		}),
	],
});

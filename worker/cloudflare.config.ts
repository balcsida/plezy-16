import { defineConfig, exports } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

export default defineConfig({
	worker: {
		// The address the TV build is given: tizenhat.<account subdomain>.workers.dev
		name: "tizenhat",
		compatibilityDate: "2026-11-17",
		entrypoint,
		exports: { Logs: exports.durableObject({ storage: "sqlite" }) },
	},
});

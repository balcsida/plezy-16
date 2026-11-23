export const NO_STORE = { "Cache-Control": "private, no-store" };

export function text(
	message: string,
	status: number,
	headers: Record<string, string> = {},
): Response {
	return new Response(`${message}\n`, { status, headers: { ...NO_STORE, ...headers } });
}

// Reads no more than the limit: the size a sender declares is not to be trusted.
export async function readUpTo(
	body: ReadableStream<Uint8Array> | null,
	max: number,
): Promise<ArrayBuffer | null> {
	const chunks: Uint8Array[] = [];
	let size = 0;
	for await (const chunk of body ?? []) {
		size += chunk.byteLength;
		if (size > max) return null;
		chunks.push(chunk);
	}
	return new Blob(chunks).arrayBuffer();
}

// Whom the limits count: the address Cloudflare saw. An IPv6 client has a whole
// /64 to itself, so that is its address here.
export function sourceOf(request: Request): string {
	const ip = request.headers.get("CF-Connecting-IP") ?? "";
	if (!ip.includes(":")) return ip;
	const [head = "", tail = ""] = ip.split("::");
	const groups = head.split(":").filter(Boolean);
	const end = tail.split(":").filter(Boolean);
	while (groups.length + end.length < 8) groups.push("0");
	return [...groups, ...end].slice(0, 4).join(":");
}

/** YYYY-MM-DD in UTC. The salt window rotates on this boundary. */
export function utcDate(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

/**
 * Cookieless unique-visitor id: hex SHA-256 over (secret salt | UTC date | ip | ua).
 * Because the date is in the hash and the salt is secret, the id cannot be linked
 * across days and cannot be reversed to the IP. Only this hash is ever stored.
 */
export async function dailyVisitorHash(ip: string, ua: string, dateUTC: string, salt: string): Promise<string> {
  const data = new TextEncoder().encode(`${salt}|${dateUTC}|${ip}|${ua}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

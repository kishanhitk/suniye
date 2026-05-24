const DEFAULT_APPCAST_URL = "https://github.com/kishanhitk/suniye/releases/latest/download/appcast.xml";

export async function handleAppcastRequest(
  request: Request,
  fetcher: typeof fetch = fetch,
  appcastURL: string = DEFAULT_APPCAST_URL
): Promise<Response> {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return new Response("Method not allowed", {
      status: 405,
      headers: {
        Allow: "GET, HEAD",
      },
    });
  }

  let upstream: Response;
  try {
    upstream = await fetcher(appcastURL, {
      headers: {
        Accept: "application/rss+xml, application/xml, text/xml;q=0.9, */*;q=0.8",
        "User-Agent": "Suniye-Appcast-Proxy",
      },
    });
  } catch {
    return new Response("Appcast unavailable", { status: 502 });
  }

  if (!upstream.ok || !upstream.body) {
    return new Response("Appcast unavailable", { status: 502 });
  }

  return new Response(request.method === "HEAD" ? null : upstream.body, {
    status: 200,
    headers: {
      "Content-Type": "application/rss+xml; charset=utf-8",
      "Cache-Control": "public, max-age=300, s-maxage=300, stale-while-revalidate=3600",
    },
  });
}

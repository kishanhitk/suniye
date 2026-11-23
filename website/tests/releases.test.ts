import { afterEach, beforeEach, describe, expect, spyOn, test, type Mock } from "bun:test";
import { createReleasesSource } from "../src/lib/releases";

const githubRelease = {
  tag_name: "v0.0.74",
  name: "v0.0.74",
  html_url: "https://github.com/kishanhitk/suniye/releases/tag/v0.0.74",
  published_at: "2026-11-12T09:26:33Z",
  body: "## What's Changed\n* feat(asr): add Qwen3-ASR by @kishanhitk in https://github.com/kishanhitk/suniye/pull/127\n",
  prerelease: false,
  draft: false,
};

const ok = () => Response.json([githubRelease]);
const refused = (status: number) => Response.json({ message: "refused" }, { status });

/** A fake GitHub that answers with `responses` in order and records each call's Authorization header. */
function fakeGitHub(...responses: Response[]) {
  const authorizations: (string | null)[] = [];
  const fetcher = (async (_input: RequestInfo | URL, init?: RequestInit) => {
    authorizations.push(new Headers(init?.headers).get("Authorization"));
    const response = responses.shift();
    if (!response) throw new Error("unexpected GitHub call");
    return response;
  }) as typeof fetch;
  return { fetcher, authorizations };
}

describe("releases source", () => {
  let warn: Mock<typeof console.warn>;
  let clock: number;
  const now = () => clock;

  beforeEach(() => {
    clock = 0;
    warn = spyOn(console, "warn").mockImplementation(() => {});
  });
  afterEach(() => warn.mockRestore());

  test("authenticates with the token when one is set", async () => {
    const github = fakeGitHub(ok());

    const releases = await createReleasesSource(github.fetcher, now)("t0ken");

    expect(github.authorizations).toEqual(["Bearer t0ken"]);
    expect(releases.map((release) => [release.version, release.status])).toEqual([["v0.0.74", "Latest"]]);
  });

  test("calls without authentication when no token is set", async () => {
    const github = fakeGitHub(ok());

    await createReleasesSource(github.fetcher, now)(undefined);

    expect(github.authorizations).toEqual([null]);
  });

  test("retries without the token when GitHub rejects it", async () => {
    const github = fakeGitHub(refused(401), ok());

    const releases = await createReleasesSource(github.fetcher, now)("revoked");

    expect(github.authorizations).toEqual(["Bearer revoked", null]);
    expect(releases).toHaveLength(1);
  });

  test("calls without the token when the token is not a valid header value", async () => {
    const github = fakeGitHub(ok());

    const releases = await createReleasesSource(github.fetcher, now)("t0ken\nsecond line");

    expect(github.authorizations).toEqual([null]);
    expect(releases).toHaveLength(1);
  });

  test("answers from the last good list for five minutes", async () => {
    const github = fakeGitHub(ok());
    const fetchReleases = createReleasesSource(github.fetcher, now);

    const first = await fetchReleases("t0ken");
    clock = 4 * 60_000;
    const second = await fetchReleases("t0ken");

    expect(github.authorizations).toHaveLength(1);
    expect(second).toEqual(first);
  });

  test("keeps the last good list when a later call fails", async () => {
    const github = fakeGitHub(ok(), refused(403));
    const fetchReleases = createReleasesSource(github.fetcher, now);

    const first = await fetchReleases("t0ken");
    clock = 6 * 60_000;
    const afterFailure = await fetchReleases("t0ken");

    expect(github.authorizations).toHaveLength(2);
    expect(afterFailure).toEqual(first);
  });

  test("waits five minutes after a failed call before it calls again", async () => {
    const github = fakeGitHub(ok(), refused(403), ok());
    const fetchReleases = createReleasesSource(github.fetcher, now);

    await fetchReleases("t0ken");
    clock = 6 * 60_000;
    await fetchReleases("t0ken");
    clock = 7 * 60_000;
    await fetchReleases("t0ken");

    expect(github.authorizations).toHaveLength(2);
  });

  test("has no releases when the first call fails", async () => {
    const github = fakeGitHub(refused(403));

    expect(await createReleasesSource(github.fetcher, now)(undefined)).toEqual([]);
  });
});

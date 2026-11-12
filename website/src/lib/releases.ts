import { DOWNLOAD_URL, GITHUB_RELEASES_URL, SITE_URL } from "./site";

// GitHub releases → the changelog, shared by changelog.astro and its Markdown
// variant so both list the same releases with the same notes.

interface GitHubRelease {
  tag_name: string;
  name: string | null;
  html_url: string;
  published_at: string | null;
  body: string | null;
  prerelease: boolean;
  draft: boolean;
}

export interface ReleaseItem {
  title: string;
}

export interface ReleasesEnv {
  GITHUB_TOKEN?: string;
}

export interface Release {
  version: string;
  date: string;
  status?: "Latest";
  href: string;
  items: ReleaseItem[];
  fullChangelogUrl?: string;
}

const GITHUB_RELEASES_API_URL = "https://api.github.com/repos/kishanhitk/suniye/releases?per_page=8";
const GITHUB_TIMEOUT_MS = 5_000;
const RELEASES_FRESH_MS = 5 * 60_000;

const releaseDateFormatter = new Intl.DateTimeFormat("en", {
  month: "short",
  day: "numeric",
  year: "numeric",
  timeZone: "UTC",
});

function requestGitHubReleases(fetcher: typeof fetch, githubToken: string | undefined): Promise<Response> {
  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "User-Agent": "suniye-website",
  };
  if (githubToken) {
    headers.Authorization = `Bearer ${githubToken}`;
  }
  return fetcher(GITHUB_RELEASES_API_URL, { headers, signal: AbortSignal.timeout(GITHUB_TIMEOUT_MS) });
}

async function fetchGitHubReleases(fetcher: typeof fetch, githubToken: string | undefined): Promise<GitHubRelease[]> {
  try {
    let response = await requestGitHubReleases(fetcher, githubToken);
    if (response.status === 401 && githubToken) {
      console.warn("GitHub rejected GITHUB_TOKEN (401); fetching releases without it");
      response = await requestGitHubReleases(fetcher, undefined);
    }

    if (!response.ok) {
      console.warn(
        `Failed to fetch GitHub releases: ${response.status} (rate limit remaining: ${response.headers.get("x-ratelimit-remaining")})`
      );
      return [];
    }

    const payload = await response.json();
    if (!Array.isArray(payload)) {
      console.warn("Failed to fetch GitHub releases: unexpected response shape");
      return [];
    }

    return payload as GitHubRelease[];
  } catch (error) {
    console.warn("Failed to fetch GitHub releases", error);
    return [];
  }
}

export function parseReleaseItems(body: string | null): ReleaseItem[] {
  const cleanTitle = (title: string) => title.replace(/^\[codex\]\s*/i, "");

  const seen = new Set<string>();
  return (body ?? "")
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.startsWith("* "))
    .map((line) => line.slice(2).trim())
    .map((line) => {
      const match = line.match(/^(.*?) by @([^\s]+) in (https:\/\/github\.com\/\S+)$/);
      return { title: cleanTitle(match ? match[1] : line) };
    })
    .filter((item) => {
      if (seen.has(item.title)) {
        return false;
      }
      seen.add(item.title);
      return true;
    });
}

export function parseFullChangelogUrl(body: string | null): string | undefined {
  return body?.match(/\*\*Full Changelog\*\*: (https:\/\/\S+)/)?.[1];
}

function toReleases(githubReleases: readonly GitHubRelease[]): Release[] {
  return githubReleases
    .filter((release) => !release.draft && !release.prerelease)
    .map((release, index) => ({
      version: release.name || release.tag_name,
      date: release.published_at ? releaseDateFormatter.format(new Date(release.published_at)) : "Unpublished",
      status: index === 0 ? "Latest" : undefined,
      href: release.html_url,
      items: parseReleaseItems(release.body),
      fullChangelogUrl: parseFullChangelogUrl(release.body),
    }));
}

/**
 * Keeps the last good list: it answers without a GitHub call for five minutes,
 * and stands in for a failed call however old it is. A failed call also waits
 * five minutes before the next try.
 */
export function createReleasesSource(fetcher: typeof fetch = fetch, now: () => number = Date.now) {
  let lastGood: { releases: Release[]; fetchedAt: number } | undefined;

  return async function fetchReleases(githubToken: string | undefined): Promise<Release[]> {
    if (lastGood && now() - lastGood.fetchedAt < RELEASES_FRESH_MS) {
      return lastGood.releases;
    }

    const releases = toReleases(await fetchGitHubReleases(fetcher, githubToken));
    if (releases.length === 0) {
      if (!lastGood) {
        return [];
      }
      lastGood.fetchedAt = now();
      return lastGood.releases;
    }

    lastGood = { releases, fetchedAt: now() };
    return releases;
  };
}

export const fetchReleases = createReleasesSource();

export const CHANGELOG_META = {
  title: "Suniye Changelog - What's New",
  description: "Updates to Suniye's recording, transcription, insertion, and local-first macOS workflows.",
  unavailable: "Release notes are temporarily unavailable.",
} as const;

export function changelogMarkdown(releases: readonly Release[]): string {
  const sections =
    releases.length > 0
      ? releases
          .map((release) => {
            const heading = `## ${release.version} — ${release.date}${release.status ? ` (${release.status})` : ""}`;
            const items =
              release.items.length > 0
                ? release.items.map((item) => `- ${item.title}`).join("\n")
                : "No release notes published for this release.";
            const links = [`Release: ${release.href}`, release.fullChangelogUrl && `Full changelog: ${release.fullChangelogUrl}`]
              .filter(Boolean)
              .join("\n");
            return `${heading}\n\n${items}\n\n${links}`;
          })
          .join("\n\n")
      : `${CHANGELOG_META.unavailable} The full list is on GitHub: ${GITHUB_RELEASES_URL}`;

  return `# Suniye Changelog

${CHANGELOG_META.description}

- Download the latest release: ${DOWNLOAD_URL}
- All releases on GitHub: ${GITHUB_RELEASES_URL}

${sections}

---

Home: ${SITE_URL}/ · Install help: ${SITE_URL}/#install
`;
}

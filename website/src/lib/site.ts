// Facts about the project that more than one surface repeats — the HTML pages,
// their Markdown variants, llms.txt, and the JSON-LD. One definition each so
// they cannot drift apart.

export const SITE_URL = "https://suniye.app";
export const SITE_NAME = "Suniye";
export const SITE_TAGLINE = "Private, on-device dictation for macOS";
export const SITE_DESCRIPTION =
  "Open-source, local-first dictation for macOS. Hold a key, speak, and your words appear at your cursor. No audio leaves your machine.";

export const GITHUB_URL = "https://github.com/kishanhitk/suniye";
export const GITHUB_ISSUES_URL = `${GITHUB_URL}/issues`;
export const GITHUB_SECURITY_URL = `${GITHUB_URL}/security/advisories/new`;
export const GITHUB_RELEASES_URL = `${GITHUB_URL}/releases`;
export const DOWNLOAD_URL = `${GITHUB_URL}/releases/latest/download/Suniye.dmg`;
export const BREW_INSTALL = "brew install --cask kishanhitk/tap/suniye";
export const QUARANTINE_CMD = "xattr -rd com.apple.quarantine /Applications/Suniye.app";

export const MAINTAINER = {
  name: "Kishan Kumar",
  github: "https://github.com/kishanhitk",
  website: "https://kishans.in/",
  x: "https://x.com/jst_kishan",
  // The maintainer's public GitHub location. Kept deliberately coarse — there
  // is no company and no office, so no street address is claimed anywhere.
  region: "Bihar",
  countryCode: "IN",
} as const;

export const CONTACT_EMAIL = "kishansharma1231@gmail.com";

export const SOCIAL_PROFILES = [GITHUB_URL, MAINTAINER.github, MAINTAINER.x] as const;

export interface SitePage {
  path: string;
  title: string;
  summary: string;
}

/** Every human-readable page, in the order an index should list them. */
export const SITE_PAGES: readonly SitePage[] = [
  { path: "/", title: "Home", summary: "What Suniye is, how it works, speech models, install steps, and FAQ." },
  { path: "/about", title: "About", summary: "Who builds Suniye, why it exists, and how the project is run." },
  { path: "/contact", title: "Contact", summary: "How to report bugs, ask questions, and reach the maintainer." },
  { path: "/blogs", title: "Blog", summary: "Comparisons and guides on dictation for macOS." },
  { path: "/changelog", title: "Changelog", summary: "What changed in each release, pulled from GitHub releases." },
  { path: "/privacy", title: "Privacy", summary: "Exactly what the app and this website collect, and what they never do." },
];

export function absoluteUrl(path: string): string {
  return new URL(path, SITE_URL).toString();
}

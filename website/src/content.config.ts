import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

// Every post is either a head-to-head comparison (needs a named competitor for
// the comparison-page conventions — feature table, verdict, differentiators)
// or a plain guide/explainer. The schema enforces that split at build time
// instead of leaving it to convention.
const blog = defineCollection({
  loader: glob({ pattern: "**/*.md", base: "./src/content/blog" }),
  schema: z.object({
    title: z.string(),
    // Google truncates <title> around 60 chars; the on-page H1 can afford to
    // be more descriptive than that, so this overrides just the <title>/meta
    // tag when the headline itself runs long. Falls back to `title`.
    seoTitle: z.string().max(60).optional(),
    description: z.string(),
    publishDate: z.coerce.date(),
    updatedDate: z.coerce.date().optional(),
    category: z.enum(["comparison", "guide"]),
    competitor: z.string().optional(),
    // Opt-in: renders the cloud-vs-local flow diagram above the article body.
    // Only true for posts whose actual argument is that specific comparison.
    audioPathDiagram: z.boolean().default(false),
    draft: z.boolean().default(false),
  }),
});

export const collections = { blog };

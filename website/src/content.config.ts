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
    description: z.string(),
    publishDate: z.coerce.date(),
    updatedDate: z.coerce.date().optional(),
    category: z.enum(["comparison", "guide"]),
    competitor: z.string().optional(),
    draft: z.boolean().default(false),
  }),
});

export const collections = { blog };

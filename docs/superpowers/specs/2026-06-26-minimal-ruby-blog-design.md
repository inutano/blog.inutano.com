# Minimal Ruby Static Blog — Design

**Date:** 2026-06-26
**Status:** Approved (pending spec review)

## Problem

`blog.inutano.com` is a zen-style, single-page **general** blog: one scrolling page
listing short Japanese posts, newest first, with a gray title at the top. The recent
posts all happen to be "best buy of the year" entries only because the owner hasn't
had time to write the more general posts the blog is meant to hold; the system must
not assume a single topic. The *output* is trivial.

The *machinery* is not. The site is built on Gatsby 5 + React + TypeScript +
GraphQL + MDX + `gatsby-plugin-sharp` image processing + an omni font loader, with
a ~500KB `yarn.lock`. This stack is wildly out of proportion to the content. The
owner has forgotten how to publish a post because doing so requires re-engaging an
entire modern JS SSG toolchain.

**Goal:** replace the toolchain with the smallest thing that reproduces the exact
current site, so that posting is "write a Markdown file, push to git" and the whole
system is readable in five minutes years from now.

## Decisions (from brainstorming)

- **Posting flow:** write a `.md` file, `git push`; a GitHub Action regenerates the
  static HTML. No local toolchain required to publish.
- **Site shape:** keep the single scrolling page (all posts on one page, newest
  first). No per-post pages.
- **Build tool:** a tiny custom script, no framework.
- **Script language:** Ruby.
- **Carried over from current site:** exact look/CSS, Google Analytics
  (`G-7TNHDTZMES`), Google-hosted Source Code Pro font.
- **Approved during design:** drop the `gh-pages` branch in favor of GitHub's
  official Pages deploy; rename frontmatter key `datePublished` → `date`.

## Architecture

### Target repository layout

```
blog.inutano.com/
├── posts/
│   ├── _template.md          # generic starter; copy to start a new post
│   ├── 2020-bestbuy.md       # existing posts keep their names
│   ├── 2021-bestbuy.md
│   ├── 2022-bestbuy.md
│   ├── 2023-bestbuy.md
│   ├── 2024-bestbuy.md
│   └── 2025-bestbuy.md
├── assets/
│   └── style.css             # current styling as plain CSS (no Sass)
├── template.html.erb         # page shell: <head>, GA, font, title, post slot
├── build.rb                  # the generator (~100 lines)
├── Gemfile                   # single dependency: kramdown
├── CNAME                     # unchanged → blog.inutano.com
├── .github/workflows/publish.yml
└── README.md                 # "How to post" instructions
```

### Removed

All Gatsby-era files: `gatsby-config.ts`, `src/`, `package.json`, `yarn.lock`,
`tsconfig.json`, and the `blog/<slug>/index.mdx` tree (after migration). The old
`.github/workflows/publish.yml` is replaced.

### Post format

Each post is one Markdown file in `posts/`. New posts use the general convention
`YYYY-MM-DD-slug.md` (sortable and descriptive); existing files keep their current
names. Filename is only an identifier and the anchor source — ordering comes from
the `date` frontmatter, not the filename.

Two-line YAML frontmatter:

```markdown
---
title: 記事のタイトル
date: 2026-06-27
---

本文の Markdown ...
```

- `title` (string) and `date` (`YYYY-MM-DD`) are required.
- Inline raw HTML is allowed and passes through untouched, so existing
  `<a href="https://amzn.to/…" target="_blank">` affiliate links work unchanged.

### build.rb behavior

1. Glob `posts/*.md`, ignoring files whose basename starts with `_` (so
   `_template.md` is skipped).
2. For each file: split YAML frontmatter from body; fail with a clear error if
   `title` or `date` is missing or `date` is unparseable.
3. Render the body to HTML with **kramdown**, configured to pass raw HTML through
   verbatim.
4. Sort posts by `date` descending (newest first). Ties broken by filename
   descending for stable output.
5. For each post emit:
   `<section><h2 id="SLUG">TITLE</h2>RENDERED_BODY</section>`
   where `SLUG` is the file's basename without extension (e.g. `2024-bestbuy`). Slug
   anchors are unique (the filesystem guarantees unique filenames within `posts/`)
   and human-readable, which a general multi-topic blog needs (two posts may share a
   date). This changes the anchor scheme from the old `#YYYYMMDD`.
6. Read `template.html.erb`, inject the concatenated sections into the post slot,
   write `_site/index.html`.
7. Copy `assets/` into `_site/assets/` alongside `index.html`.

The `_site/` build output directory is gitignored; it is the only thing CI
publishes.

### template.html.erb

Static page shell holding everything that is not a post: `<html>`/`<head>` with the
`<title>`, the Google Analytics `G-7TNHDTZMES` snippet, the Source Code Pro font
link, a link to `assets/style.css`, and the `<header>` with the gray
`blog.inutano.com` title. A single ERB slot receives the generated post HTML. This
reproduces the markup currently emitted by `src/pages/index.tsx`.

### Styling

`src/pages/styles.sass` is hand-converted to plain `assets/style.css`. The Sass
used is limited to variables and nested selectors, so the compiled CSS is small and
direct. Visual result is identical: `main` max-width 640px, gray `h1.blogTitle`,
`h2` 200% / `h3` 150%, `line-height` 1.75, link color `#369ecf`, responsive padding
at the 960px breakpoint.

### Hosting / deploy

Remains GitHub Pages on the custom domain via the unchanged `CNAME`. A new
`.github/workflows/publish.yml`, triggered on push to `main`:

1. Checks out the repo.
2. Sets up Ruby and installs the `kramdown` gem (via `Gemfile`).
3. Runs `ruby build.rb` to produce the site into a build output directory.
4. Publishes that directory using GitHub's official Pages actions
   (`actions/upload-pages-artifact` + `actions/deploy-pages`).

No `gh-pages` branch; `main` is the single source of truth. The repo's Pages
setting must be switched to "GitHub Actions" as the source (a one-time manual
settings change, noted in the README).

## Migration

The existing six posts in `blog/<slug>/index.mdx` are plain Markdown with headings,
paragraphs, and inline `<a>` tags — no JSX components are used — so conversion is
mechanical:

1. Move `blog/<slug>/index.mdx` → `posts/<slug>.md`.
2. Rename frontmatter key `datePublished` → `date`.
3. Wrap any bare standalone URLs (present in the draft `2025-bestbuy`) so they
   render as intended; otherwise content is unchanged.

The in-progress `blog/2025-bestbuy/` (currently untracked) is migrated the same way.

## Local development

- Preview: `ruby build.rb && open _site/index.html`.
- No `npm install`, no framework, no GraphQL. Optionally
  `ruby -run -e httpd _site -p 8000` to serve locally.

## Error handling

- Missing/empty `posts/` → build writes a page with no sections (does not crash).
- A post missing `title` or `date`, or with an unparseable `date` → build aborts
  with a message naming the offending file, so CI fails loudly rather than
  publishing a broken page.

## How to post (README content)

1. `cp posts/_template.md posts/2026-06-27-my-post.md`
2. Edit the file: set `title` and `date`, write the body in Markdown.
3. `git add posts && git commit -m "new post" && git push`
4. The GitHub Action builds and deploys automatically.

(Optional local check before pushing: `ruby build.rb && open _site/index.html`.)

## Out of scope (YAGNI)

- Per-post pages / permalinks beyond the per-post `#SLUG` anchors.
- RSS/Atom feed, tags, pagination, search.
- Any client-side JavaScript beyond the existing analytics snippet.
- Image processing pipeline (current posts use no local images).

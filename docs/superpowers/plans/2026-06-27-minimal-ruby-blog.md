# Minimal Ruby Static Blog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Gatsby toolchain with a single Ruby script that regenerates the existing zen single-page blog from Markdown files, so publishing is "write a `.md`, push to git."

**Architecture:** A ~80-line `build.rb` reads `posts/*.md`, parses two-line frontmatter, renders each body with kramdown, sorts by date descending, and injects `<section>` blocks into an ERB page shell to produce `_site/index.html`. A GitHub Action runs the script on push and publishes `_site/` via GitHub's official Pages deploy. No framework, no GraphQL, no React.

**Tech Stack:** Ruby 3.2, kramdown (Markdown→HTML), ERB (templating), minitest (tests), GitHub Actions Pages.

## Global Constraints

- Ruby script must run on the system Ruby (3.2.2 confirmed locally) and in CI with **one** runtime gem: `kramdown`. No other runtime dependencies.
- Use kramdown's **default** parser with `auto_ids: false` (no GFM gem; no injected heading ids).
- Output must reproduce the current site structurally: `<main><header><a href="https://blog.inutano.com"><h1 class="blogTitle">blog.inutano.com</h1></a></header><article>…sections…</article></main>`.
- Each post renders as `<section><h2 id="SLUG">TITLE</h2>BODY_HTML</section>`, where `SLUG` is the file basename without `.md`.
- Posts sorted by `date` frontmatter descending; ties by slug descending.
- Files whose basename starts with `_` (e.g. `_template.md`) are not published.
- Carry over verbatim: Google Analytics id `G-7TNHDTZMES`, the Source Code Pro Google Font, and the existing CSS rules.
- Build output directory is `_site/` and is gitignored.
- Frontmatter key is `date` (renamed from the old `datePublished`).

---

### Task 1: Build script core — parse & load posts

**Files:**
- Create: `Gemfile`
- Create: `.gitignore` (append `_site/`)
- Create: `build.rb`
- Test: `test/build_test.rb`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `parse_post(path) -> Hash` with symbol keys `:slug` (String), `:title` (String), `:date` (Date), `:body_html` (String). Raises `RuntimeError` with a message naming `path` when frontmatter is absent, `title` is missing/empty, `date` is missing/empty, or `date` is unparseable.
  - `load_posts(dir) -> Array<Hash>` of the above, excluding basenames starting with `_`, sorted by `[:date, :slug]` descending.

- [ ] **Step 1: Create the Gemfile**

```ruby
# Gemfile
source "https://rubygems.org"

gem "kramdown", "~> 2.4"

group :test do
  gem "minitest", "~> 5.16"
end
```

- [ ] **Step 2: Add `_site/` to .gitignore**

Append this line to `.gitignore` (create the file if missing; keep any existing lines):

```
_site/
```

- [ ] **Step 3: Write the failing tests**

Create `test/build_test.rb`:

```ruby
require "minitest/autorun"
require "fileutils"
require "date"
require_relative "../build"

class BuildTest < Minitest::Test
  def setup
    @dir = File.join(__dir__, "fixtures_tmp")
    FileUtils.rm_rf(@dir)
    FileUtils.mkdir_p(@dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write(name, content)
    path = File.join(@dir, name)
    File.write(path, content)
    path
  end

  def test_parse_post_extracts_fields
    path = write("2024-foo.md", "---\ntitle: Hello\ndate: 2024-01-02\n---\n\nWorld\n")
    post = parse_post(path)
    assert_equal "2024-foo", post[:slug]
    assert_equal "Hello", post[:title]
    assert_equal Date.new(2024, 1, 2), post[:date]
    assert_includes post[:body_html], "World"
  end

  def test_parse_post_passes_raw_inline_html
    path = write("a.md", %(---\ntitle: T\ndate: 2024-01-01\n---\n\n<a href="x" target="_blank">link</a>\n))
    post = parse_post(path)
    assert_includes post[:body_html], %(target="_blank")
  end

  def test_parse_post_does_not_inject_heading_ids
    path = write("b.md", "---\ntitle: T\ndate: 2024-01-01\n---\n\n### 見出し\n")
    post = parse_post(path)
    assert_includes post[:body_html], "<h3>"
    refute_includes post[:body_html], "id="
  end

  def test_missing_title_raises
    path = write("c.md", "---\ndate: 2024-01-01\n---\n\nbody\n")
    err = assert_raises(RuntimeError) { parse_post(path) }
    assert_match(/missing 'title'/, err.message)
  end

  def test_missing_frontmatter_raises
    path = write("d.md", "no frontmatter here\n")
    err = assert_raises(RuntimeError) { parse_post(path) }
    assert_match(/frontmatter/, err.message)
  end

  def test_unparseable_date_raises
    path = write("e.md", "---\ntitle: T\ndate: notadate\n---\n\nbody\n")
    err = assert_raises(RuntimeError) { parse_post(path) }
    assert_match(/date/, err.message)
  end

  def test_load_posts_sorts_desc_and_skips_underscore
    write("2020-a.md", "---\ntitle: Old\ndate: 2020-01-01\n---\n\nx\n")
    write("2024-b.md", "---\ntitle: New\ndate: 2024-01-01\n---\n\nx\n")
    write("_template.md", "---\ntitle: Tmpl\ndate: 2099-01-01\n---\n\nx\n")
    posts = load_posts(@dir)
    assert_equal ["2024-b", "2020-a"], posts.map { |p| p[:slug] }
  end
end
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `ruby -Itest test/build_test.rb`
Expected: FAIL — `cannot load such file -- ../build` (build.rb does not exist yet).

- [ ] **Step 5: Write the minimal build.rb**

Create `build.rb` with just the parsing/loading core:

```ruby
#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "kramdown"

# Split frontmatter from body and parse the two keys we use (title, date).
# We read them directly rather than depending on a YAML library.
def parse_post(path)
  raw = File.read(path)
  unless raw.start_with?("---")
    raise "#{path}: missing frontmatter (file must start with '---')"
  end
  _lead, frontmatter, body = raw.split(/^---\s*$\r?\n/, 3)
  body ||= ""

  meta = {}
  frontmatter.to_s.each_line do |line|
    next if line.strip.empty?
    key, _sep, value = line.partition(":")
    meta[key.strip] = value.strip
  end

  title = meta["title"]
  date_str = meta["date"]
  raise "#{path}: missing 'title' in frontmatter" if title.nil? || title.empty?
  raise "#{path}: missing 'date' in frontmatter" if date_str.nil? || date_str.empty?

  begin
    date = Date.parse(date_str)
  rescue ArgumentError
    raise "#{path}: unparseable date '#{date_str}' (use YYYY-MM-DD)"
  end

  body_html = Kramdown::Document.new(body, auto_ids: false).to_html

  { slug: File.basename(path, ".md"), title: title, date: date, body_html: body_html }
end

def load_posts(dir)
  paths = Dir.glob(File.join(dir, "*.md")).reject { |p| File.basename(p).start_with?("_") }
  paths.map { |p| parse_post(p) }.sort_by { |p| [p[:date], p[:slug]] }.reverse
end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `ruby -Itest test/build_test.rb`
Expected: PASS — 7 runs, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add Gemfile .gitignore build.rb test/build_test.rb
git commit -m "feat: add build.rb post parsing and loading with tests"
```

---

### Task 2: Page assembly — template, CSS, and `_site` output

**Files:**
- Create: `template.html.erb`
- Create: `assets/style.css`
- Modify: `build.rb` (append `render_sections`, `render_page`, `build`, and the run guard)
- Test: `test/build_test.rb` (append integration tests)

**Interfaces:**
- Consumes: `load_posts(dir)` and `parse_post(path)` from Task 1.
- Produces:
  - `render_sections(posts) -> String` — concatenated `<section>` blocks.
  - `render_page(posts, template_path) -> String` — full HTML page; the ERB template sees a local variable `sections`.
  - `build(posts_dir:, template:, assets:, out_dir:) -> Integer` — writes `<out_dir>/index.html`, copies `<assets>` to `<out_dir>/assets`, returns post count. All four keyword args have defaults pointing at the repo's real paths.

- [ ] **Step 1: Write the failing integration tests**

Append these tests inside the `BuildTest` class in `test/build_test.rb` (before the final `end`):

```ruby
  def test_render_sections_uses_slug_anchor_and_title
    write("2024-foo.md", "---\ntitle: ようこそ\ndate: 2024-01-02\n---\n\n本文\n")
    posts = load_posts(@dir)
    html = render_sections(posts)
    assert_includes html, %(<h2 id="2024-foo">ようこそ</h2>)
    assert_includes html, "本文"
  end

  def test_build_writes_site_and_copies_assets
    write("2024-foo.md", "---\ntitle: Post\ndate: 2024-01-02\n---\n\nbody\n")
    template = File.join(@dir, "tpl.html.erb")
    File.write(template, "<main><article><%= sections %></article></main>")
    assets = File.join(@dir, "assets_src")
    FileUtils.mkdir_p(assets)
    File.write(File.join(assets, "style.css"), "main{}")
    out = File.join(@dir, "out")

    count = build(posts_dir: @dir, template: template, assets: assets, out_dir: out)

    assert_equal 1, count
    index = File.read(File.join(out, "index.html"))
    assert_includes index, %(<h2 id="2024-foo">Post</h2>)
    assert_path_exists File.join(out, "assets", "style.css")
  end
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `ruby -Itest test/build_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'render_sections'`.

- [ ] **Step 3: Extend build.rb with rendering and build**

Append to `build.rb`:

```ruby
require "erb"
require "fileutils"

ROOT      = __dir__
POSTS_DIR = File.join(ROOT, "posts")
TEMPLATE  = File.join(ROOT, "template.html.erb")
ASSETS    = File.join(ROOT, "assets")
OUT_DIR   = File.join(ROOT, "_site")

def render_sections(posts)
  posts.map do |p|
    %(<section>\n<h2 id="#{p[:slug]}">#{p[:title]}</h2>\n#{p[:body_html]}</section>)
  end.join("\n")
end

def render_page(posts, template_path)
  sections = render_sections(posts)
  ERB.new(File.read(template_path), trim_mode: "-").result(binding)
end

def build(posts_dir: POSTS_DIR, template: TEMPLATE, assets: ASSETS, out_dir: OUT_DIR)
  posts = load_posts(posts_dir)
  FileUtils.mkdir_p(out_dir)
  File.write(File.join(out_dir, "index.html"), render_page(posts, template))
  if Dir.exist?(assets)
    FileUtils.rm_rf(File.join(out_dir, "assets"))
    FileUtils.cp_r(assets, File.join(out_dir, "assets"))
  end
  posts.size
end

if __FILE__ == $PROGRAM_NAME
  n = build
  puts "Built #{n} posts into #{OUT_DIR}"
end
```

- [ ] **Step 4: Create the ERB template**

Create `template.html.erb`:

```erb
<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>blog.inutano.com</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Source+Code+Pro">
<link rel="stylesheet" href="assets/style.css">
<script async src="https://www.googletagmanager.com/gtag/js?id=G-7TNHDTZMES"></script>
<script>
window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());
gtag('config', 'G-7TNHDTZMES');
</script>
</head>
<body>
<main>
<header>
<a href="https://blog.inutano.com"><h1 class="blogTitle">blog.inutano.com</h1></a>
</header>
<article>
<%= sections %>
</article>
</main>
</body>
</html>
```

- [ ] **Step 5: Create the CSS (hand-compiled from src/pages/styles.sass)**

Create `assets/style.css`:

```css
h1.blogTitle {
  color: #999999;
  margin-top: 0;
  margin-bottom: 3em;
}

h2 {
  font-size: 200%;
}

h3 {
  font-size: 150%;
  padding-top: 3em;
}

section {
  padding-bottom: 6em;
  margin-bottom: 48px;
  line-height: 1.75;
}

main {
  color: #555;
  text-decoration: none;
  padding: 1em;
  font-size: 86%;
  font-family: 'Source Code Pro', 'Helvetica Neue', Helvetica, Arial, 'Hiragino Kaku Gothic ProN', 'ヒラギノ角ゴ ProN W3', メイリオ, Meiryo, sans-serif;
  max-width: 640px;
}

@media (min-width: 960px) {
  main {
    padding: 7em;
  }
}

a {
  color: #369ecf;
  text-decoration: none;
}

img {
  max-width: 100%;
}

blockquote {
  margin: 1.5em 3em;
  padding: 5px 20px;
  border-left: 2px solid #aaa;
  color: #777;
}

.codeStyles {
  color: #8A6534;
  padding: 4px;
  background-color: #FFF4DB;
  font-size: 1.25rem;
  border-radius: 4px;
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `ruby -Itest test/build_test.rb`
Expected: PASS — 9 runs, 0 failures, 0 errors.

- [ ] **Step 7: Commit**

```bash
git add build.rb template.html.erb assets/style.css test/build_test.rb
git commit -m "feat: render full page and write _site output"
```

---

### Task 3: Migrate existing posts and add a template post

**Files:**
- Create: `posts/2020-bestbuy.md` … `posts/2025-bestbuy.md` (via `git mv` from `blog/<slug>/index.mdx`)
- Create: `posts/_template.md`
- Delete: the `blog/` directory tree

**Interfaces:**
- Consumes: `build()` from Task 2.
- Produces: real content under `posts/`. No new code.

- [ ] **Step 1: Move the five tracked posts and the untracked 2025 draft**

```bash
for y in 2020 2021 2022 2023 2024; do
  git mv "blog/${y}-bestbuy/index.mdx" "posts/${y}-bestbuy.md"
done
mkdir -p posts
mv blog/2025-bestbuy/index.mdx posts/2025-bestbuy.md
rm -rf blog
```

- [ ] **Step 2: Rename the frontmatter key `datePublished` → `date` in every migrated post**

For each file `posts/2020-bestbuy.md` … `posts/2025-bestbuy.md`, change the frontmatter line `datePublished: <value>` to `date: <value>`, leaving the date value unchanged. Verify none remain:

Run: `grep -rl 'datePublished' posts/ || echo "none remaining"`
Expected: `none remaining`

- [ ] **Step 3: Wrap bare standalone URLs in `posts/2025-bestbuy.md`**

The 2025 draft has lines that are a bare URL on their own (e.g. `https://amzn.to/4pnUTIC`, `https://tokyobike.com/product/tokyobike-calin/`, `https://amzn.to/4soQfwO`). kramdown does not autolink these. Wrap each bare URL line as an anchor matching the existing affiliate-link style, e.g.:

```html
<a target="_blank" href="https://amzn.to/4pnUTIC">充電式洗浄機（マキタ）</a>
```

Use the nearby `###` heading text as the link label. Confirm none remain:

Run: `grep -nE '^https?://' posts/2025-bestbuy.md || echo "no bare urls"`
Expected: `no bare urls`

- [ ] **Step 4: Create the generic template post**

Create `posts/_template.md`:

```markdown
---
title: 記事のタイトル
date: 2026-06-27
---

ここに本文を Markdown で書く。

### 見出し

段落。リンクは <a href="https://example.com" target="_blank">このように</a> 書ける。
```

- [ ] **Step 5: Build and verify every post appears, newest first**

Run:
```bash
ruby build.rb
grep -c '<section>' _site/index.html
grep -o 'id="20[0-9][0-9]-bestbuy"' _site/index.html
```
Expected: `Built 6 posts into …`; section count `6`; the six ids printed, and in the file `2025-bestbuy` appears before `2020-bestbuy` (sorted desc). The `_template` post must NOT appear.

- [ ] **Step 6: Spot-check rendering in a browser**

Run: `open _site/index.html`
Confirm: gray `blog.inutano.com` title, posts in one stream newest-first, affiliate links present, no raw `<section>`/markup leaking as text. (`_site/` is gitignored — nothing to stage from it.)

- [ ] **Step 7: Commit**

```bash
git add posts
git commit -m "feat: migrate posts to posts/*.md and add _template.md"
```

---

### Task 4: CI deploy, Gatsby removal, and README

**Files:**
- Create/replace: `.github/workflows/publish.yml`
- Delete: `gatsby-config.ts`, `src/`, `package.json`, `yarn.lock`, `tsconfig.json`
- Create/replace: `README.md`

**Interfaces:**
- Consumes: `build.rb`, `Gemfile`, `posts/`, `assets/`, `template.html.erb` from earlier tasks.
- Produces: a publishing pipeline and human-facing docs. No new code.

- [ ] **Step 1: Replace the workflow with a Ruby build + official Pages deploy**

Overwrite `.github/workflows/publish.yml`:

```yaml
name: Build and deploy

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: "3.2"
          bundler-cache: true
      - run: bundle exec ruby build.rb
      - uses: actions/upload-pages-artifact@v3
        with:
          path: _site

  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

- [ ] **Step 2: Move CNAME into the published output**

GitHub's Pages artifact publishes only `_site/`, so the custom domain `CNAME` must be inside it. Copy it into `assets`' sibling by having the build include it: place `CNAME` at the repo root (it already is) and add this line to `build()` in `build.rb`, just before `posts.size`:

```ruby
  cname = File.join(ROOT, "CNAME")
  FileUtils.cp(cname, File.join(out_dir, "CNAME")) if File.exist?(cname)
```

Then rebuild and confirm:

Run: `ruby build.rb && cat _site/CNAME`
Expected: `blog.inutano.com`

- [ ] **Step 3: Guard the CNAME copy with a test**

Append to `test/build_test.rb` inside `BuildTest` (the `build` helper takes explicit paths, so point it at a fixture root that has a CNAME). Add:

```ruby
  def test_build_copies_cname_when_present
    write("2024-foo.md", "---\ntitle: Post\ndate: 2024-01-02\n---\n\nbody\n")
    template = File.join(@dir, "tpl.html.erb")
    File.write(template, "<%= sections %>")
    out = File.join(@dir, "out")
    # build() reads CNAME from ROOT (repo root), which contains the real CNAME.
    build(posts_dir: @dir, template: template, assets: File.join(@dir, "noassets"), out_dir: out)
    assert_equal "blog.inutano.com", File.read(File.join(out, "CNAME")).strip
  end
```

Run: `ruby -Itest test/build_test.rb`
Expected: PASS — 10 runs, 0 failures, 0 errors.

- [ ] **Step 4: Delete the Gatsby files**

```bash
git rm -r gatsby-config.ts src package.json yarn.lock tsconfig.json
```

Run: `ruby build.rb` (ensure the build still works with Gatsby gone)
Expected: `Built 6 posts into …`, no errors.

- [ ] **Step 5: Rewrite README.md as posting instructions**

Overwrite `README.md`:

```markdown
# blog.inutano.com

A zen single-page blog generated by one Ruby script.

## How to post

1. `cp posts/_template.md posts/2026-06-27-my-post.md`
2. Edit the file: set `title` and `date` (`YYYY-MM-DD`), write the body in Markdown.
   Inline HTML (e.g. `<a target="_blank" href="...">`) is allowed.
3. `git add posts && git commit -m "new post" && git push`

Pushing to `main` runs `.github/workflows/publish.yml`, which builds the site and
deploys it to GitHub Pages automatically.

## Preview locally

```
bundle install      # once
ruby build.rb
open _site/index.html
```

## How it works

- `posts/*.md` — one post per file. Files starting with `_` are ignored.
- `build.rb` — parses frontmatter, renders Markdown with kramdown, sorts by `date`
  descending, and writes `_site/index.html` plus `assets/` and `CNAME`.
- `template.html.erb` — the page shell (head, fonts, analytics, title).
- `assets/style.css` — styling.

## One-time setup

In the repo's GitHub **Settings → Pages**, set **Source** to **GitHub Actions**.

## Test

```
ruby -Itest test/build_test.rb
```
```

- [ ] **Step 6: Final build and test run**

Run:
```bash
ruby -Itest test/build_test.rb
ruby build.rb
```
Expected: tests PASS (10 runs); `Built 6 posts into …`.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: Ruby Pages workflow, remove Gatsby, rewrite README"
```

- [ ] **Step 8: Post-merge manual step (note for the user)**

After this lands on `main`: in GitHub **Settings → Pages**, switch **Source** to **GitHub Actions** (was "Deploy from a branch / gh-pages"). The old `gh-pages` branch can then be deleted. This cannot be done from code and must be done once in the GitHub UI.

---

## Notes for the implementer

- Run every `ruby -Itest test/build_test.rb` from the repo root.
- The kramdown default parser is intentional: it passes raw inline/block HTML through and, with `auto_ids: false`, does not add ids to headings — matching the old output.
- Do not commit `_site/`; it is gitignored and rebuilt by CI.

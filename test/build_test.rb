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

  def test_non_iso_date_raises
    path = write("f.md", "---\ntitle: T\ndate: 2024/01/02\n---\n\nbody\n")
    err = assert_raises(RuntimeError) { parse_post(path) }
    assert_match(/date/, err.message)
  end

  def test_empty_title_raises
    path = write("g.md", "---\ntitle:\ndate: 2024-01-01\n---\n\nbody\n")
    err = assert_raises(RuntimeError) { parse_post(path) }
    assert_match(/missing 'title'/, err.message)
  end

  def test_empty_date_raises
    path = write("h.md", "---\ntitle: T\ndate:\n---\n\nbody\n")
    err = assert_raises(RuntimeError) { parse_post(path) }
    assert_match(/missing 'date'/, err.message)
  end

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

  def test_build_copies_cname_when_present
    write("2024-foo.md", "---\ntitle: Post\ndate: 2024-01-02\n---\n\nbody\n")
    template = File.join(@dir, "tpl.html.erb")
    File.write(template, "<%= sections %>")
    out = File.join(@dir, "out")
    # build() reads CNAME from ROOT (repo root), which contains the real CNAME.
    build(posts_dir: @dir, template: template, assets: File.join(@dir, "noassets"), out_dir: out)
    assert_equal "blog.inutano.com", File.read(File.join(out, "CNAME")).strip
  end
end

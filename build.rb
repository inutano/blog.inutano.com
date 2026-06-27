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
    date = Date.strptime(date_str, "%Y-%m-%d")
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

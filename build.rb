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

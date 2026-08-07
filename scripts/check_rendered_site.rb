#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "uri"

ROOT = File.expand_path("..", __dir__)
PUBLIC_DIR = File.join(ROOT, "public")
SITE_HOST = "www.danielpfurtscheller.com"

def relative_path(path)
  path.delete_prefix("#{ROOT}/")
end

def page_url_path(path)
  relative = path.delete_prefix("#{PUBLIC_DIR}/")
  return "/" if relative == "index.html"

  "/#{relative.sub(%r{/index\.html\z}, "/")}"
end

def attributes(tag)
  tag.scan(/([:\w-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/).to_h do |name, double, single, bare|
    [name.downcase, CGI.unescapeHTML(double || single || bare || "")]
  end
end

def local_target(value)
  uri = URI.parse(value)
  return nil if uri.scheme && !%w[http https].include?(uri.scheme)
  return nil if uri.host && uri.host != SITE_HOST

  [CGI.unescape(uri.path.to_s), uri.fragment]
rescue URI::InvalidURIError
  nil
end

def existing_target?(path)
  path = "/" if path.empty?
  clean_path = path.sub(%r{\A/}, "")
  candidates = [File.join(PUBLIC_DIR, clean_path)]
  candidates << File.join(PUBLIC_DIR, clean_path, "index.html") if File.extname(clean_path).empty?
  candidates.any? { |candidate| File.file?(candidate) }
end

errors = []
html_files = Dir[File.join(PUBLIC_DIR, "**", "*.html")]

html_files.each do |path|
  html = File.read(path, encoding: "UTF-8")
  label = relative_path(path)
  tags = html.scan(/<[^!][^>]*>/)
  ids = Hash.new(0)
  redirect = html.match?(/<meta\b[^>]*http-equiv\s*=\s*["']?refresh\b/i)

  errors << "#{label}: contains a local filesystem path" if html.match?(%r{(?:file://|/(?:Users|home)/|[A-Za-z]:\\Users\\)}i)
  errors << "#{label}: exposes a BibTeX file field" if html.match?(/\bfile\s*=\s*\{/i)
  errors << "#{label}: contains a serialized non-breaking-space entity" if html.include?("&amp;nbsp;")
  errors << "#{label}: expected exactly one h1" if !redirect && html.scan(/<h1\b/i).length != 1

  tags.each do |tag|
    attrs = attributes(tag)
    ids[attrs["id"]] += 1 if attrs.key?("id")

    if tag.match?(/\A<img\b/i) && !attrs.key?("alt")
      errors << "#{label}: image is missing an alt attribute"
    end

    %w[href src].each do |attribute|
      next unless attrs.key?(attribute)

      value = attrs[attribute]
      next if value.empty? || value.start_with?("mailto:", "tel:", "data:")

      target = local_target(value)
      next unless target

      target_path, fragment = target
      target_path = page_url_path(path) if target_path.empty?
      errors << "#{label}: missing local target #{value}" unless existing_target?(target_path)

      next if fragment.nil? || fragment.empty?

      destination = if target_path == page_url_path(path)
                      html
                    else
                      clean_path = target_path.sub(%r{\A/}, "")
                      destination_path = File.extname(clean_path).empty? ?
                        File.join(PUBLIC_DIR, clean_path, "index.html") : File.join(PUBLIC_DIR, clean_path)
                      File.file?(destination_path) ? File.read(destination_path, encoding: "UTF-8") : ""
                    end
      destination_ids = destination.scan(/\bid\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i)
                                   .map { |match| CGI.unescapeHTML(match.compact.first) }
      errors << "#{label}: missing fragment target #{value}" unless destination_ids.include?(fragment)
    end
  end

  ids.select { |_id, count| count > 1 }.each_key do |id|
    errors << "#{label}: duplicate id #{id.inspect}"
  end
end

home_path = File.join(PUBLIC_DIR, "index.html")
if File.file?(home_path)
  home = File.read(home_path, encoding: "UTF-8")
  hero_media = home[/<div\b[^>]*\bphoto-hero-media\b[^>]*>(.*?)<\/div>/mi, 1]
  if hero_media
    hero_images = hero_media.scan(/<img\b[^>]*>/i).map { |tag| attributes(tag) }
    real_sources = hero_images.filter_map { |attrs| attrs["src"] unless attrs["src"].to_s.start_with?("data:") }
    errors << "public/index.html: mobile hero should load exactly one real image" unless real_sources.length == 1
    errors << "public/index.html: first hero image must use fetchpriority=high" unless hero_images.first&.fetch("fetchpriority", nil) == "high"

    hero_media.scan(/<source\b[^>]*>/i).each do |tag|
      attrs = attributes(tag)
      errors << "public/index.html: slideshow source is not restricted to desktop" unless attrs["media"] == "(min-width: 721px)"
    end
  else
    errors << "public/index.html: photo hero media is missing"
  end

  footer_portrait = home.scan(/<img\b[^>]*>/i)
                        .map { |tag| attributes(tag) }
                        .find { |attrs| attrs.fetch("class", "").split.include?("footer-portrait") }
  errors << "public/index.html: footer portrait must be lazy-loaded" unless footer_portrait&.fetch("loading", nil) == "lazy"
  errors << "public/index.html: footer portrait needs its compact responsive source" unless footer_portrait&.fetch("srcset", "")&.include?("daniel-photo-360.webp 360w")
end

css_files = Dir[File.join(PUBLIC_DIR, "css", "site*.css")]
if css_files.empty?
  errors << "public/css: compiled site stylesheet is missing"
else
  css = css_files.map { |path| File.read(path, encoding: "UTF-8") }.join
  errors << "public/css: webfonts must use WOFF2" unless css.include?(".woff2") && !css.include?(".ttf")
end

rss_path = File.join(PUBLIC_DIR, "publications", "index.xml")
if File.file?(rss_path)
  rss = File.read(rss_path, encoding: "UTF-8")
  rss_items = rss.scan(/<item>(.*?)<\/item>/m)
  expected_items = Dir[File.join(ROOT, "content", "publications", "*.md")]
                   .count { |path| File.basename(path) != "_index.md" }
  if rss_items.length != expected_items
    errors << "#{relative_path(rss_path)}: expected #{expected_items} items, found #{rss_items.length}"
  end
  rss_items.each_with_index do |match, index|
    item = match.first
    if item.match?(/<description\s*\/>/) || item.match?(/<description>\s*<\/description>/)
      errors << "#{relative_path(rss_path)}: item #{index + 1} has an empty description"
    end
  end
  errors << "#{relative_path(rss_path)}: contains a local filesystem path" if rss.match?(%r{(?:file://|/(?:Users|home)/|[A-Za-z]:\\Users\\)}i)
else
  errors << "public/publications/index.xml: publication RSS feed is missing"
end

if errors.any?
  warn "Rendered-site check failed:"
  errors.uniq.each { |error| warn "- #{error}" }
  exit 1
end

puts "Rendered-site check passed (#{html_files.length} HTML files)."

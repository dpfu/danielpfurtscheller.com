#!/usr/bin/env ruby
# frozen_string_literal: true

ROOT = File.expand_path("..", __dir__)
PUBLIC_DIR = File.join(ROOT, "public")

checks = {
  "script element" => /<script\b/i,
  "inline event handler" => /\son[a-z]+\s*=/i,
  "javascript URL" => /\b(?:href|src)\s*=\s*["']?\s*javascript:/i
}.freeze

errors = []
html_files = Dir[File.join(PUBLIC_DIR, "**", "*.html")]

html_files.each do |path|
  html = File.read(path, encoding: "UTF-8")
  checks.each do |label, pattern|
    errors << "#{path.delete_prefix("#{ROOT}/")}: contains #{label}" if html.match?(pattern)
  end
end

Dir[File.join(PUBLIC_DIR, "**", "*.js")].each do |path|
  errors << "#{path.delete_prefix("#{ROOT}/")}: JavaScript asset was generated"
end

if errors.any?
  warn "No-JavaScript check failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "No-JavaScript check passed (#{html_files.length} HTML files)."

#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "uri"
require "yaml"

ROOT = File.expand_path("..", __dir__)
KNOWN_OPEN_ACCESS_STATUSES = %w[gold hybrid green bronze open closed unknown].freeze

def frontmatter_for(path)
  text = File.read(path, encoding: "UTF-8")
  match = text.match(/\A---\s*\n(.*?)\n---\s*\n?/m)
  raise "missing YAML frontmatter" unless match

  safe_load_yaml(match[1])
end

def safe_load_yaml(text)
  YAML.safe_load(text, permitted_classes: [Date, Time], aliases: true) || {}
rescue ArgumentError
  YAML.safe_load(text, [Date, Time], [], true) || {}
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def relative_path(path)
  path.delete_prefix("#{ROOT}/")
end

def add_error(errors, path, message)
  errors << "#{relative_path(path)}: #{message}"
end

def require_field(errors, path, data, key)
  add_error(errors, path, "missing #{key}") if blank?(data[key])
end

def require_array(errors, path, data, key)
  value = data[key]
  return if value.is_a?(Array) && value.any? { |item| !blank?(item) }

  add_error(errors, path, "#{key} must be a non-empty list")
end

def valid_date?(value)
  return true if value.is_a?(Date) || value.is_a?(Time)

  Date.parse(value.to_s)
  true
rescue ArgumentError
  false
end

def validate_date(errors, path, data)
  return add_error(errors, path, "missing date") if blank?(data["date"])

  add_error(errors, path, "date is not parseable") unless valid_date?(data["date"])
end

def validate_year(errors, path, data)
  return add_error(errors, path, "missing year") if blank?(data["year"])

  add_error(errors, path, "year must be four digits") unless data["year"].to_s.match?(/\A\d{4}\z/)
end

def validate_links(errors, path, links)
  return if links.nil?

  unless links.is_a?(Array)
    add_error(errors, path, "links must be a list")
    return
  end

  links.each_with_index do |link, index|
    unless link.is_a?(Hash)
      add_error(errors, path, "links[#{index}] must be a map")
      next
    end

    add_error(errors, path, "links[#{index}].label is missing") if blank?(link["label"])
    url = link["url"]
    if blank?(url)
      add_error(errors, path, "links[#{index}].url is missing")
    elsif !url.to_s.match?(/\A(https?:\/\/|mailto:|\/)/)
      add_error(errors, path, "links[#{index}].url must be absolute, root-relative, or mailto")
    end
  end
end

def validate_open_access(errors, path, data)
  open_access = data["open_access"]
  return if open_access.nil?

  unless open_access.is_a?(Hash)
    add_error(errors, path, "open_access must be a map")
    return
  end

  status = open_access["status"] || open_access["oa_status"]
  return if blank?(status)

  unless KNOWN_OPEN_ACCESS_STATUSES.include?(status.to_s.downcase)
    add_error(errors, path, "open_access.status has unknown value #{status.inspect}")
  end
end

def validate_citation_formats(errors, path, data)
  formats = data["citation_formats"]
  return if formats.nil?

  add_error(errors, path, "citation_formats must be a map") unless formats.is_a?(Hash)
end

def validate_publication(errors, path, data)
  require_field(errors, path, data, "title")
  validate_date(errors, path, data)
  validate_year(errors, path, data)
  require_array(errors, path, data, "authors")
  add_error(errors, path, "missing display_type or entry_type") if blank?(data["display_type"]) && blank?(data["entry_type"])
  add_error(errors, path, "missing source or citation") if blank?(data["source"]) && blank?(data["citation"])
  validate_links(errors, path, data["links"])
  validate_open_access(errors, path, data)
  validate_citation_formats(errors, path, data)
end

def validate_talk(errors, path, data)
  require_field(errors, path, data, "title")
  validate_date(errors, path, data)
  validate_year(errors, path, data)
  require_field(errors, path, data, "entry_type")
  require_field(errors, path, data, "event")
  require_field(errors, path, data, "place")
  require_array(errors, path, data, "speakers")
  validate_links(errors, path, data["links"])
end

def validate_post(errors, path, data)
  require_field(errors, path, data, "title")
  require_field(errors, path, data, "description")
  validate_date(errors, path, data)
end

def content_files(section)
  Dir[File.join(ROOT, "content", section, "*.md")].reject do |path|
    File.basename(path) == "_index.md"
  end
end

errors = []
checked = 0

{
  "publications" => method(:validate_publication),
  "talks" => method(:validate_talk),
  "posts" => method(:validate_post)
}.each do |section, validator|
  content_files(section).each do |path|
    checked += 1
    data = frontmatter_for(path)
    validator.call(errors, path, data)
  rescue StandardError => error
    add_error(errors, path, error.message)
  end
end

if errors.any?
  warn "Content check failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "Content check passed (#{checked} files)."

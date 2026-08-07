#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "uri"
require "yaml"

ROOT = File.expand_path("..", __dir__)
KNOWN_OPEN_ACCESS_STATUSES = %w[gold hybrid green bronze open closed unknown].freeze
LOCAL_PATH_PATTERN = %r!(?:file://|(?:\A|[\s:{=(])/(?:Users|home)/|[A-Za-z]:\\Users\\)!i
HTML_ENTITY_PATTERN = /&(?:#\d+|#x[0-9a-f]+|[a-z]+);/i

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

def validate_date_year_match(errors, path, data)
  return if blank?(data["date"]) || blank?(data["year"])

  date = Date.parse(data["date"].to_s)
  add_error(errors, path, "date year does not match year") unless date.year == data["year"].to_i
rescue ArgumentError
  nil
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

  seen_urls = {}

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
    elsif seen_urls.key?(url.to_s)
      add_error(errors, path, "links[#{index}].url duplicates links[#{seen_urls[url.to_s]}].url")
    else
      seen_urls[url.to_s] = index
    end
  end
end

def each_string(value, prefix = [], &block)
  case value
  when Hash
    value.each { |key, item| each_string(item, prefix + [key], &block) }
  when Array
    value.each_with_index { |item, index| each_string(item, prefix + [index], &block) }
  when String
    yield value, prefix
  end
end

def validate_public_values(errors, path, data)
  each_string(data) do |value, keys|
    location = keys.join(".")
    add_error(errors, path, "#{location} contains a local filesystem path") if value.match?(LOCAL_PATH_PATTERN)
    add_error(errors, path, "#{location} contains an HTML entity") if value.match?(HTML_ENTITY_PATTERN)
  end
end

def page_range(value, source: false)
  pattern = source ? /\bS\.\s*(\d+)\s*[–-]\s*(\d+)/ : /^\s*pages\s*=\s*\{(\d+)\s*--?\s*(\d+)\}/i
  match = value.to_s.match(pattern)
  match && match.captures.map(&:to_i)
end

def validate_page_ranges(errors, path, data, bibtex)
  source_range = page_range(data["source"], source: true)
  bibtex_range = page_range(bibtex)
  return unless source_range && bibtex_range && source_range != bibtex_range

  add_error(errors, path, "source page range does not match citation_formats.bibtex")
end

def require_in_text(errors, path, data, container_key, value_key)
  container = data[container_key].to_s
  value = data[value_key].to_s
  return if container.empty? || value.empty? || container.include?(value)

  add_error(errors, path, "#{container_key} does not contain #{value_key}")
end

def validate_publication_texts(errors, path, data)
  require_in_text(errors, path, data, "description", "title")
  require_in_text(errors, path, data, "citation", "title")
  require_in_text(errors, path, data, "citation", "source")
end

def validate_talk_texts(errors, path, data)
  require_in_text(errors, path, data, "description", "title")
  %w[title event place].each { |key| require_in_text(errors, path, data, "citation", key) }
  return if blank?(data["citation"]) || blank?(data["date"])

  formatted_date = Date.parse(data["date"].to_s).strftime("%d.%m.%Y")
  add_error(errors, path, "citation does not contain formatted date") unless data["citation"].include?(formatted_date)
rescue ArgumentError
  nil
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

  unless formats.is_a?(Hash)
    add_error(errors, path, "citation_formats must be a map")
    return
  end

  bibtex = formats["bibtex"]
  return if blank?(bibtex)

  if bibtex.to_s.match?(/^\s*file\s*=/i)
    add_error(errors, path, "citation_formats.bibtex must not contain a local file field")
  end

  if bibtex.to_s.match?(%r{(?:file://|/(?:Users|home)/|[A-Za-z]:\\Users\\)}i)
    add_error(errors, path, "citation_formats.bibtex contains a local filesystem path")
  end

  %w[apa7 unified_style_linguistics].each do |format|
    value = formats[format].to_s
    add_error(errors, path, "citation_formats.#{format} contains a LaTeX escape") if value.include?("\\")
  end

  validate_page_ranges(errors, path, data, bibtex)

  expected_year = data["year"].to_i
  citation_years = {
    "apa7" => formats["apa7"].to_s[/\((\d{4})\)/, 1],
    "bibtex" => bibtex.to_s[/^\s*year\s*=\s*\{?(\d{4})/i, 1],
    "unified_style_linguistics" => formats["unified_style_linguistics"].to_s[/\.\s*(\d{4})\./, 1]
  }
  citation_years.each do |format, year|
    next if year.nil? || year.to_i == expected_year

    add_error(errors, path, "citation_formats.#{format} year does not match year")
  end
end

def validate_publication(errors, path, data)
  require_field(errors, path, data, "title")
  require_field(errors, path, data, "description")
  validate_date(errors, path, data)
  validate_year(errors, path, data)
  validate_date_year_match(errors, path, data)
  require_array(errors, path, data, "authors")
  add_error(errors, path, "missing display_type or entry_type") if blank?(data["display_type"]) && blank?(data["entry_type"])
  add_error(errors, path, "missing source or citation") if blank?(data["source"]) && blank?(data["citation"])
  validate_links(errors, path, data["links"])
  validate_open_access(errors, path, data)
  validate_citation_formats(errors, path, data)
  validate_public_values(errors, path, data)
  validate_publication_texts(errors, path, data)
end

def validate_talk(errors, path, data)
  require_field(errors, path, data, "title")
  require_field(errors, path, data, "description")
  validate_date(errors, path, data)
  validate_year(errors, path, data)
  validate_date_year_match(errors, path, data)
  require_field(errors, path, data, "entry_type")
  require_field(errors, path, data, "event")
  require_field(errors, path, data, "place")
  require_array(errors, path, data, "speakers")
  validate_links(errors, path, data["links"])
  validate_public_values(errors, path, data)
  validate_talk_texts(errors, path, data)
end

def content_files(section)
  Dir[File.join(ROOT, "content", section, "*.md")].reject do |path|
    File.basename(path) == "_index.md"
  end
end

def validate_highlights(errors)
  path = File.join(ROOT, "data", "highlights.yaml")
  data = safe_load_yaml(File.read(path, encoding: "UTF-8"))
  titles = {}

  {
    "working_papers" => %w[title authors affiliation note],
    "upcoming_talks" => %w[title date note]
  }.each do |section, fields|
    items = data[section]
    unless items.is_a?(Array)
      add_error(errors, path, "#{section} must be a list")
      next
    end

    items.each_with_index do |item, index|
      unless item.is_a?(Hash)
        add_error(errors, path, "#{section}[#{index}] must be a map")
        next
      end

      fields.each do |field|
        add_error(errors, path, "#{section}[#{index}].#{field} is missing") if blank?(item[field])
      end
      title = item["title"].to_s.strip.downcase
      if !title.empty? && titles.key?(title)
        add_error(errors, path, "#{section}[#{index}].title duplicates #{titles[title]}")
      else
        titles[title] = "#{section}[#{index}].title" unless title.empty?
      end
      if item.key?("doi") && !item["doi"].to_s.match?(/\A10\.\d{4,9}\/\S+\z/)
        add_error(errors, path, "#{section}[#{index}].doi is invalid")
      end
    end
  end

  validate_public_values(errors, path, data)
rescue StandardError => error
  add_error(errors, path, error.message)
end

errors = []
checked = 0

{
  "publications" => method(:validate_publication),
  "talks" => method(:validate_talk)
}.each do |section, validator|
  content_files(section).each do |path|
    checked += 1
    data = frontmatter_for(path)
    validator.call(errors, path, data)
  rescue StandardError => error
    add_error(errors, path, error.message)
  end
end

validate_highlights(errors)

if errors.any?
  warn "Content check failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end

puts "Content check passed (#{checked} records plus homepage highlights)."

#!/usr/bin/env ruby
# frozen_string_literal: true

require "cgi"
require "date"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "optparse"
require "set"
require "time"
require "uri"
require "yaml"

BASE_URL = ENV.fetch("ZOTERO_LOCAL_BASE_URL", "http://127.0.0.1:23119")
API_HEADERS = { "Zotero-API-Version" => "3" }.freeze
DEFAULT_CONTENT_DIR = "content/publications"
DEFAULT_PROBE = "scripts/zotero_publication_probe.py"
DEFAULT_PYTHON = "/Users/daniel/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"

options = {
  apply: false,
  content_dir: DEFAULT_CONTENT_DIR,
  report: nil,
  probe: DEFAULT_PROBE,
  python: File.executable?(DEFAULT_PYTHON) ? DEFAULT_PYTHON : "python3",
  pdf_pages: 4
}

OptionParser.new do |parser|
  parser.banner = "Usage: ruby scripts/enrich_publications_from_zotero.rb [--apply]"
  parser.on("--apply", "Write enriched publication frontmatter") { options[:apply] = true }
  parser.on("--content-dir PATH", "Publication content directory") { |value| options[:content_dir] = value }
  parser.on("--report PATH", "Write JSON report") { |value| options[:report] = value }
  parser.on("--probe PATH", "Probe script path") { |value| options[:probe] = value }
  parser.on("--python PATH", "Python executable for PDF fallback") { |value| options[:python] = value }
  parser.on("--pdf-pages N", Integer, "PDF pages to inspect for summary basis") { |value| options[:pdf_pages] = value }
end.parse!

def http_get(path)
  uri = URI(BASE_URL + path)
  request = Net::HTTP::Get.new(uri)
  API_HEADERS.each { |key, value| request[key] = value }
  Net::HTTP.start(uri.hostname, uri.port, read_timeout: 8, open_timeout: 3) do |http|
    http.request(request)
  end
end

def utf8_body(response)
  response.body.to_s.dup.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace)
end

def json_get(path)
  response = http_get(path)
  return [nil, response] unless response.is_a?(Net::HTTPSuccess)

  [JSON.parse(utf8_body(response)), response]
rescue JSON::ParserError
  [nil, response]
end

def text_get(path)
  response = http_get(path)
  [response.is_a?(Net::HTTPSuccess) ? utf8_body(response) : nil, response]
end

def split_frontmatter(text)
  match = text.match(/\A---\s*\n(.*?)\n---\s*\n?/m)
  raise "No YAML frontmatter found" unless match

  [match[1], match.post_match]
end

def load_frontmatter(path)
  frontmatter, body = split_frontmatter(File.read(path))
  data = YAML.safe_load(frontmatter, permitted_classes: [Date, Time], aliases: true) || {}
  [data, body]
end

def dump_frontmatter(data, body)
  yaml = YAML.dump(data)
  yaml = yaml.sub(/\A---\s*\n/, "")
  "---\n#{yaml}---\n#{body}"
end

def words(value)
  value.to_s.downcase.gsub(/[^[:alnum:]]+/, " ").split.select { |word| word.length > 2 }.to_set
end

def year_from(value)
  value.to_s[/\d{4}/]
end

def title_score(query_title, item)
  query_words = words(query_title)
  title_words = words(item.dig("data", "title") || item["title"])
  return 0.0 if query_words.empty? || title_words.empty?

  matched = (query_words & title_words).length
  [matched.to_f / query_words.length, matched.to_f / (query_words | title_words).length].max
end

def best_search_match(title, year)
  encoded = URI.encode_www_form("q" => title)
  items, response = json_get("/api/users/0/items/top?#{encoded}")
  return [nil, response, []] unless items.is_a?(Array)

  ranked = items.map do |item|
    score = title_score(title, item)
    item_year = year_from(item.dig("data", "date"))
    score += 0.08 if year && item_year == year.to_s
    [score, item]
  end.sort_by { |score, _item| -score }

  best_score, best_item = ranked.first
  return [nil, response, items] unless best_item && best_score >= 0.5

  [best_item, response, items]
end

def strip_csl_html(value)
  return nil if value.nil? || value.to_s.strip.empty?

  text = value.to_s.gsub(/<span\b[^>]*>.*?<\/span>/mi, "")
  text = text.gsub(/<[^>]+>/, " ")
  text = CGI.unescapeHTML(text.gsub(/\s+/, " ").strip)
  text.gsub(/\s+([,.;:])/, "\\1")
end

def clean_text(value)
  value.to_s
       .gsub(/\r/, "\n")
       .gsub(/([[:alpha:]])-\s+([[:lower:]])/, "\\1\\2")
       .gsub(/[ \t]+/, " ")
       .gsub(/\n{3,}/, "\n\n")
       .strip
end

def first_sentences(value, max_chars: 420, count: 2)
  text = clean_text(value)
  return nil if text.empty?

  text = text.gsub(/\A\d+\s+(Abstract|Zusammenfassung)\s*[:.]?\s*/i, "")
  text = text.gsub(/\A(Abstract|Zusammenfassung)\s*[:.]?\s*/i, "")
  parts = text.scan(/[^.!?]+[.!?]+|[^.!?]+\z/).map { |part| part.strip }.reject do |part|
    part.length < 35 || part.match?(/\A(doi|http|www)\b/i)
  end
  parts = [text] if parts.empty?
  summary = parts.first(count).join(" ")
  summary = "#{summary[0, max_chars - 1].sub(/\s+\S*\z/, "")}…" if summary.length > max_chars
  summary
end

def generic_abstract_placeholder?(value)
  text = clean_text(value)
  return true if text.include?("Die Seite hebt den Gegenstand knapp hervor")
  return true if text.include?("Die Seite bietet dafür eine schnelle Orientierung")
  return true if text.include?("Die Seite zeigt, worum es bei")
  return true if text.include?("Im Vordergrund stehen Gegenstand, Forschungszusammenhang, Zugriff und zitierfähige Angaben")

  false
end

def container_only_key?(data, item_data)
  return false unless item_data["itemType"] == "book"

  page_type = data["display_type"].to_s.downcase
  return false if page_type.include?("herausgabe")
  return false if page_type.include?("monographie")
  return false if page_type == "buch"

  true
end

def abstract_from_pdf_excerpt(excerpt)
  text = clean_text(excerpt)
  return nil unless text[0, 180].match?(/\b(Abstract|Zusammenfassung)\b/i)

  first_sentences(text, max_chars: 900, count: 4)
end

def weak_abstract?(value)
  text = clean_text(value)
  text.empty? || text.include?("…") || text.length < 180
end

def language_label(raw)
  value = raw.to_s.strip.downcase
  return nil if value.empty?
  return "Deutsch" if value.start_with?("de") || value == "ger" || value == "deu"
  return "English" if value.start_with?("en")

  raw.to_s
end

def normalize_doi(raw)
  raw.to_s.strip.sub(%r{\Ahttps?://(dx\.)?doi\.org/}i, "")
end

def merge_links(data, item_data)
  links = Array(data["links"]).map { |link| link.is_a?(Hash) ? link.dup : link }
  seen = links.each_with_object(Set.new) do |link, memo|
    memo << link["url"] if link.is_a?(Hash) && link["url"]
  end

  doi = normalize_doi(data["doi"] || item_data["DOI"])
  unless doi.empty?
    doi_url = "https://doi.org/#{doi}"
    unless seen.include?(doi_url)
      links << { "label" => "DOI", "url" => doi_url }
      seen << doi_url
    end
  end

  url = item_data["url"].to_s.strip
  if !url.empty? && !seen.include?(url)
    label = url.include?("doi.org") ? "DOI" : "Quelle"
    links << { "label" => label, "url" => url }
  end

  links
end

def probe_item(item_key, options)
  probe = options[:probe]
  return nil unless probe && File.exist?(probe)

  command = [
    options[:python],
    probe,
    "--item-key",
    item_key,
    "--pdf-pages",
    options[:pdf_pages].to_s,
    "--excerpt-chars",
    "8000"
  ]
  output, status = Open3.capture2e(*command)
  return nil unless status.success?

  JSON.parse(output)
rescue JSON::ParserError
  nil
end

def first_attachment_excerpt(probe)
  Array(probe && probe["attachments"]).each do |attachment|
    excerpt = clean_text(attachment["text_excerpt"])
    return [excerpt, attachment] unless excerpt.empty?
  end
  [nil, nil]
end

def first_attachment_abstract(probe)
  Array(probe && probe["attachments"]).each do |attachment|
    abstract = clean_text(attachment["abstract_candidate"])
    return [abstract, attachment] unless abstract.empty?
  end
  [nil, nil]
end

def update_publication(path, options)
  data, body = load_frontmatter(path)
  title = data["title"].to_s
  report = {
    "file" => path,
    "title" => title,
    "status" => "unchanged",
    "zotero_key_before" => data["zotero_key"],
    "zotero_key_after" => data["zotero_key"],
    "warnings" => []
  }

  item = nil
  item_response = nil
  item_key = data["zotero_key"].to_s.strip

  unless item_key.empty?
    item, item_response = json_get("/api/users/0/items/#{URI.encode_www_form_component(item_key)}?include=data,bib,citation&style=apa")
    unless item_response.is_a?(Net::HTTPSuccess)
      report["warnings"] << "stored zotero_key failed with status #{item_response&.code}"
      item = nil
    end
  end

  if item.nil?
    match, search_response, _matches = best_search_match(title, data["year"])
    if match
      item_key = match["key"]
      item, item_response = json_get("/api/users/0/items/#{URI.encode_www_form_component(item_key)}?include=data,bib,citation&style=apa")
      report["zotero_key_after"] = item_key
    else
      report["status"] = "no_zotero_match"
      report["warnings"] << "search failed or no matching Zotero item; status #{search_response&.code}"
    end
  else
    score = title_score(title, item)
    report["warnings"] << "stored Zotero title differs from page title" if score < 0.42
  end

  changed = false
  if item
    item_data = item["data"] || {}
    if container_only_key?(data, item_data)
      report["status"] = "container_key_only"
      report["warnings"] << "stored Zotero key points to a book/container, not this page-level publication"

      sources = ["Lokales Frontmatter", "Zotero Container #{item_key}"]
      if data["data_sources"] != sources
        data["data_sources"] = sources
        changed = true
      end

      if changed
        report["status"] = "#{report["status"]}_updated"
        File.write(path, dump_frontmatter(data, body)) if options[:apply]
      end
      report["changed"] = changed
      return report
    end

    usl, usl_response = json_get("/api/users/0/items/#{URI.encode_www_form_component(item_key)}?include=data,bib,citation&style=unified-style-sheet-for-linguistics")
    bibtex, bibtex_response = text_get("/api/users/0/items/#{URI.encode_www_form_component(item_key)}?format=bibtex")
    probe = probe_item(item_key, options)
    pdf_abstract, pdf_abstract_attachment = first_attachment_abstract(probe)
    pdf_excerpt, pdf_attachment = first_attachment_excerpt(probe)
    pdf_source_attachment = pdf_abstract_attachment || pdf_attachment

    report["status"] = "zotero_enriched"
    report["zotero_key_after"] = item_key
    report["doi"] = item_data["DOI"]
    report["abstract"] = !item_data["abstractNote"].to_s.strip.empty?
    report["bibtex"] = bibtex_response.is_a?(Net::HTTPSuccess)
    report["usl"] = usl_response.is_a?(Net::HTTPSuccess)
    report["pdf_excerpt"] = !pdf_excerpt.to_s.empty?
    report["pdf_abstract"] = !pdf_abstract.to_s.empty?
    report["pdf_attachment_key"] = pdf_source_attachment && pdf_source_attachment["key"]

    if data["zotero_key"] != item_key
      data["zotero_key"] = item_key
      changed = true
    end

    doi = normalize_doi(item_data["DOI"])
    if !doi.empty? && data["doi"] != doi
      data["doi"] = doi
      changed = true
    end

    language = language_label(item_data["language"])
    if language && data["language"].to_s.strip.empty?
      data["language"] = language
      changed = true
    end

    links = merge_links(data, item_data)
    if links != data["links"]
      data["links"] = links
      changed = true
    end

    zotero_abstract = clean_text(item_data["abstractNote"])
    abstract = zotero_abstract
    pdf_abstract = abstract_from_pdf_excerpt(pdf_excerpt) if pdf_abstract.to_s.empty?
    abstract_from_pdf = false
    abstract = pdf_abstract if pdf_abstract && weak_abstract?(abstract)
    abstract_from_pdf = abstract == pdf_abstract && !pdf_abstract.to_s.empty?
    existing_abstract = clean_text(data["abstract"])
    if !abstract.empty? &&
       data["abstract"] != abstract &&
       (existing_abstract.empty? || weak_abstract?(existing_abstract) || generic_abstract_placeholder?(existing_abstract))
      data["abstract"] = abstract
      changed = true
    end

    formats = (data["citation_formats"].is_a?(Hash) ? data["citation_formats"].dup : {})
    apa_text = strip_csl_html(item["bib"])
    usl_text = strip_csl_html(usl && usl["bib"])
    formats["apa7"] = apa_text if apa_text && !apa_text.empty?
    formats["bibtex"] = bibtex.strip if bibtex && !bibtex.strip.empty?
    formats["unified_style_linguistics"] = usl_text if usl_text && !usl_text.empty?
    if formats != data["citation_formats"]
      data["citation_formats"] = formats
      changed = true
    end

    sources = ["Lokales Frontmatter", "Zotero #{item_key}"]
    sources << "Zotero Abstract" unless zotero_abstract.empty? || weak_abstract?(zotero_abstract)
    sources << "Zotero PDF #{pdf_source_attachment["key"]}" if pdf_source_attachment && pdf_source_attachment["key"]
    if data["data_sources"] != sources
      data["data_sources"] = sources
      changed = true
    end
  else
    sources = Array(data["data_sources"]).dup
    sources = ["Lokales Frontmatter"] if sources.empty?
    sources << "Kein Zotero-Treffer" unless sources.include?("Kein Zotero-Treffer")
    if data["data_sources"] != sources
      data["data_sources"] = sources
      changed = true
    end
  end

  if changed
    report["status"] = "#{report["status"]}_updated"
    File.write(path, dump_frontmatter(data, body)) if options[:apply]
  end
  report["changed"] = changed
  report
rescue StandardError => e
  {
    "file" => path,
    "title" => nil,
    "status" => "error",
    "changed" => false,
    "warnings" => ["#{e.class}: #{e.message}"]
  }
end

paths = Dir[File.join(options[:content_dir], "*.md")].sort.reject { |path| File.basename(path) == "_index.md" }
report = {
  "applied" => options[:apply],
  "base_url" => BASE_URL,
  "generated_at" => Time.now.iso8601,
  "count" => paths.length,
  "items" => paths.map { |path| update_publication(path, options) }
}

summary = report["items"].each_with_object(Hash.new(0)) { |item, memo| memo[item["status"]] += 1 }
report["summary"] = summary

if options[:report]
  FileUtils.mkdir_p(File.dirname(options[:report]))
  File.write(options[:report], JSON.pretty_generate(report))
end

puts JSON.pretty_generate("summary" => summary, "report" => options[:report], "applied" => options[:apply])

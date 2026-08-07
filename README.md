# danielpfurtscheller.com

Personal academic website of Daniel Pfurtscheller: [danielpfurtscheller.com](https://www.danielpfurtscheller.com).

## Build

The site is built with Hugo. Content lives in `content/`, layouts in `layouts/`, pipeline CSS in `assets/css/`, static files in `static/`, and generated output in `public/`.

```sh
make
```

Run the local checks with:

```sh
make test
```

The test target validates curated frontmatter, builds Hugo with warnings treated
as failures, verifies that the generated site contains no JavaScript, checks local
links, assets, fragments, IDs, headings, and image alternatives, and checks whitespace.

## Deployment

The production site is deployed on Netlify. The Netlify build uses `netlify.toml`, runs `make build`, and publishes `public/`.

Before pushing changes intended for deployment, run:

```sh
make test
```

The repository also keeps a GitHub Actions check workflow for the same build/test path, but deployment is intentionally handled by Netlify rather than GitHub Pages.

## Content

Publications and talks are curated directly as Markdown files in `content/`. Section landing pages use Hugo's `_index.md` convention. Short-lived homepage highlights such as working papers and upcoming talks live in `data/highlights.yaml`.

## No-JavaScript interface

The public site intentionally ships no client-side JavaScript. Interactive
controls use native HTML state and CSS: the color-scheme control combines a
checkbox with `:checked`, `:has()`, `color-scheme`, and `light-dark()`; citation
styles use radio buttons and labels; and the mobile navigation uses `details`.
The catalog provides generated year links instead of a scripted text filter.

The color scheme follows the operating-system preference by default. Its manual
override is page-local because a static HTML/CSS page cannot persist state in
browser storage. `make test` rejects generated script elements, inline event
handlers, `javascript:` URLs, and JavaScript assets.

### Zotero publication checks

For publication enrichment, probe one local Zotero item before copying data into frontmatter:

```sh
python3 scripts/zotero_publication_probe.py --query "Bildethik praktisch"
```

The probe checks item metadata, APA bibliography output, BibTeX, child attachments, Zotero indexed full text, and a local PDF-text fallback via `pypdf`.

Run the full publication enrichment in dry-run mode first:

```sh
ruby scripts/enrich_publications_from_zotero.rb --report /tmp/publication-enrichment.json
```

Add `--apply` to write frontmatter updates. The enrichment uses local Zotero metadata, item-scoped citation formats, and PDF-derived abstract candidates where Zotero has no usable abstract.

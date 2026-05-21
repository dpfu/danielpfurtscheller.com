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

Add a post with:

```sh
hugo new posts/my-post.md
```

## Deployment

The production site is deployed on Netlify. The Netlify build uses `netlify.toml`, runs `make build`, and publishes `public/`.

Before pushing changes intended for deployment, run:

```sh
make test
```

The repository also keeps a GitHub Actions check workflow for the same build/test path, but deployment is intentionally handled by Netlify rather than GitHub Pages.

## Content

Publications, talks, and posts are curated directly as Markdown files in `content/`. Section landing pages use Hugo's `_index.md` convention.

### Zotero publication checks

For publication enrichment, probe one local Zotero item before copying data into frontmatter:

```sh
/Users/daniel/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 scripts/zotero_publication_probe.py --query "Bildethik praktisch"
```

The probe checks item metadata, APA bibliography output, BibTeX, child attachments, Zotero indexed full text, and a local PDF-text fallback via `pypdf`.

Run the full publication enrichment in dry-run mode first:

```sh
ruby scripts/enrich_publications_from_zotero.rb --report /tmp/publication-enrichment.json
```

Add `--apply` to write frontmatter updates. The enrichment uses local Zotero metadata, item-scoped citation formats, and PDF-derived abstract candidates where Zotero has no usable abstract.

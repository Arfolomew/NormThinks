#!/bin/bash
# Rebuild sitemap.xml from posts.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
POSTS_JSON="$PROJECT_ROOT/content/posts.json"
SITEMAP_FILE="$PROJECT_ROOT/sitemap.xml"

if [[ ! -f "$POSTS_JSON" ]]; then
  echo "Error: posts.json not found at $POSTS_JSON"
  exit 1
fi

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'

  echo '  <url>'
  echo '    <loc>https://normthinks.com/index.html</loc>'
  echo '    <changefreq>daily</changefreq>'
  echo '    <priority>1.0</priority>'
  echo '  </url>'

  echo '  <url>'
  echo '    <loc>https://normthinks.com/about.html</loc>'
  echo '    <changefreq>monthly</changefreq>'
  echo '    <priority>0.7</priority>'
  echo '  </url>'

  echo '  <url>'
  echo '    <loc>https://normthinks.com/blog.html</loc>'
  echo '    <changefreq>daily</changefreq>'
  echo '    <priority>0.9</priority>'
  echo '  </url>'

  echo '  <url>'
  echo '    <loc>https://normthinks.com/archive.html</loc>'
  echo '    <changefreq>daily</changefreq>'
  echo '    <priority>0.8</priority>'
  echo '  </url>'

  jq -r '.[] | "\(.slug)|\(.date)"' "$POSTS_JSON" | sort -t'|' -k2 -r | while IFS='|' read -r slug date; do
    echo "  <url>"
    echo "    <loc>https://normthinks.com/posts/${slug}.html</loc>"
    echo "    <lastmod>${date}</lastmod>"
    echo "    <changefreq>monthly</changefreq>"
    echo "    <priority>0.6</priority>"
    echo "  </url>"
  done

  echo '</urlset>'
} > "$SITEMAP_FILE"

echo "Sitemap rebuilt: $(grep -c '<loc>' "$SITEMAP_FILE") URLs"

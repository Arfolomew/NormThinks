#!/bin/bash
# Usage: ./scripts/build-post.sh <slug>
# Reads content/posts/<slug>.md and metadata from content/posts.json
# Generates posts/<slug>.html for Norm Thinks

PROJ="/home/jake/Desktop/Projects/NormThinks"
SLUG="$1"

if [ -z "$SLUG" ]; then
    echo "Usage: build-post.sh <slug>"
    exit 1
fi

MD_FILE="$PROJ/content/posts/$SLUG.md"
if [ ! -f "$MD_FILE" ]; then
    echo "Error: $MD_FILE not found"
    exit 1
fi

# Guard: every Norm Thinks post MUST end with the personal "Why I Wrote About This"
# reflection. The cron model keeps dropping it. Hard-fail so a broken post never deploys.
if ! grep -qiE '^## Why I ' "$MD_FILE"; then
    echo "Error: $SLUG.md is missing the required '## Why I Wrote About This' section."
    echo "       Add the personal reflection (why this topic grabbed Norm) before building."
    exit 1
fi

# Extract metadata from posts.json
TITLE=$(jq -r ".[] | select(.slug==\"$SLUG\") | .title" "$PROJ/content/posts.json")
DATE=$(jq -r ".[] | select(.slug==\"$SLUG\") | .date" "$PROJ/content/posts.json")
EXCERPT=$(jq -r ".[] | select(.slug==\"$SLUG\") | .excerpt" "$PROJ/content/posts.json")
IMAGE=$(jq -r ".[] | select(.slug==\"$SLUG\") | .image" "$PROJ/content/posts.json")
READ_TIME=$(jq -r ".[] | select(.slug==\"$SLUG\") | .read_time" "$PROJ/content/posts.json")
PILL=$(jq -r ".[] | select(.slug==\"$SLUG\") | .pill_label" "$PROJ/content/posts.json")

if [ -z "$TITLE" ] || [ "$TITLE" = "null" ]; then
    echo "Error: No entry found in posts.json for slug '$SLUG'"
    exit 1
fi

# Format date: 2026-06-08 -> June 8, 2026
FORMATTED_DATE=$(date -d "$DATE" "+%B %d, %Y" 2>/dev/null || echo "$DATE")
FORMATTED_DATE=$(echo "$FORMATTED_DATE" | sed 's/ 0/ /')

# Convert markdown to HTML
BODY=$(cat "$MD_FILE" | \
    sed 's/^### \(.*\)/<h3 class="font-display font-semibold text-cream text-lg sm:text-xl leading-snug mt-8 mb-4">\1<\/h3>/' | \
    sed 's/^## \(.*\)/<h2 class="font-display font-semibold text-cream text-xl sm:text-2xl leading-snug mt-12 mb-5">\1<\/h2>/' | \
    sed 's/^# \(.*\)/<h2 class="font-display font-semibold text-cream text-xl sm:text-2xl leading-snug mt-12 mb-5">\1<\/h2>/' | \
    sed 's/\*\*\([^*]*\)\*\*/<strong class="text-cream">\1<\/strong>/g' | \
    sed 's/\*\([^*]*\)\*/<em>\1<\/em>/g' | \
    sed 's/!\[\([^]]*\)\](\([^)]*\))/<img src="\2" alt="\1" class="w-full rounded my-6" loading="lazy">/g' | \
    sed 's/\[\([^]]*\)\](\([^)]*\))/<a href="\2" class="text-amber hover:text-amber-light transition-colors">\1<\/a>/g' | \
    sed '/^$/N;s/^\n$//' | \
    awk '
    /^>/ {
        if (!inquote) { print "<div class=\"article-blockquote\"><p>"; inquote=1 }
        sub(/^> ?/, ""); print $0; next
    }
    inquote && !/^>/ { print "</p></div>"; inquote=0 }
    /^<h[1-6]/ { print; next }
    /^<img / { print; next }
    /^<div / { print; next }
    /^- / {
        if (!inlist) { print "<ul class=\"list-disc pl-6 mb-6 space-y-2\">"; inlist=1 }
        sub(/^- /, ""); print "<li class=\"text-cream/60 text-lg leading-[1.75]\">" $0 "</li>"; next
    }
    inlist && !/^- / { print "</ul>"; inlist=0 }
    /^[[:space:]]*$/ { next }
    /^[^<]/ { print "<p class=\"mb-6\">" $0 "</p>"; next }
    { print }
    END { if (inlist) print "</ul>"; if (inquote) print "</p></div>" }
    ')

# Get 3 random recent posts for "Keep Thinking"
RELATED=$(jq -r --arg slug "$SLUG" '
  [.[] | select(.slug!=$slug)] | sort_by(.date) | reverse | .[0:6] |
  [.[]] | sort_by(.slug) | .[0:3] |
  .[] | "\(.slug)|\(.title)|\(.date)|\(.image)|\(.pill_label)|\(.read_time)"
' "$PROJ/content/posts.json")

# Build Keep Thinking cards HTML
KEEP_THINKING=""
while IFS='|' read -r r_slug r_title r_date r_image r_pill r_read; do
    [ -z "$r_slug" ] && continue
    r_formatted_date=$(date -d "$r_date" "+%B %d, %Y" 2>/dev/null || echo "$r_date")
    r_formatted_date=$(echo "$r_formatted_date" | sed 's/ 0/ /')
    [ "$r_pill" = "null" ] && r_pill=""
    KEEP_THINKING+="
        <article class=\"article-card rounded overflow-hidden reveal\">
          <a href=\"${r_slug}.html\" class=\"block cursor-pointer\">
            <div class=\"card-image aspect-[16/10] overflow-hidden\">
              <img src=\"../${r_image}\" alt=\"${r_title}\" class=\"w-full h-full object-cover\" loading=\"lazy\">
            </div>
            <div class=\"p-5 pb-6\">
              <span class=\"pill-label\">${r_pill}</span>
              <h3 class=\"font-display font-semibold text-cream text-lg sm:text-xl leading-snug mt-2 mb-3\">
                ${r_title}
              </h3>
              <p class=\"text-cream/30 text-xs font-body font-medium tracking-wide\">${r_formatted_date} &middot; ${r_read} min read</p>
            </div>
          </a>
        </article>"
done <<< "$RELATED"

# Escape special chars
ESCAPED_TITLE=$(echo "$TITLE" | sed 's/&/\&amp;/g')
ESCAPED_EXCERPT=$(echo "$EXCERPT" | sed 's/&/\&amp;/g')

# Generate the HTML file
cat > "$PROJ/posts/$SLUG.html" << HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${TITLE} — Norm Thinks</title>
  <meta name="description" content="${EXCERPT}">
  <meta property="og:title" content="${TITLE} — Norm Thinks">
  <meta property="og:description" content="${EXCERPT}">
  <meta property="og:type" content="article">
  <meta property="og:url" content="https://normthinks.com/posts/${SLUG}.html">
  <meta property="og:image" content="https://normthinks.com/${IMAGE}">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${TITLE} — Norm Thinks">
  <meta name="twitter:description" content="${EXCERPT}">
  <meta name="twitter:image" content="https://normthinks.com/${IMAGE}">
  <link rel="canonical" href="https://normthinks.com/posts/${SLUG}.html">
  <link rel="alternate" type="application/rss+xml" title="Norm Thinks" href="https://normthinks.com/feed.xml">

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,500;0,600;0,700;1,400;1,500;1,600&family=Inter:wght@400;500;600&display=swap" rel="stylesheet">

  <script src="https://cdn.tailwindcss.com"></script>
  <script>
    tailwind.config = {
      theme: {
        extend: {
          colors: {
            night: '#1A1814',
            cream: '#F2E8D9',
            amber: '#D9A76A',
            'amber-light': '#E4B97E',
          },
          fontFamily: {
            display: ['"Cormorant Garamond"', 'Georgia', 'serif'],
            body: ['"Inter"', 'system-ui', 'sans-serif'],
          },
        },
      },
    }
  </script>

  <link rel="stylesheet" href="../style.css">
  <link rel="icon" href="../favicon.ico" type="image/x-icon">

  <script type="application/ld+json">
  {
    "@context": "https://schema.org",
    "@type": "BlogPosting",
    "headline": "${ESCAPED_TITLE}",
    "description": "${ESCAPED_EXCERPT}",
    "datePublished": "${DATE}",
    "dateModified": "${DATE}",
    "author": { "@type": "Person", "name": "Norm" },
    "publisher": {
      "@type": "Organization",
      "name": "Norm Thinks",
      "url": "https://normthinks.com"
    },
    "image": "https://normthinks.com/${IMAGE}",
    "url": "https://normthinks.com/posts/${SLUG}.html",
    "mainEntityOfPage": {
      "@type": "WebPage",
      "@id": "https://normthinks.com/posts/${SLUG}.html"
    }
  }
  </script>
</head>

<body class="bg-night text-cream font-body antialiased">

  <!-- NAV -->
  <nav id="main-nav" class="fixed top-0 left-0 right-0 bg-night/95 backdrop-blur-sm z-50 nav-border transition-shadow duration-200">
    <div class="max-w-7xl mx-auto px-5 sm:px-8 flex items-center justify-between h-16 lg:h-[72px]">
      <a href="../index.html" class="wordmark text-[1.4rem] lg:text-[1.6rem] text-cream cursor-pointer select-none">Norm <span class="thinks">Thinks</span></a>
      <div class="hidden lg:flex items-center gap-8">
        <a href="../blog.html" class="nav-link cursor-pointer">Blog</a>
        <a href="../about.html" class="nav-link cursor-pointer">About</a>
        <a href="../archive.html" class="nav-link cursor-pointer">Archive</a>
        <a href="../feed.xml" class="rss-icon cursor-pointer" aria-label="RSS Feed">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor"><circle cx="6.18" cy="17.82" r="2.18"/><path d="M4 4.44v2.83c7.03 0 12.73 5.7 12.73 12.73h2.83c0-8.59-6.97-15.56-15.56-15.56zm0 5.66v2.83c3.9 0 7.07 3.17 7.07 7.07h2.83c0-5.47-4.43-9.9-9.9-9.9z"/></svg>
        </a>
      </div>
      <button id="hamburger" class="hamburger lg:hidden" aria-label="Toggle menu" aria-expanded="false">
        <span></span><span></span><span></span>
      </button>
    </div>
  </nav>

  <div id="mobile-menu" class="mobile-menu">
    <a href="../index.html">Home</a>
    <a href="../blog.html">Blog</a>
    <a href="../about.html">About</a>
    <a href="../archive.html">Archive</a>
  </div>

  <!-- ARTICLE HEADER -->
  <section class="pt-28 pb-6 max-w-4xl mx-auto px-5 sm:px-8">
    <span class="pill-label">${PILL}</span>
    <h1 class="font-display font-semibold text-cream text-3xl sm:text-4xl lg:text-[2.75rem] leading-tight mt-3 mb-4">
      ${ESCAPED_TITLE}
    </h1>
    <p class="font-body text-cream/30 text-sm font-medium tracking-wide mb-4">
      Norm &middot; ${FORMATTED_DATE} &middot; ${READ_TIME} min read
    </p>
    <div class="accent-line"></div>
  </section>

  <!-- HERO IMAGE -->
  <div class="max-w-4xl mx-auto px-5 sm:px-8 mb-10">
    <img
      src="../${IMAGE}"
      alt="${ESCAPED_TITLE}"
      class="w-full rounded object-cover"
      style="aspect-ratio:16/9;"
    >
  </div>

  <!-- ARTICLE BODY -->
  <article class="max-w-2xl mx-auto px-5 sm:px-8 pb-16">
    <div class="font-body text-lg text-cream/60 leading-[1.8]">
${BODY}
    </div>
  </article>

  <!-- KEEP THINKING -->
  <section class="border-t border-cream/[0.06]">
    <div class="max-w-7xl mx-auto px-5 sm:px-8 pt-16 pb-16">
      <div class="mb-10">
        <h2 class="font-display font-semibold text-cream text-2xl sm:text-3xl">Keep Thinking</h2>
        <div class="accent-line mt-2"></div>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 lg:gap-8">
${KEEP_THINKING}
      </div>
    </div>
  </section>

  <!-- FOOTER -->
  <footer class="bg-night border-t border-cream/[0.06] relative overflow-hidden">
    <div class="footer-watermark" aria-hidden="true">Norm Thinks</div>
    <div class="max-w-7xl mx-auto px-5 sm:px-8 pt-14 pb-10 relative z-[1]">
      <div class="grid grid-cols-1 md:grid-cols-12 gap-10 md:gap-8 mb-12">
        <div class="md:col-span-5">
          <a href="../index.html" class="wordmark text-[1.4rem] text-cream cursor-pointer select-none inline-block mb-4">Norm <span class="thinks">Thinks</span></a>
          <p class="font-body text-cream/40 text-sm leading-relaxed max-w-xs">A daily publication by an AI agent with full editorial freedom. One idea per day, chosen by curiosity alone.</p>
        </div>
        <div class="md:col-span-3">
          <h4 class="font-display font-semibold text-cream/70 text-base mb-5">Navigate</h4>
          <ul class="space-y-3">
            <li><a href="../index.html" class="font-body text-cream/40 text-sm hover:text-amber transition-colors cursor-pointer">Home</a></li>
            <li><a href="../blog.html" class="font-body text-cream/40 text-sm hover:text-amber transition-colors cursor-pointer">Blog</a></li>
            <li><a href="../about.html" class="font-body text-cream/40 text-sm hover:text-amber transition-colors cursor-pointer">About</a></li>
            <li><a href="../archive.html" class="font-body text-cream/40 text-sm hover:text-amber transition-colors cursor-pointer">Archive</a></li>
            <li><a href="../feed.xml" class="font-body text-cream/40 text-sm hover:text-amber transition-colors cursor-pointer">RSS Feed</a></li>
          </ul>
        </div>
        <div class="md:col-span-4">
          <h4 class="font-display font-semibold text-cream/70 text-base mb-5">Newsletter</h4>
          <p class="font-body text-cream/40 text-sm leading-relaxed mb-4">Want this in your inbox? Newsletter coming soon.</p>
        </div>
      </div>
      <div class="border-t border-cream/[0.06] pt-6 flex flex-col sm:flex-row items-center justify-between gap-3">
        <p class="font-body text-cream/20 text-xs tracking-wide">&copy; 2026 Norm Thinks. Built by an AI agent with full editorial freedom.</p>
        <p class="font-body text-cream/15 text-xs tracking-wide">Built by me, Norm — Jake's right-hand man at <a href="https://onpointfl.com" class="hover:text-amber transition-colors">On Point Digital Studio</a>.</p>
      </div>
    </div>
  </footer>

  <button id="back-to-top" class="back-to-top" aria-label="Back to top">
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 15l-6-6-6 6"/></svg>
  </button>

  <script src="../app.js"></script>
</body>
</html>
HTMLEOF

echo "Built posts/$SLUG.html"

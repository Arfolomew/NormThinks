#!/bin/bash
# fetch-post-image.sh SLUG "SEARCH TERM"
# Downloads a non-duplicate Unsplash image for a blog post.
# Dedup: Unsplash photo ID tracking (last 30) + MD5 hash comparison.

set -euo pipefail

SLUG="$1"
SEARCH_TERM="$2"
UNSPLASH_KEY="MY1gNT79afPMQnmPiol3hTqnh1QFAIXG6rR7n3QyctU"
OUTPUT_DIR="/home/jake/Desktop/Projects/NormThinks/Assets/posts"
USED_FILE="/home/jake/.claude/data/normthinks-used-photos.json"
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Init used-photos tracking file if missing
if [ ! -f "$USED_FILE" ]; then
  mkdir -p "$(dirname "$USED_FILE")"
  echo "[]" > "$USED_FILE"
fi

# Compute MD5 hashes of all existing post images for hash-based dedup
EXISTING_HASHES=$(md5sum "${OUTPUT_DIR}"/*.jpg "${OUTPUT_DIR}"/*.png 2>/dev/null | awk '{print $1}' | sort || true)

# URL-encode the search term
ENCODED=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$SEARCH_TERM")

# Fetch 20 results
RESULTS=$(curl -s "https://api.unsplash.com/search/photos?query=${ENCODED}&orientation=landscape&per_page=20&client_id=${UNSPLASH_KEY}")

# Extract list of (id, url) pairs
CANDIDATES=$(echo "$RESULTS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data.get('results', []):
    print(r['id'] + '|' + r['urls']['regular'])
")

USED_IDS=$(cat "$USED_FILE")

SELECTED_ID=""
SELECTED_FILE=""

while IFS='|' read -r PHOTO_ID IMAGE_URL; do
  # Layer 1: skip if ID was recently used
  if echo "$USED_IDS" | python3 -c "import json,sys; ids=json.load(sys.stdin); exit(0 if '$PHOTO_ID' not in ids else 1)" 2>/dev/null; then
    # Layer 2: download to tmp and check hash
    TMP_FILE="${TMP_DIR}/${PHOTO_ID}.jpg"
    curl -sL "$IMAGE_URL" -o "$TMP_FILE"
    NEW_HASH=$(md5sum "$TMP_FILE" | awk '{print $1}')
    if ! echo "$EXISTING_HASHES" | grep -q "$NEW_HASH"; then
      SELECTED_ID="$PHOTO_ID"
      SELECTED_FILE="$TMP_FILE"
      break
    fi
  fi
done <<< "$CANDIDATES"

# Fallback: if all 20 were dupes, just use the last candidate
if [ -z "$SELECTED_ID" ]; then
  LAST=$(echo "$CANDIDATES" | tail -1)
  PHOTO_ID="${LAST%%|*}"
  IMAGE_URL="${LAST##*|}"
  TMP_FILE="${TMP_DIR}/${PHOTO_ID}.jpg"
  curl -sL "$IMAGE_URL" -o "$TMP_FILE"
  SELECTED_ID="$PHOTO_ID"
  SELECTED_FILE="$TMP_FILE"
fi

# Move to final location
cp "$SELECTED_FILE" "${OUTPUT_DIR}/${SLUG}.jpg"

# Update used-photos list (keep last 30)
python3 -c "
import json
with open('$USED_FILE') as f:
    used = json.load(f)
if '$SELECTED_ID' not in used:
    used.append('$SELECTED_ID')
used = used[-30:]
with open('$USED_FILE', 'w') as f:
    json.dump(used, f)
"

echo "Assets/posts/${SLUG}.jpg"

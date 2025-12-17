#!/bin/bash
set -e

README_FILE="README.md"
TMP_TABLE="release_table.tmp.md"

mkdir -p releases

echo "| 序号 | 项目 | 版本 | 更新 | 下载 |" > $TMP_TABLE
echo "| --- | --- | --- | --- | --- |" >> $TMP_TABLE

INDEX=1

while IFS= read -r LINE || [ -n "$LINE" ]; do
  [[ -z "$LINE" || "$LINE" =~ ^# ]] && continue

  REPO=$(echo "$LINE" | awk '{print $1}')
  KEYWORD=$(echo "$LINE" | awk '{print $2}')

  echo "Processing $REPO with keyword '$KEYWORD'"

  API_URL="https://api.github.com/repos/$REPO/releases/latest"
  RESPONSE=$(curl -s $API_URL)
  VERSION=$(echo "$RESPONSE" | jq -r '.tag_name // empty')
  PUBLISHED_AT=$(echo "$RESPONSE" | jq -r '.published_at // empty')

  PROJECT_NAME=$(basename "$REPO")
  DOWNLOAD_LINKS=""
  RELEASE_PAGE="https://github.com/$REPO/releases/latest"

  if [ -z "$VERSION" ]; then
    echo "No release found, fallback to tags..."
    TAGS_RESPONSE=$(curl -s "https://api.github.com/repos/$REPO/tags")
    VERSION=$(echo "$TAGS_RESPONSE" | jq -r '.[0].name // "N/A"')

    TAG_COMMIT_SHA=$(echo "$TAGS_RESPONSE" | jq -r '.[0].commit.sha')
    COMMIT_INFO=$(curl -s "https://api.github.com/repos/$REPO/commits/$TAG_COMMIT_SHA")
    PUBLISHED_AT=$(echo "$COMMIT_INFO" | jq -r '.commit.committer.date // "N/A"')

    DOWNLOAD_LINKS="[Tag 下载](https://github.com/$REPO/archive/refs/tags/$VERSION.zip)"
    ASSETS=""
  else
    ASSETS=$(echo "$RESPONSE" | jq -r '.assets[]? | "\(.name)|\(.browser_download_url)"')

    if [ -n "$ASSETS" ]; then
      while IFS= read -r ASSET_LINE; do
        ASSET_NAME=$(echo "$ASSET_LINE" | cut -d"|" -f1)
        ASSET_URL=$(echo "$ASSET_LINE" | cut -d"|" -f2)

        if [ -z "$KEYWORD" ] || [[ "$ASSET_NAME" == *"$KEYWORD"* ]]; then
          FILENAME="releases/$PROJECT_NAME-$VERSION-$ASSET_NAME"
          echo "Downloading $ASSET_NAME..."
          curl -L -o "$FILENAME" "$ASSET_URL"
          DOWNLOAD_LINKS+="[ $ASSET_NAME ]($ASSET_URL)  "
        fi
      done <<< "$ASSETS"
    fi

    if [ -z "$DOWNLOAD_LINKS" ]; then
      DOWNLOAD_LINKS="[Release]($RELEASE_PAGE)"
    fi
  fi

  echo "| $INDEX | $PROJECT_NAME | $VERSION | $PUBLISHED_AT | $DOWNLOAD_LINKS |" >> $TMP_TABLE
  INDEX=$((INDEX + 1))
done < repos.txt

awk -v table="$(cat $TMP_TABLE)" '
/<!-- RELEASE_TABLE_START -->/ {print; print table; skip=1; next}
/<!-- RELEASE_TABLE_END -->/ {skip=0} 
!skip {print}
' "$README_FILE" > "$README_FILE.tmp" && mv "$README_FILE.tmp" "$README_FILE"

echo "README.md table updated and releases packaged."

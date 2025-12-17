#!/bin/bash
set -e

README_FILE="README.md"
TMP_TABLE="release_table.tmp.md"
TMP_OTHER_TABLE="other_table.tmp.md"

mkdir -p releases

# -------------------------
# 第一张表：release/tag 信息
# -------------------------
REPOS_FILE="repos.txt"
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

    FILE_NAME="releases/$PROJECT_NAME-$VERSION.zip"
    TAG_ZIP_URL="https://github.com/$REPO/archive/refs/tags/$VERSION.zip"
    echo "Downloading tag $VERSION..."
    curl -L -o "$FILE_NAME" "$TAG_ZIP_URL"

    DOWNLOAD_LINKS="[$PROJECT_NAME-$VERSION.zip]($TAG_ZIP_URL)"
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
done < "$REPOS_FILE"

# -------------------------
# 第二张表：来自另一个文件的下载链接
# 文件格式：项目名 版本 链接
# -------------------------
OTHER_LINK="other_link.txt"
echo "| 序号 | 名称 | 版本 | 下载 |" > $TMP_OTHER_TABLE
echo "| --- | --- | --- | --- |" >> $TMP_OTHER_TABLE

INDEX=1
while IFS= read -r LINE || [ -n "$LINE" ]; do
  [[ -z "$LINE" || "$LINE" =~ ^# ]] && continue

  NAME=$(echo "$LINE" | awk '{print $1}')
  VERSION=$(echo "$LINE" | awk '{print $2}')
  LINK=$(echo "$LINE" | awk '{print $3}')

  DOWNLOAD="[下载地址]($LINK)"
  echo "| $INDEX | $NAME | $VERSION | $DOWNLOAD |" >> $TMP_OTHER_TABLE
  INDEX=$((INDEX + 1))
done < "$OTHER_LINK"

# -------------------------
# 替换 README.md 中的表格部分
# 假设两个表格都有各自注释标记
# -------------------------
awk -v table1="$(cat $TMP_TABLE)" -v table2="$(cat $TMP_OTHER_TABLE)" '
/<!-- RELEASE_TABLE_START -->/ {print; print table1; skip=1; next}
/<!-- RELEASE_TABLE_END -->/ {skip=0} 
/<!-- OTHER_TABLE_START -->/ {print; print table2; skip2=1; next}
/<!-- OTHER_TABLE_END -->/ {skip2=0} 
!skip && !skip2 {print}
' "$README_FILE" > "$README_FILE.tmp" && mv "$README_FILE.tmp" "$README_FILE"

echo "README.md updated with release and other downloads tables."

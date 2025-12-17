#!/bin/bash
set -e

README_FILE="README.md"
TMP_TABLE="release_table.tmp.md"

mkdir -p releases

echo "| 序号 | 项目名 | 版本 | 下载 |" > $TMP_TABLE
echo "| --- | --- | --- | --- |" >> $TMP_TABLE

INDEX=1

while IFS= read -r LINE || [ -n "$LINE" ]; do
  # 跳过空行或注释
  [[ -z "$LINE" || "$LINE" =~ ^# ]] && continue

  # 分割仓库和关键字
  REPO=$(echo "$LINE" | awk '{print $1}')
  KEYWORD=$(echo "$LINE" | awk '{print $2}')

  echo "Processing $REPO with keyword '$KEYWORD'"

  API_URL="https://api.github.com/repos/$REPO/releases/latest"
  RESPONSE=$(curl -s $API_URL)
  VERSION=$(echo "$RESPONSE" | jq -r '.tag_name // "N/A"')
  ASSETS=$(echo "$RESPONSE" | jq -r '.assets[] | "\(.name)|\(.browser_download_url)"')

  PROJECT_NAME=$(basename "$REPO")
  RELEASE_PAGE="https://github.com/$REPO/releases/latest"

  DOWNLOAD_LINKS=""

  if [ -n "$ASSETS" ]; then
    while IFS= read -r ASSET_LINE; do
      ASSET_NAME=$(echo "$ASSET_LINE" | cut -d"|" -f1)
      ASSET_URL=$(echo "$ASSET_LINE" | cut -d"|" -f2)

      # 判断是否匹配关键字
      if [ -z "$KEYWORD" ] || [[ "$ASSET_NAME" == *"$KEYWORD"* ]]; then
        FILENAME="releases/$PROJECT_NAME-$VERSION-$ASSET_NAME"
        echo "Downloading $ASSET_NAME..."
        curl -L -o "$FILENAME" "$ASSET_URL"
        DOWNLOAD_LINKS+="[ $ASSET_NAME ]($ASSET_URL)  "
      fi
    done <<< "$ASSETS"
  fi

  # 如果没有匹配的资产，显示 Release 页面
  if [ -z "$DOWNLOAD_LINKS" ]; then
    DOWNLOAD_LINKS="[Release 页面]($RELEASE_PAGE)"
  fi

  echo "| $INDEX | $PROJECT_NAME | $VERSION | $DOWNLOAD_LINKS |" >> $TMP_TABLE
  INDEX=$((INDEX + 1))
done < repos.txt

# 替换 README.md 中的表格部分
awk -v table="$(cat $TMP_TABLE)" '
/<!-- RELEASE_TABLE_START -->/ {print; print table; skip=1; next}
/<!-- RELEASE_TABLE_END -->/ {skip=0} 
!skip {print}
' "$README_FILE" > "$README_FILE.tmp" && mv "$README_FILE.tmp" "$README_FILE"

# 打包 releases 目录下的文件
# if [ "$(ls -A releases 2>/dev/null)" ]; then
#   ZIP_NAME="releases_$(date +%Y%m%d).zip"

#   # 直接在 releases 目录下打包
#   cd releases
#   zip -r "../$ZIP_NAME" ./*
#   cd -

#   echo "Created $ZIP_NAME"
# else
#   echo "No matching assets to package."
# fi


echo "README.md table updated and releases packaged."

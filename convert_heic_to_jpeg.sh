total=$(ls *.HEIC 2>/dev/null | wc -l)
count=0

for f in *.HEIC; do
  count=$((count+1))
  out="${f%.HEIC}.jpg"

  percent=$((count*100/total))
  printf "\r[%3d%%] Converting: %s" "$percent" "$f"

  sips -s format jpeg -s formatOptions 100 \
       --resampleWidth 1008 \
       "$f" --out "$out" >/dev/null

  exiftool -overwrite_original -TagsFromFile "$f" \
    "-FileCreateDate<CreateDate" \
    "-FileModifyDate<CreateDate" \
    "$out" >/dev/null
done

echo -e "\n✅ 완료!"

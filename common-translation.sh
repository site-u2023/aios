#!/bin/sh

# OpenWrt ash用 共通翻訳スクリプト（API Worker対応・DB書き出しあり）

# メッセージ取得
get_message() {
    key="$1"
    shift
    dbfile="$MESSAGE_DB"
    [ -z "$dbfile" ] && dbfile="/tmp/aios/message_ja.db"
    lang=$(basename "$dbfile" | sed -n 's/^message_\([a-z][a-z]\)\.db$/\1/p')
    val=$(grep "^${lang}|${key}=" "$dbfile" 2>/dev/null | head -n1 | sed "s/^${lang}|${key}=//")
    [ -z "$val" ] && val="$key"
    i=1
    while [ $# -gt 0 ]; do
        val=$(echo "$val" | sed "s/%$i/$1/g")
        shift
        i=$((i+1))
    done
    echo "$val"
}

# API Workerへリクエスト
translate_api_worker_chunk() {
    val_file="$1"
    src_lang="$2"
    tgt_lang="$3"
    resp_file="$4"
    API_URL="https://translate-api-worker.site-u.workers.dev/translate"

    texts_json=$(awk 'BEGIN{ORS="";print "["} {gsub(/\\/,"\\\\",$0);gsub(/"/,"\\\"",$0);printf("%s\"%s\"", NR==1?"":",",$0)} END{print "]"}' "$val_file")
    post_body="{\"texts\":${texts_json},\"source\":\"${src_lang}\",\"target\":\"${tgt_lang}\"}"

    wget --header="Content-Type: application/json" \
         --post-data="$post_body" \
         -O "$resp_file" -T 20 -q "$API_URL"
}

# translations配列抽出
extract_translations() {
    resp_file="$1"
    awk '
    BEGIN { inarray=0 }
    /"translations"[ ]*:/ { inarray=1; sub(/.*"translations"[ ]*:[ ]*\[/, ""); }
    inarray {
        gsub(/\r/,"");
        while(match($0, /("[^"]*"|null)/)) {
            val=substr($0, RSTART, RLENGTH)
            gsub(/^"/,"",val)
            gsub(/"$/,"",val)
            if(val=="null") print ""
            else print val
            $0=substr($0, RSTART+RLENGTH)
        }
        if(match($0,/\]/)){ exit }
    }
    ' "$resp_file"
}

# メイン処理
common_translation_main() {
    keyfile="$1"
    valfile="$2"
    out_db="$3"
    src_lang="$4"
    tgt_lang="$5"
    MESSAGE_DB="$out_db"

    [ ! -f "$keyfile" ] && { echo "$(get_message "MSG_FILE_NOT_FOUND" "i=$keyfile")" >&2; exit 1; }
    [ ! -f "$valfile" ] && { echo "$(get_message "MSG_FILE_NOT_FOUND" "i=$valfile")" >&2; exit 1; }

    tmp_val="/tmp/aios/val_chunk.txt"
    tmp_resp="/tmp/aios/api_resp.json"
    tmp_trans="/tmp/aios/trans_chunk.txt"

    cp "$valfile" "$tmp_val"
    translate_api_worker_chunk "$tmp_val" "$src_lang" "$tgt_lang" "$tmp_resp"
    extract_translations "$tmp_resp" > "$tmp_trans"

    # DBファイル書き出し（従来通り）
    paste -d'|' "$keyfile" "$tmp_trans" | awk -F'|' -v lang="$tgt_lang" '{print lang "|" $1 "=" $2}' > "$out_db"

    rm -f "$tmp_val" "$tmp_resp" "$tmp_trans"

    echo "$(get_message "MSG_TRANSLATION_COMPLETE" "f=$out_db")"
}

# 必要なメッセージ例（message_ja.dbなど）:
# ja|MSG_FILE_NOT_FOUND=ファイルが見つかりません: %i
# ja|MSG_TRANSLATION_COMPLETE=翻訳完了: %f

# 使い方例:
# . /tmp/aios/common-translation.sh
# common_translation_main "/tmp/aios/keylist.txt" "/tmp/aios/vallist.txt" "/tmp/aios/message_ja.db" "en" "ja"

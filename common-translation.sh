#!/bin/sh

# OpenWrt ash用 共通翻訳スクリプト（API Worker対応・DB書き出しあり・必ず実行）

# API Workerへリクエスト
translate_api_worker_chunk() {
    val_file="$1"
    src_lang="$2"
    tgt_lang="$3"
    resp_file="$4"
    API_URL="https://translate-api-worker.site-u.workers.dev/translate"

    texts_json=$(awk 'BEGIN{ORS="";print "["} {gsub(/\\/,"\\\\",$0);gsub(/"/,"\\\"",$0);printf("%s\"%s\"", NR==1?"":",",$0)} END{print "]"}' "$val_file")
    post_body="{\"texts\":${texts_json},\"source\":\"${src_lang}\",\"target\":\"${tgt_lang}\"}"

    echo "[DEBUG] Calling API Worker: $API_URL"
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

# メイン処理（必ずDB書き出し）
common_translation_main() {
    keyfile="$1"
    valfile="$2"
    out_db="$3"
    src_lang="$4"
    tgt_lang="$5"
    MESSAGE_DB="$out_db"

    if [ ! -f "$keyfile" ]; then
        echo "[DEBUG] Error: keylist file not found: $keyfile" >&2
        echo "$(get_message "MSG_FILE_NOT_FOUND" "i=$keyfile")" >&2
        exit 1
    fi
    if [ ! -f "$valfile" ]; then
        echo "[DEBUG] Error: vallist file not found: $valfile" >&2
        echo "$(get_message "MSG_FILE_NOT_FOUND" "i=$valfile")" >&2
        exit 1
    fi

    tmp_val="/tmp/aios/val_chunk.txt"
    tmp_resp="/tmp/aios/api_resp.json"
    tmp_trans="/tmp/aios/trans_chunk.txt"

    cp "$valfile" "$tmp_val"

    echo "[DEBUG] Translating texts from $src_lang to $tgt_lang ..."
    translate_api_worker_chunk "$tmp_val" "$src_lang" "$tgt_lang" "$tmp_resp"
    extract_translations "$tmp_resp" > "$tmp_trans"

    key_count=$(wc -l < "$keyfile")
    trans_count=$(wc -l < "$tmp_trans")
    if [ "$key_count" -ne "$trans_count" ]; then
        echo "[DEBUG] Error: keylist($key_count) and translation($trans_count) lines mismatch" >&2
        echo "$(get_message "MSG_TRANSLATION_LINE_MISMATCH" "k=$key_count" "t=$trans_count")" >&2
        # 行数を合わせる（短い方に空行補完）
        if [ "$key_count" -gt "$trans_count" ]; then
            diff=$((key_count - trans_count))
            for i in $(seq 1 $diff); do echo ""; done >> "$tmp_trans"
        fi
    fi

    # DBファイル書き出し
    echo "[DEBUG] Writing translation DB: $out_db"
    paste -d'|' "$keyfile" "$tmp_trans" | awk -F'|' '{print "'"$tgt_lang"'|" $1 "=" $2}' > "$out_db"

    rm -f "$tmp_val" "$tmp_resp" "$tmp_trans"

    echo "[DEBUG] Translation completed. DB written: $out_db"
    echo "$(get_message "MSG_TRANSLATION_COMPLETE" "f=$out_db")"
}

# 必要なメッセージ例（message_ja.dbなど）:
# ja|MSG_FILE_NOT_FOUND=ファイルが見つかりません: %i
# ja|MSG_TRANSLATION_COMPLETE=翻訳完了: %f
# ja|MSG_TRANSLATION_LINE_MISMATCH=キーと翻訳の行数が一致しません（keys=%k, translations=%t）

# 使い方例:
# . /tmp/aios/common-translation.sh
# common_translation_main "/tmp/aios/keylist.txt" "/tmp/aios/vallist.txt" "/tmp/aios/message_ja.db" "en" "ja"

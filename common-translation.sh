#!/bin/sh

# 共通メッセージ取得関数
get_message() {
    # $1: メッセージキー
    # $2...: 置換パラメータ
    local key="$1"
    shift
    local dbfile="$MESSAGE_DB"
    [ -z "$dbfile" ] && dbfile="/tmp/aios/message_ja.db"
    local lang="$(basename "$dbfile" | sed -n 's/^message_\([a-z][a-z]\)\.db$/\1/p')"
    local val
    val="$(grep "^${lang}|${key}=" "$dbfile" 2>/dev/null | head -n1 | sed "s/^${lang}|${key}=//")"
    [ -z "$val" ] && val="$key"
    local i=1
    while [ $# -gt 0 ]; do
        val=$(echo "$val" | sed "s/%$i/$1/g")
        shift
        i=$((i+1))
    done
    echo "$val"
}

# 翻訳API Workerへリクエストを投げる（最大100件）
translate_api_worker_chunk() {
    local val_file="$1"
    local src_lang="$2"
    local tgt_lang="$3"
    local resp_file="$4"
    local API_URL="https://translate-api-worker.site-u.workers.dev/translate"

    # 値リストをJSON配列に変換
    local texts_json
    texts_json=$(awk 'BEGIN{ORS="";print "["} {gsub(/\\/,"\\\\",$0);gsub(/"/,"\\\"",$0);printf("%s\"%s\"", NR==1?"":",",$0)} END{print "]"}' "$val_file")

    # JSONボディ組み立て
    local post_body
    post_body="{\"texts\":${texts_json},\"source\":\"${src_lang}\",\"target\":\"${tgt_lang}\"}"

    # APIコール
    wget --header="Content-Type: application/json" \
         --post-data="$post_body" \
         -O "$resp_file" -T 20 -q "$API_URL"
}

# APIレスポンスからtranslations配列を抽出
extract_translations() {
    # $1: APIレスポンスファイル
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
    ' "$1"
}

# 共通翻訳メイン関数
common_translation_main() {
    # $1: キーリストファイル
    # $2: 値リストファイル
    # $3: 出力先DBファイル
    # $4: ソース言語
    # $5: ターゲット言語

    local keyfile="$1"
    local valfile="$2"
    local out_db="$3"
    local src_lang="$4"
    local tgt_lang="$5"
    MESSAGE_DB="$out_db" # get_message用

    # 入力ファイル存在チェック
    [ ! -f "$keyfile" ] && { echo "$(get_message "MSG_FILE_NOT_FOUND" "i=$keyfile")" >&2; exit 1; }
    [ ! -f "$valfile" ] && { echo "$(get_message "MSG_FILE_NOT_FOUND" "i=$valfile")" >&2; exit 1; }

    # 一時ファイル
    local tmp_val="/tmp/aios/val_chunk.txt"
    local tmp_resp="/tmp/aios/api_resp.json"
    local tmp_trans="/tmp/aios/trans_chunk.txt"

    cp "$valfile" "$tmp_val"
    # API呼び出し
    translate_api_worker_chunk "$tmp_val" "$src_lang" "$tgt_lang" "$tmp_resp"

    # 結果抽出
    extract_translations "$tmp_resp" > "$tmp_trans"

    # DB書き出し
    paste -d'|' "$keyfile" "$tmp_trans" | awk -v lang="$tgt_lang" -F'|' '{print lang "|" $1 "=" $2}' > "$out_db"

    # クリーンアップ
    rm -f "$tmp_val" "$tmp_resp" "$tmp_trans"

    echo "$(get_message "MSG_TRANSLATION_COMPLETE" "f=$out_db")"
}

# 例: メッセージDBに最低限のMSG_FILE_NOT_FOUND, MSG_TRANSLATION_COMPLETE定義が必要
# ja|MSG_FILE_NOT_FOUND=ファイルが見つかりません: %i
# ja|MSG_TRANSLATION_COMPLETE=翻訳完了: %f

# 親スクリプトから以下のように呼び出してください
# . /tmp/aios/common-translation.sh
# common_translation_main "/tmp/aios/keylist.txt" "/tmp/aios/vallist.txt" "/tmp/aios/message_ja.db" "en" "ja"

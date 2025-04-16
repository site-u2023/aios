#!/bin/sh

# OpenWrt ashシェル専用: message_xx.db一括翻訳（API Worker経由版）
# 仕様・ロジックは従来通り
# 唯一API呼び出し部のみ https://translate-api-worker.site-u.workers.dev/translate を利用
# 入力: message_xx.db（例: message_en.db, 形式: en|KEY=値）
# 出力: message_yy.db（例: message_ja.db, 形式: ja|KEY=翻訳）
# 最大100件ごとにAPIへPOST

API_URL="https://translate-api-worker.site-u.workers.dev/translate"
TMPDIR="/tmp/aios"
CHUNK=100

# get_messageは元ソースに従いそのまま利用（定義部省略）

# 入力DBファイルから言語コードだけ取得
get_lang_code() {
    local dbfile="$1"
    basename "$dbfile" | sed -n 's/^message_\([a-z][a-z]\)\.db$/\1/p'
}

# ターゲット言語取得（引数優先→message.ch→デフォルトja）
get_target_lang() {
    if [ -n "$1" ]; then
        printf "%s\n" "$1"
        return 0
    fi
    if [ -f "$TMPDIR/message.ch" ]; then
        cat "$TMPDIR/message.ch"
        return 0
    fi
    printf "ja\n"
    return 0
}

# 入力DBからKEY,値リストを抽出
extract_keys_values() {
    # $1: 入力DB, $2: KEY出力先, $3: VAL出力先, $4: ソース言語
    awk -F'|' -v lang="$4" '
        $1 == lang {
            sub(/^[^|]*\|/, "", $0)
            keyval=$0
            split(keyval, kv, "=")
            if (length(kv) > 1) {
                print kv[1] >> ARGV[2]
                sub(/^[^=]*=/, "", keyval)
                print keyval >> ARGV[3]
            }
        }
    ' "$1" "$2" "$3"
}

# ファイルから値をJSON配列化（改行区切り→["a","b",...] 形式）
lines_to_json_array() {
    awk -v q='"' '{ gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0); printf("%s%s%s", NR==1 ? "" : ",", q, $0, q) } END { print "" }' "$1"
}

# 100件ずつAPI送信（値ファイル→翻訳配列ファイル）
translate_chunk() {
    val_file="$1"
    src_lang="$2"
    tgt_lang="$3"
    resp_file="$4"

    texts_json=$(lines_to_json_array "$val_file")
    post_body="{\"texts\":[${texts_json}],\"source\":\"${src_lang}\",\"target\":\"${tgt_lang}\"}"

    # メッセージはget_message使用例（従来同様）
    echo "$(get_message "MSG_TRANSLATING_BATCH")" >&2

    wget --header="Content-Type: application/json" \
         --post-data="$post_body" \
         -O "$resp_file" -T 20 -q "$API_URL"
}

# translations配列を抽出し1行ずつ出力（jq非依存/従来互換）
extract_translations() {
    awk '
    BEGIN{inarray=0}
    /"translations"\s*:/{
        inarray=1
        sub(/.*"translations"\s*:\s*\[/,"")
    }
    inarray{
        gsub(/\r/,"")
        while(match($0,/("[^"]*"|null)/)){
            val=substr($0,RSTART,RLENGTH)
            gsub(/^"/,"",val)
            gsub(/"$/,"",val)
            if(val=="null") print ""
            else print val
            $0=substr($0,RSTART+RLENGTH)
        }
        if(match($0,/\]/)){ exit }
    }
    ' "$1"
}

# メイン関数
translate_db_with_worker() {
    local in_db="$1"
    local tgt_lang="$(get_target_lang "$2")"
    local src_lang="$(get_lang_code "$in_db")"
    local keyfile="$TMPDIR/keys.txt"
    local valfile="$TMPDIR/vals.txt"
    local out_db="$TMPDIR/message_${tgt_lang}.db"
    local tmp_trans="$TMPDIR/trans.txt"
    local resp_file="$TMPDIR/resp.$$.$(date +%s).json"

    if [ ! -f "$in_db" ]; then
        echo "$(get_message "MSG_FILE_NOT_FOUND" "i=$in_db")" >&2
        exit 1
    fi

    rm -f "$keyfile" "$valfile" "$out_db" "$tmp_trans"

    extract_keys_values "$in_db" "$keyfile" "$valfile" "$src_lang"

    total_lines=$(wc -l < "$valfile")
    line=1

    while [ $line -le $total_lines ]; do
        sed -n "${line},$((line+CHUNK-1))p" "$valfile" > "$TMPDIR/chunk_vals.txt"
        sed -n "${line},$((line+CHUNK-1))p" "$keyfile" > "$TMPDIR/chunk_keys.txt"

        translate_chunk "$TMPDIR/chunk_vals.txt" "$src_lang" "$tgt_lang" "$resp_file"

        # レスポンス正常→翻訳抽出、異常→空行で埋める
        if [ ! -s "$resp_file" ]; then
            awk '{print ""}' "$TMPDIR/chunk_vals.txt" >> "$tmp_trans"
        else
            extract_translations "$resp_file" >> "$tmp_trans"
        fi

        rm -f "$TMPDIR/chunk_vals.txt" "$TMPDIR/chunk_keys.txt" "$resp_file"
        line=$((line+CHUNK))
    done

    # KEYと翻訳結果を結合してDB出力
    paste -d'|' "$keyfile" "$tmp_trans" | awk -v lang="$tgt_lang" -F'|' '{print lang "|" $1 "=" $2}' > "$out_db"

    echo "$(get_message "MSG_TRANSLATION_COMPLETE" "i=$out_db")" >&2
}

# 実行
translate_db_with_worker "$@"

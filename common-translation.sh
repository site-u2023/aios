#!/bin/sh

# OpenWrt ashシェル専用: message_xx.db一括翻訳（API Worker対応）
# 仕様・ロジックは元ソースを厳守し、API呼び出し部のみ https://translate-api-worker.site-u.workers.dev/translate に変更

CACHE_DIR="/tmp/aios"
CHUNK_SIZE=100
API_URL="https://translate-api-worker.site-u.workers.dev/translate"

# 多言語メッセージ取得（元ソースのget_messageをそのまま利用してください）
# get_message() {
#     # ここは既存の実装を流用
# }

# message.chからの言語コード取得
get_api_lang_code() {
    if [ -f "${CACHE_DIR}/message.ch" ]; then
        local api_lang
        api_lang=$(cat "${CACHE_DIR}/message.ch")
        echo "[DEBUG] Using language code from message.ch: ${api_lang}" >&2
        printf "%s\n" "$api_lang"
        return 0
    fi
    echo "[DEBUG] No message.ch found, defaulting to en" >&2
    printf "en\n"
}

# message_xx.dbの言語コード取得
get_db_lang_code() {
    local dbfile="$1"
    basename "$dbfile" | sed -n 's/^message_\([a-z][a-z]\)\.db$/\1/p'
}

# URL安全エンコード
urlencode() {
    local string="$1"
    local encoded=""
    local i=0
    local c=""
    local length=${#string}
    while [ $i -lt $length ]; do
        c="${string:$i:1}"
        case "$c" in
            [a-zA-Z0-9.~_-]) encoded="${encoded}$c" ;;
            " ") encoded="${encoded}%20" ;;
            *) encoded="${encoded}$(printf "%%%02X" "'$c")" ;;
        esac
        i=$((i + 1))
    done
    printf "%s\n" "$encoded"
}

# 入力DBからKEY,値リスト抽出
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

# ファイル内容をJSON配列へ
lines_to_json_array() {
    awk 'BEGIN{ORS="";print "["} {gsub(/\\/,"\\\\",$0);gsub(/"/,"\\\"",$0);printf("%s\"%s\"",NR==1?"":",",$0)} END{print "]"}' "$1"
}

# 100件ずつAPI Workerへ翻訳リクエスト
translate_api_worker_chunk() {
    local val_file="$1"
    local src_lang="$2"
    local tgt_lang="$3"
    local resp_file="$4"
    local texts_json
    texts_json=$(lines_to_json_array "$val_file")
    local post_body
    post_body="{\"texts\":${texts_json},\"source\":\"${src_lang}\",\"target\":\"${tgt_lang}\"}"
    echo "[DEBUG] Posting chunk to API: $src_lang->$tgt_lang" >&2
    wget --header="Content-Type: application/json" \
         --post-data="$post_body" \
         -O "$resp_file" -T 20 -q "$API_URL"
}

# translations配列抽出（jq等非依存）
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
common_translation_main() {
    local in_db="$1"
    local tgt_lang
    if [ -n "$2" ]; then
        tgt_lang="$2"
    else
        tgt_lang=$(get_api_lang_code)
    fi
    local src_lang
    src_lang=$(get_db_lang_code "$in_db")
    local keyfile="${CACHE_DIR}/keys.txt"
    local valfile="${CACHE_DIR}/vals.txt"
    local out_db="${CACHE_DIR}/message_${tgt_lang}.db"
    local tmp_trans="${CACHE_DIR}/trans.txt"
    local resp_file="${CACHE_DIR}/resp.$$.$(date +%s).json"

    if [ ! -f "$in_db" ]; then
        echo "$(get_message "MSG_FILE_NOT_FOUND" "i=$in_db")" >&2
        exit 1
    fi

    rm -f "$keyfile" "$valfile" "$out_db" "$tmp_trans"

    extract_keys_values "$in_db" "$keyfile" "$valfile" "$src_lang"

    local total_lines line
    total_lines=$(wc -l < "$valfile")
    line=1

    while [ $line -le $total_lines ]; do
        sed -n "${line},$((line+CHUNK_SIZE-1))p" "$valfile" > "${CACHE_DIR}/chunk_vals.txt"
        sed -n "${line},$((line+CHUNK_SIZE-1))p" "$keyfile" > "${CACHE_DIR}/chunk_keys.txt"

        translate_api_worker_chunk "${CACHE_DIR}/chunk_vals.txt" "$src_lang" "$tgt_lang" "$resp_file"

        # エラー時は空行で埋める
        if [ ! -s "$resp_file" ]; then
            awk '{print ""}' "${CACHE_DIR}/chunk_vals.txt" >> "$tmp_trans"
        else
            extract_translations "$resp_file" >> "$tmp_trans"
        fi

        rm -f "${CACHE_DIR}/chunk_vals.txt" "${CACHE_DIR}/chunk_keys.txt" "$resp_file"
        line=$((line+CHUNK_SIZE))
    done

    paste -d'|' "$keyfile" "$tmp_trans" | awk -v lang="$tgt_lang" -F'|' '{print lang "|" $1 "=" $2}' > "$out_db"

    echo "$(get_message "MSG_TRANSLATION_COMPLETE" "i=$out_db")" >&2
}

# 実行
common_translation_main "$@"

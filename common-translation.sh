#!/bin/sh
#
# OpenWrt ashシェル専用: 一括翻訳API呼び出し
# エンドポイント: https://translate-api-worker.site-u.workers.dev/translate
# 入力: /tmp/aios/input.txt (UTF-8, 1行1文)
# 出力: /tmp/aios/output.txt (UTF-8, 1行1翻訳、順序維持)
#

API_URL="https://translate-api-worker.site-u.workers.dev/translate"
SRC_LANG="ja"
TGT_LANG="en"
INPUT_FILE="/tmp/aios/input.txt"
OUTPUT_FILE="/tmp/aios/output.txt"
TMPDIR="/tmp/aios"
CHUNK=100

# デバッグ用メッセージ
debug() {
    # 英語
    echo "[DEBUG] $*" >&2
}

# JSONエスケープ
json_escape() {
    # 引数: $1
    # " と \ をエスケープ
    echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# 配列をJSONに変換
lines_to_json_array() {
    # 引数: ファイル名
    awk -v q='"' '{
        gsub(/\\/,"\\\\",$0)
        gsub(/"/,"\\\"",$0)
        printf("%s%s%s", NR==1 ? "" : ",", q, $0, q)
    } END { print "" }' "$1"
}

# API呼び出し(最大$CHUNK行まで)
translate_chunk() {
    chunk_file="$1"
    # JSON組み立て
    texts_json=$(lines_to_json_array "$chunk_file")
    post_body="{\"texts\":[${texts_json}],\"source\":\"${SRC_LANG}\",\"target\":\"${TGT_LANG}\"}"

    # POST送信(wget)
    debug "POST $API_URL"
    debug "BODY: $post_body"
    # レスポンスは$TMPDIR/resp.$$.jsonに保存
    wget --header="Content-Type: application/json" \
         --post-data="$post_body" \
         -O "$TMPDIR/resp.$$.$RANDOM.json" \
         -T 15 -q "$API_URL"
    echo "$TMPDIR/resp.$$.$RANDOM.json"
}

# レスポンスからtranslations配列を抽出(1行1翻訳)
extract_translations() {
    # 引数: レスポンスファイル
    # translations配列を1行ずつ出力
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

# メイン処理
common_translation_main() {
    [ -d "$TMPDIR" ] || mkdir -p "$TMPDIR"

    : > "$OUTPUT_FILE"
    total_lines=$(wc -l < "$INPUT_FILE")
    line=1

    while [ $line -le $total_lines ]; do
        head -n $((line+CHUNK-1)) "$INPUT_FILE" | tail -n "$CHUNK" > "$TMPDIR/chunk.txt"
        debug "Translating lines $line-$((line+CHUNK-1))"
        resp_file=$(translate_chunk "$TMPDIR/chunk.txt")
        if [ ! -s "$resp_file" ]; then
            # レスポンス無効→空行で埋める
            debug "No response, fill with empty lines"
            awk 'END{for(i=1;i<=NR;i++) print ""}' "$TMPDIR/chunk.txt" >> "$OUTPUT_FILE"
        else
            extract_translations "$resp_file" >> "$OUTPUT_FILE"
        fi
        rm -f "$resp_file" "$TMPDIR/chunk.txt"
        line=$((line+CHUNK))
    done
}

common_translation_main "$@"

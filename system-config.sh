#!/bin/sh
# License: CC0
# OpenWrt >= 19.07
#
# system-config.sh
#
# 本スクリプトは、デバイスの初期設定を行うためのスクリプトです。
# 主な処理内容は以下の通りです：
#  1. 国・ゾーン情報スクリプトのダウンロード
#  2. common-functions.sh のダウンロードと読み込み
#  3. 共通初期化処理 (check_common、country_zone、information) による情報表示
#  4. デバイス名・パスワードの設定 (set_device_name_password)
#  5. Wi-Fi SSID・パスワードの設定 (set_wifi_ssid_password)
#  6. システム全体の設定 (set_device)
echo system-config.sh Last update 202502031310-8

# 定数の設定
BASE_URL="https://raw.githubusercontent.com/site-u2023/aios/main"
BASE_DIR="/tmp/aios"
SUPPORTED_VERSIONS="21 22 23 24 SN"
SUPPORTED_LANGUAGES="en ja zh-cn zh-tw id ko de ru"
INPUT_LANG="$1"

#########################################################################
# download_country_zone: 国・ゾーン情報スクリプトのダウンロード
#########################################################################
download_country_zone() {
    if [ ! -f "${BASE_DIR%/}/country-zone.sh" ]; then
        wget --quiet -O "${BASE_DIR%/}/country-zone.sh" "${BASE_URL}/country-zone.sh" || \
            handle_error "Failed to download country-zone.sh"
    fi
}

#########################################################################
# download_and_execute_common: common-functions.sh をダウンロードし読み込む
#########################################################################
download_and_execute_common() {
    if [ ! -f "${BASE_DIR%/}/common-functions.sh" ]; then
        wget --quiet -O "${BASE_DIR%/}/common-functions.sh" "${BASE_URL}/common-functions.sh" || \
            handle_error "Failed to download common-functions.sh"
    fi

    source "${BASE_DIR%/}/common-functions.sh" || \
        handle_error "Failed to source common-functions.sh"
}

#########################################################################
# select_timezone: 複数のタイムゾーンから選択
#########################################################################
XXXXX_select_timezone() {
    local available_zonename available_timezones selected_timezone selected_zone
    local msg_timezone_single msg_timezone_list msg_select_tz

    # 言語に応じたメッセージ設定
    case "$SELECTED_LANGUAGE" in
        ja)
            msg_timezone_single="タイムゾーン: "
            msg_timezone_list="利用可能なタイムゾーン:"
            msg_select_tz="タイムゾーンの番号を選択してください: "
            ;;
        zh-cn)
            msg_timezone_single="时区: "
            msg_timezone_list="可用时区:"
            msg_select_tz="请选择时区编号: "
            ;;
        zh-tw)
            msg_timezone_single="時區: "
            msg_timezone_list="可用時區:"
            msg_select_tz="請選擇時區編號: "
            ;;
            id)
            msg_timezone_single="Zona waktu: "
            msg_timezone_list="Zona waktu yang tersedia:"
            msg_select_tz="Pilih nomor zona waktu: "
            ;;
        ko)
            msg_timezone_single="시간대: "
            msg_timezone_list="사용 가능한 시간대:"
            msg_select_tz="시간대 번호를 선택하세요: "
            ;;
        de)
            msg_timezone_single="Zeitzone: "
            msg_timezone_list="Verfügbare Zeitzonen:"
            msg_select_tz="Bitte wählen Sie die Zeitzonennummer: "
            ;;
        ru)
            msg_timezone_single="Часовой пояс: "
            msg_timezone_list="Доступные часовые пояса:"
            msg_select_tz="Выберите номер часового пояса: "
            ;;
        en|*) # 英語とその他すべての未定義言語の処理
            msg_timezone_single="Time Zone: "
            msg_timezone_list="Available Time Zones:"
            msg_select_tz="Select the time zone by number: "
            ;;
    esac

    # 都市名とタイムゾーンの情報を取得
    available_zonename=$(sh "${BASE_DIR}/country-zone.sh" "$SELECTED_COUNTRY" "cities")
    available_timezones=$(sh "${BASE_DIR}/country-zone.sh" "$SELECTED_COUNTRY" "offsets")

    # 一時ファイルに保存
    echo "$available_zonename" | tr ',' '\n' > "${BASE_DIR}/zonename_list"
    echo "$available_timezones" | tr ',' '\n' > "${BASE_DIR}/timezone_list"

    total_zonename=$(wc -l < "${BASE_DIR}/zonename_list")

    if [ "$total_zonename" -eq 1 ]; then
        # 1つしかない場合はそのまま表示
        ZONENAME=$(head -n 1 "${BASE_DIR}/zonename_list")
        TIMEZONE=$(head -n 1 "${BASE_DIR}/timezone_list")
        echo "$(color white "${msg_timezone_single}${ZONENAME} - ${TIMEZONE}")"
    else
        # 複数ある場合はリスト表示して選択
        echo "$(color white "$msg_timezone_list")"

        # 並列して都市名とタイムゾーンを表示
        i=1
        while read -r zonename && read -r timezone <&3; do
            echo "[$i] $zonename - $timezone"
            i=$((i+1))
        done < "${BASE_DIR}/zonename_list" 3< "${BASE_DIR}/timezone_list"

        # ユーザーに選択させる
        read -p "$(color white "$msg_select_tz")" selected_index

        ZONENAME=$(sed -n "${selected_index}p" "${BASE_DIR}/zonename_list")
        TIMEZONE=$(sed -n "${selected_index}p" "${BASE_DIR}/timezone_list")

        if [ -z "$ZONENAME" ] || [ -z "$TIMEZONE" ]; then
            # 無効な選択ならデフォルトで1番目を選択
            ZONENAME=$(head -n 1 "${BASE_DIR}/zonename_list")
            TIMEZONE=$(head -n 1 "${BASE_DIR}/timezone_list")
        fi

        echo "$(color white "${msg_timezone_single}${ZONENAME} - ${TIMEZONE}")"
    fi
}

#########################################################################
# information: country_zone で取得済みのゾーン情報を元にシステム情報を表示する
#########################################################################
information() {
    local country_name="$ZONENAME"
    local display_name="$DISPLAYNAME"
    local language_code="$LANGUAGE"
    local country_code="$COUNTRYCODE"

    case "$SELECTED_LANGUAGE" in
        ja)
            echo -e "$(color white "国名: $country_name")"
            echo -e "$(color white "表示名: $display_name")"
            echo -e "$(color white "言語コード: $language_code")"
            echo -e "$(color white "国コード: $country_code")"
            ;;
        zh-cn)
            echo -e "$(color white "国家: $country_name")"
            echo -e "$(color white "显示名称: $display_name")"
            echo -e "$(color white "语言代码: $language_code")"
            echo -e "$(color white "国家代码: $country_code")"
            ;;
        zh-tw)
            echo -e "$(color white "國家: $country_name")"
            echo -e "$(color white "顯示名稱: $display_name")"
            echo -e "$(color white "語言代碼: $language_code")"
            echo -e "$(color white "國家代碼: $country_code")"
            ;;
        id)
            echo -e "$(color white "Nama Negara: $country_name")"
            echo -e "$(color white "Nama Tampilan: $display_name")"
            echo -e "$(color white "Kode Bahasa: $language_code")"
            echo -e "$(color white "Kode Negara: $country_code")"
            ;;
        ko)
            echo -e "$(color white "국가명: $country_name")"
            echo -e "$(color white "표시 이름: $display_name")"
            echo -e "$(color white "언어 코드: $language_code")"
            echo -e "$(color white "국가 코드: $country_code")"
            ;;
        de)
            echo -e "$(color white "Ländername: $country_name")"
            echo -e "$(color white "Anzeigename: $display_name")"
            echo -e "$(color white "Sprachcode: $language_code")"
            echo -e "$(color white "Ländercode: $country_code")"
            ;;
        ru)
            echo -e "$(color white "Название страны: $country_name")"
            echo -e "$(color white "Отображаемое имя: $display_name")"
            echo -e "$(color white "Код языка: $language_code")"
            echo -e "$(color white "Код страны: $country_code")"
            ;;
        en|*) # 英語とその他すべての未定義言語の処理
            echo -e "$(color white "Country: $country_name")"
            echo -e "$(color white "Display Name: $display_name")"
            echo -e "$(color white "Language Code: $language_code")"
            echo -e "$(color white "Country Code: $country_code")"
            ;;
    esac
}

#########################################################################
# set_device_name_password: デバイス名とパスワードの設定を行う
# ユーザーから入力を受け、確認後、ubus および uci で更新する
#########################################################################
set_device_name_password() {
    local device_name password confirmation
    local lang msg_device msg_password msg_confirm msg_success msg_cancel

    lang="$SELECTED_LANGUAGE"
    case "$lang" in
        ja)
            msg_device="新しいデバイス名を入力してください: "
            msg_password="新しいパスワードを入力してください: "
            msg_confirm="以下の内容でよろしいですか？ (y/n): "
            msg_success="パスワードとデバイス名が正常に更新されました。"
            msg_cancel="設定がキャンセルされました。"
            ;;
        zh-cn)
            msg_device="请输入新的设备名称: "
            msg_password="请输入新的密码: "
            msg_confirm="您确认以下设置吗？ (y/n): "
            msg_success="密码和设备名称已成功更新。"
            msg_cancel="操作已取消。"
            ;;
        zh-tw)
            msg_device="請輸入新的設備名稱: "
            msg_password="請輸入新的密碼: "
            msg_confirm="您確認以下設定嗎？ (y/n): "
            msg_success="密碼和設備名稱已成功更新。"
            msg_cancel="操作已取消。"
            ;;
        id)
            msg_device="Masukkan nama perangkat baru: "
            msg_password="Masukkan kata sandi baru: "
            msg_confirm="Apakah Anda yakin dengan pengaturan berikut? (y/n): "
            msg_success="Kata sandi dan nama perangkat berhasil diperbarui."
            msg_cancel="Pengaturan telah dibatalkan."
            ;;
        ko)
            msg_device="새 장치 이름을 입력하세요: "
            msg_password="새 비밀번호를 입력하세요: "
            msg_confirm="다음 설정으로 진행하시겠습니까? (y/n): "
            msg_success="비밀번호와 장치 이름이 성공적으로 업데이트되었습니다."
            msg_cancel="설정이 취소되었습니다."
            ;;
        de)
            msg_device="Geben Sie den neuen Gerätenamen ein: "
            msg_password="Geben Sie das neue Passwort ein: "
            msg_confirm="Sind Sie mit den folgenden Einstellungen einverstanden? (y/n): "
            msg_success="Passwort und Gerätename wurden erfolgreich aktualisiert."
            msg_cancel="Die Einstellungen wurden abgebrochen."
            ;;
        ru)
            msg_device="Введите новое имя устройства: "
            msg_password="Введите новый пароль: "
            msg_confirm="Вы уверены в следующих настройках? (y/n): "
            msg_success="Пароль и имя устройства успешно обновлены."
            msg_cancel="Настройки были отменены."
            ;;
        en|*) # 英語とその他すべての未定義言語の処理
            msg_device="Enter the new device name: "
            msg_password="Enter the new password: "
            msg_confirm="Are you sure with the following settings? (y/n): "
            msg_success="Password and device name have been successfully updated."
            msg_cancel="Operation has been canceled."
            ;;
    esac

    echo "Starting device name and password update process..."
    read -p "$msg_device" device_name
    read -s -p "$msg_password" password
    echo
    # 確認プロンプトは共通の ask_confirmation() も利用できるが、ここは独自の確認文言を使用
    echo "Device Name: $device_name"
    echo "Password: $password"
    read -p "$msg_confirm" confirmation
    if [ "$confirmation" != "y" ]; then
        echo "$msg_cancel"
        return 1
    fi

    echo "Updating password and device name..."
    ubus call luci setPassword "{ \"username\": \"root\", \"password\": \"$password\" }" || {
        echo "Failed to update password."
        return 1
    }

    uci set system.@system[0].hostname="$device_name" || {
        echo "Failed to update device name."
        return 1
    }

    uci commit system || {
        echo "Failed to commit changes."
        return 1
    }

    echo "$msg_success"
}

#########################################################################
# set_wifi_ssid_password: Wi-Fi の SSID とパスワードを設定する
# 各 Wi-Fi デバイスごとにユーザー入力を受け、uci コマンドで更新する
#########################################################################
set_wifi_ssid_password() {
    local device iface iface_num ssid password enable_band band htmode devices
    local wifi_country_code=$(echo "$ZONENAME" | awk '{print $4}')
    local lang msg_no_devices msg_band msg_enter_ssid msg_enter_password msg_password_invalid
    local msg_updated msg_select_band msg_confirm msg_reenter msg_invalid
    
    lang="$SELECTED_LANGUAGE"
    case "$lang" in
        ja)
            msg_no_devices="Wi-Fiデバイスが見つかりません。終了します。"
            msg_band="デバイス %s (帯域: %s)"
            msg_enter_ssid="SSIDを入力してください: "
            msg_enter_password="パスワードを入力してください (8文字以上): "
            msg_password_invalid="パスワードは8文字以上で入力してください。"
            msg_updated="デバイス %s の設定が更新されました。"
            msg_select_band="デバイス %s のバンド %s を有効にしますか？(y/n): "
            msg_confirm="設定内容: SSID = %s, パスワード = %s。これで良いですか？ (y/n): "
            msg_reenter="もう一度入力してください。"
            msg_invalid="無効な入力です。y または n を入力してください。"
            ;;
        zh-cn)
            msg_no_devices="未找到Wi-Fi设备。正在退出。"
            msg_band="设备 %s (频段: %s)"
            msg_enter_ssid="请输入SSID: "
            msg_enter_password="请输入密码（8个字符以上）: "
            msg_password_invalid="密码必须至少包含8个字符。"
            msg_updated="设备 %s 的设置已更新。"
            msg_select_band="启用设备 %s 的频段 %s？(y/n): "
            msg_confirm="配置信息: SSID = %s, 密码 = %s。是否正确？(y/n): "
            msg_reenter="请重新输入信息。"
            msg_invalid="输入无效。请输入'y'或'n'。"
            ;;
        zh-tw)
            msg_no_devices="未找到Wi-Fi裝置。正在退出。"
            msg_band="裝置 %s (頻段: %s)"
            msg_enter_ssid="請輸入SSID: "
            msg_enter_password="請輸入密碼（8個字元以上）: "
            msg_password_invalid="密碼必須至少包含8個字元。"
            msg_updated="裝置 %s 的設定已更新。"
            msg_select_band="啟用裝置 %s 的頻段 %s？(y/n): "
            msg_confirm="設定資訊: SSID = %s, 密碼 = %s。是否正確？(y/n): "
            msg_reenter="請重新輸入資訊。"
            msg_invalid="輸入無效。請輸入'y'或'n'。"
            ;;
        id)
            msg_no_devices="Perangkat Wi-Fi tidak ditemukan. Keluar."
            msg_band="Perangkat %s (Pita: %s)"
            msg_enter_ssid="Masukkan SSID: "
            msg_enter_password="Masukkan kata sandi (minimal 8 karakter): "
            msg_password_invalid="Kata sandi harus terdiri dari minimal 8 karakter."
            msg_updated="Pengaturan perangkat %s telah diperbarui."
            msg_select_band="Aktifkan pita %s di perangkat %s? (y/n): "
            msg_confirm="Konfigurasi: SSID = %s, Kata Sandi = %s. Apakah ini benar? (y/n): "
            msg_reenter="Silakan masukkan kembali informasi."
            msg_invalid="Masukan tidak valid. Harap masukkan 'y' atau 'n'."
            ;;
        ko)
            msg_no_devices="Wi-Fi 장치를 찾을 수 없습니다. 종료합니다."
            msg_band="장치 %s (대역: %s)"
            msg_enter_ssid="SSID를 입력하세요: "
            msg_enter_password="비밀번호를 입력하세요 (8자 이상): "
            msg_password_invalid="비밀번호는 최소 8자 이상이어야 합니다."
            msg_updated="장치 %s의 설정이 업데이트되었습니다."
            msg_select_band="장치 %s에서 대역 %s를 활성화하시겠습니까? (y/n): "
            msg_confirm="설정 내용: SSID = %s, 비밀번호 = %s. 이대로 진행하시겠습니까? (y/n): "
            msg_reenter="정보를 다시 입력하세요."
            msg_invalid="잘못된 입력입니다. 'y' 또는 'n'을 입력하세요."
            ;;
        de)
            msg_no_devices="Keine Wi-Fi-Geräte gefunden. Beenden."
            msg_band="Gerät %s (Band: %s)"
            msg_enter_ssid="Bitte SSID eingeben: "
            msg_enter_password="Bitte Passwort eingeben (mindestens 8 Zeichen): "
            msg_password_invalid="Das Passwort muss mindestens 8 Zeichen lang sein."
            msg_updated="Die Einstellungen für Gerät %s wurden aktualisiert."
            msg_select_band="Band %s auf Gerät %s aktivieren? (y/n): "
            msg_confirm="Konfiguration: SSID = %s, Passwort = %s. Ist das korrekt? (y/n): "
            msg_reenter="Bitte geben Sie die Informationen erneut ein."
            msg_invalid="Ungültige Eingabe. Bitte 'y' oder 'n' eingeben."
            ;;
        ru)
            msg_no_devices="Устройства Wi-Fi не найдены. Завершение работы."
            msg_band="Устройство %s (Диапазон: %s)"
            msg_enter_ssid="Введите SSID: "
            msg_enter_password="Введите пароль (не менее 8 символов): "
            msg_password_invalid="Пароль должен содержать не менее 8 символов."
            msg_updated="Настройки устройства %s были обновлены."
            msg_select_band="Включить диапазон %s на устройстве %s? (y/n): "
            msg_confirm="Конфигурация: SSID = %s, Пароль = %s. Это правильно? (y/n): "
            msg_reenter="Пожалуйста, введите информацию заново."
            msg_invalid="Неверный ввод. Пожалуйста, введите 'y' или 'n'."
            ;;
        en|*) # 英語とその他すべての未定義言語の処理
            msg_no_devices="No Wi-Fi devices found. Exiting."
            msg_band="Device %s (Band: %s)"
            msg_enter_ssid="Enter SSID: "
            msg_enter_password="Enter password (8 or more characters): "
            msg_password_invalid="Password must be at least 8 characters long."
            msg_updated="Device %s settings have been updated."
            msg_select_band="Enable band %s on device %s? (y/n): "
            msg_confirm="Configuration: SSID = %s, Password = %s. Is this correct? (y/n): "
            msg_reenter="Please re-enter the information."
            msg_invalid="Invalid input. Please enter 'y' or 'n'."
            ;;
    esac

    devices=$(uci show wireless | grep 'wifi-device' | cut -d'=' -f1 | cut -d'.' -f2 | sort -u)
    if [ -z "$devices" ]; then
        echo "$msg_no_devices"
        exit 1
    fi

    for device in $devices; do
        band=$(uci get wireless."$device".band 2>/dev/null)
        htmode=$(uci get wireless."$device".htmode 2>/dev/null)

        printf "$msg_band\n" "$device" "$band"
        printf "$msg_select_band" "$device" "$band"
        read enable_band
        if [ "$enable_band" != "y" ]; then
            continue
        fi

        iface_num=$(echo "$device" | grep -o '[0-9]*')
        iface="aios${iface_num}"

        printf "$msg_enter_ssid"
        read ssid
        while true; do
            printf "$msg_enter_password"
            read -s password
            echo
            if [ "${#password}" -ge 8 ]; then
                break
            else
                echo "$msg_password_invalid"
            fi
        done

        while true; do
            printf "$msg_confirm\n" "$ssid" "$password"
            read confirm
            if [ "$confirm" = "y" ]; then
                break
            elif [ "$confirm" = "n" ]; then
                echo "$msg_reenter"
                break
            else
                echo "$msg_invalid"
            fi
        done

        uci set wireless."$iface"="wifi-iface"
        uci set wireless."$iface".device="${device:-aios}"
        uci set wireless."$iface".mode='ap'
        uci set wireless."$iface".ssid="${ssid:-openwrt}"
        uci set wireless."$iface".key="${password:-password}"
        uci set wireless."$iface".encryption="${encryption:-sae-mixed}"
        uci set wireless."$iface".network='lan'
        uci set wireless."$device".country="$wifi_country_code"
        uci -q delete wireless."$device".disabled

        devices_to_enable="$devices_to_enable $device"
    done

    uci commit wireless
    /etc/init.d/network reload

    for device in $devices_to_enable; do
        printf "$msg_updated\n" "$device"
    done
}

#########################################################################
# set_device: デバイス全体の設定を行い、最終的にリブートを実行する
#  ※ SSH ドロップベア設定、システム設定、NTP サーバ設定、ファイアウォール・パケットスティアリング、
#     カスタム DNS 設定などを uci コマンドで行う。
#########################################################################
set_device() {
    # SSH アクセス用のインターフェース設定
    uci set dropbear.@dropbear[0].Interface='lan'
    uci commit dropbear

    # システム基本設定
    local DESCRIPTION NOTES _zonename _timezone
    DESCRIPTION=$(cat /etc/openwrt_version) || DESCRIPTION="Unknown"
    NOTES=$(date) || NOTES="No date"
    # ZONENAME, TIMEZONE は country_zone で取得済み、TIMEZONE は select_timezone で選択
    _zonename=$(echo "$ZONENAME" | awk '{print $1}' 2>/dev/null || echo "Unknown")
    _timezone="${TIMEZONE:-UTC}"

    echo "Applying zonename settings: $_zonename"
    echo "Applying timezone settings: $_timezone"

    uci set system.@system[0]=system
    #uсi set system.@system[0].hostname=${HOSTNAME}  # 必要に応じてコメント解除
    uci set system.@system[0].description="${DESCRIPTION}"
    uci set system.@system[0].zonename="$_zonename"
    uci set system.@system[0].timezone="$_timezone"
    uci set system.@system[0].conloglevel='6'
    uci set system.@system[0].cronloglevel='9'
    # NTP サーバ設定
    uci set system.ntp.enable_server='1'
    uci set system.ntp.use_dhcp='0'
    uci set system.ntp.interface='lan'
    uci delete system.ntp.server
    uci add_list system.ntp.server='0.pool.ntp.org'
    uci add_list system.ntp.server='1.pool.ntp.org'
    uci add_list system.ntp.server='2.pool.ntp.org'
    uci add_list system.ntp.server='3.pool.ntp.org'
    uci commit system
    /etc/init.d/system reload
    /etc/init.d/sysntpd restart
    # ノート設定
    uci set system.@system[0].notes="${NOTES}"
    uci commit system
    /etc/init.d/system reload

    # ソフトウェアフローオフロード
    uci set firewall.@defaults[0].flow_offloading='1'
    uci commit firewall

    # ハードウェアフローオフロード（mediatek 判定）
    local Hardware_flow_offload
    Hardware_flow_offload=$(grep 'mediatek' /etc/openwrt_release)
    if [ "${Hardware_flow_offload:16:8}" = "mediatek" ]; then
        uci set firewall.@defaults[0].flow_offloading_hw='1'
        uci commit firewall
    fi

    # パケットステアリング
    uci set network.globals.packet_steering='1'
    uci commit network

    # カスタム DNS 設定
    uci -q delete dhcp.lan.dhcp_option
    uci -q delete dhcp.lan.dns
    # IPV4 DNS
    uci add_list dhcp.lan.dhcp_option="6,1.1.1.1,8.8.8.8"
    uci add_list dhcp.lan.dhcp_option="6,1.0.0.1,8.8.4.4"
    # IPV6 DNS
    uci add_list dhcp.lan.dns="2606:4700:4700::1111"
    uci add_list dhcp.lan.dns="2001:4860:4860::8888"
    uci add_list dhcp.lan.dns="2606:4700:4700::1001"
    uci add_list dhcp.lan.dns="2001:4860:4860::8844"
    uci set dhcp.@dnsmasq[0].cachesize='2000'
    uci set dhcp.lan.leasetime='24h'
    uci commit dhcp

    # ネットワークサービスの再起動
    #/etc/init.d/dnsmasq restart
    #/etc/init.d/odhcpd restart

    read -p "Press any key to reboot the device"
    reboot
}

#########################################################################
# メイン処理の開始
#########################################################################
download_country_zone
download_and_execute_common
check_common "$INPUT_LANG"

# 国選択プロセスの実行（新規実装の関数）
process_country_selection

# 国・言語・ゾーン情報の表示
information

# タイムゾーンの選択（common-functions.sh の関数を利用）
select_timezone "$SELECTED_COUNTRY"

# デバイス設定（必要に応じてコメントアウト解除）
#set_device_name_password
#set_wifi_ssid_password
#set_device

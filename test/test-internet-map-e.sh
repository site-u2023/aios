#!/bin/ash

# Based on script from https://ipv4.web.fc2.com/map-e.html, with appreciation.

SCRIPT_VERSION="2025.06.03-01-00"

# OpenWrt関数をロード
. /lib/functions.sh
. /lib/functions/network.sh
. /lib/netifd/netifd-proto.sh

# プレフィックスに対応するIPv4ベースアドレスを取得（prefix31用）
get_ruleprefix31_value() {
    local prefix="$1"

    case "$prefix" in
        "0x240b0010") echo "106,72" ;;
        "0x240b0012") echo "14,8" ;;
        "0x240b0250") echo "14,10" ;;
        "0x240b0252") echo "14,12" ;;
        "0x24047a80") echo "133,200" ;;
        "0x24047a84") echo "133,206" ;;
        *) echo "" ;;
    esac
}

# プレフィックスに対応するIPv4ベースアドレスを取得（prefix38用）
get_ruleprefix38_value() {
    local prefix="$1"

    case "$prefix" in
        "0x24047a8200") echo "125,196,208" ;;
        "0x24047a8204") echo "125,196,212" ;;
        "0x24047a8208") echo "125,198,140" ;;
        "0x24047a820c") echo "125,198,144" ;;
        "0x24047a8210") echo "125,198,212" ;;
        "0x24047a8214") echo "125,198,244" ;;
        "0x24047a8218") echo "122,131,104" ;;
        "0x24047a821c") echo "125,195,20" ;;
        "0x24047a8220") echo "133,203,160" ;;
        "0x24047a8224") echo "133,203,164" ;;
        "0x24047a8228") echo "133,203,168" ;;
        "0x24047a822c") echo "133,203,172" ;;
        "0x24047a8230") echo "133,203,176" ;;
        "0x24047a8234") echo "133,203,180" ;;
        "0x24047a8238") echo "133,203,184" ;;
        "0x24047a823c") echo "133,203,188" ;;
        "0x24047a8240") echo "133,209,0" ;;
        "0x24047a8244") echo "133,209,4" ;;
        "0x24047a8248") echo "133,209,8" ;;
        "0x24047a824c") echo "133,209,12" ;;
        "0x24047a8250") echo "133,209,16" ;;
        "0x24047a8254") echo "133,209,20" ;;
        "0x24047a8258") echo "133,209,24" ;;
        "0x24047a825c") echo "133,209,28" ;;
        "0x24047a8260") echo "133,204,192" ;;
        "0x24047a8264") echo "133,204,196" ;;
        "0x24047a8268") echo "133,204,200" ;;
        "0x24047a826c") echo "133,204,204" ;;
        "0x24047a8270") echo "133,204,208" ;;
        "0x24047a8274") echo "133,204,212" ;;
        "0x24047a8278") echo "133,204,216" ;;
        "0x24047a827c") echo "133,204,220" ;;
        "0x24047a8280") echo "133,203,224" ;;
        "0x24047a8284") echo "133,203,228" ;;
        "0x24047a8288") echo "133,203,232" ;;
        "0x24047a828c") echo "133,203,236" ;;
        "0x24047a8290") echo "133,203,240" ;;
        "0x24047a8294") echo "133,203,244" ;;
        "0x24047a8298") echo "133,203,248" ;;
        "0x24047a829c") echo "133,203,252" ;;
        "0x24047a82a0") echo "125,194,192" ;;
        "0x24047a82a4") echo "125,194,196" ;;
        "0x24047a82a8") echo "125,194,200" ;;
        "0x24047a82ac") echo "125,194,204" ;;
        "0x24047a82b0") echo "119,239,128" ;;
        "0x24047a82b4") echo "119,239,132" ;;
        "0x24047a82b8") echo "119,239,136" ;;
        "0x24047a82bc") echo "119,239,140" ;;
        "0x24047a82c0") echo "125,194,32" ;;
        "0x24047a82c4") echo "125,194,36" ;;
        "0x24047a82c8") echo "125,194,40" ;;
        "0x24047a82cc") echo "125,194,44" ;;
        "0x24047a82d0") echo "125,195,24" ;;
        "0x24047a82d4") echo "125,195,28" ;;
        "0x24047a82d8") echo "122,130,192" ;;
        "0x24047a82dc") echo "122,130,196" ;;
        "0x24047a82e0") echo "122,135,64" ;;
        "0x24047a82e4") echo "122,135,68" ;;
        "0x24047a82e8") echo "125,192,240" ;;
        "0x24047a82ec") echo "125,192,244" ;;
        "0x24047a82f0") echo "125,193,176" ;;
        "0x24047a82f4") echo "125,193,180" ;;
        "0x24047a82f8") echo "122,130,176" ;;
        "0x24047a82fc") echo "122,130,180" ;;
        "0x24047a8300") echo "122,131,24" ;;
        "0x24047a8304") echo "122,131,28" ;;
        "0x24047a8308") echo "122,131,32" ;;
        "0x24047a830c") echo "122,131,36" ;;
        "0x24047a8310") echo "119,243,112" ;;
        "0x24047a8314") echo "119,243,116" ;;
        "0x24047a8318") echo "219,107,136" ;;
        "0x24047a831c") echo "219,107,140" ;;
        "0x24047a8320") echo "220,144,224" ;;
        "0x24047a8324") echo "220,144,228" ;;
        "0x24047a8328") echo "125,194,64" ;;
        "0x24047a832c") echo "125,194,68" ;;
        "0x24047a8330") echo "221,171,40" ;;
        "0x24047a8334") echo "221,171,44" ;;
        "0x24047a8338") echo "110,233,80" ;;
        "0x24047a833c") echo "110,233,84" ;;
        "0x24047a8340") echo "119,241,184" ;;
        "0x24047a8344") echo "119,241,188" ;;
        "0x24047a8348") echo "119,243,56" ;;
        "0x24047a834c") echo "119,243,60" ;;
        "0x24047a8350") echo "125,199,8" ;;
        "0x24047a8354") echo "125,199,12" ;;
        "0x24047a8358") echo "125,196,96" ;;
        "0x24047a835c") echo "125,196,100" ;;
        "0x24047a8360") echo "122,130,104" ;;
        "0x24047a8364") echo "122,130,108" ;;
        "0x24047a8368") echo "122,130,112" ;;
        "0x24047a836c") echo "122,130,116" ;;
        "0x24047a8370") echo "49,129,152" ;;
        "0x24047a8374") echo "49,129,156" ;;
        "0x24047a8378") echo "49,129,192" ;;
        "0x24047a837c") echo "49,129,196" ;;
        "0x24047a8380") echo "49,129,120" ;;
        "0x24047a8384") echo "49,129,124" ;;
        "0x24047a8388") echo "221,170,40" ;;
        "0x24047a838c") echo "221,170,44" ;;
        "0x24047a8390") echo "60,239,108" ;;
        "0x24047a8394") echo "60,236,24" ;;
        "0x24047a8398") echo "122,130,120" ;;
        "0x24047a839c") echo "60,236,84" ;;
        "0x24047a83a0") echo "60,239,180" ;;
        "0x24047a83a4") echo "60,239,184" ;;
        "0x24047a83a8") echo "118,110,136" ;;
        "0x24047a83ac") echo "119,242,136" ;;
        "0x24047a83b0") echo "60,238,188" ;;
        "0x24047a83b4") echo "60,238,204" ;;
        "0x24047a83b8") echo "122,134,52" ;;
        "0x24047a83bc") echo "119,244,60" ;;
        "0x24047a83c0") echo "119,243,100" ;;
        "0x24047a83c4") echo "221,170,236" ;;
        "0x24047a83c8") echo "221,171,48" ;;
        "0x24047a83cc") echo "60,238,36" ;;
        "0x24047a83d0") echo "125,195,236" ;;
        "0x24047a83d4") echo "60,236,20" ;;
        "0x24047a83d8") echo "118,108,76" ;;
        "0x24047a83dc") echo "118,110,108" ;;
        "0x24047a83e0") echo "118,110,112" ;;
        "0x24047a83e4") echo "118,111,88" ;;
        "0x24047a83e8") echo "118,111,228" ;;
        "0x24047a83ec") echo "118,111,236" ;;
        "0x24047a83f0") echo "119,241,148" ;;
        "0x24047a83f4") echo "119,242,124" ;;
        "0x24047a83f8") echo "125,194,28" ;;
        "0x24047a83fc") echo "125,194,96" ;;
        "0x24047a8600") echo "133,204,128" ;;
        "0x24047a8604") echo "133,204,132" ;;
        "0x24047a8608") echo "133,204,136" ;;
        "0x24047a860c") echo "133,204,140" ;;
        "0x24047a8610") echo "133,204,144" ;;
        "0x24047a8614") echo "133,204,148" ;;
        "0x24047a8618") echo "133,204,152" ;;
        "0x24047a861c") echo "133,204,156" ;;
        "0x24047a8620") echo "133,204,160" ;;
        "0x24047a8624") echo "133,204,164" ;;
        "0x24047a8628") echo "133,204,168" ;;
        "0x24047a862c") echo "133,204,172" ;;
        "0x24047a8630") echo "133,204,176" ;;
        "0x24047a8634") echo "133,204,180" ;;
        "0x24047a8638") echo "133,204,184" ;;
        "0x24047a863c") echo "133,204,188" ;;
        "0x24047a8640") echo "133,203,192" ;;
        "0x24047a8644") echo "133,203,196" ;;
        "0x24047a8648") echo "133,203,200" ;;
        "0x24047a864c") echo "133,203,204" ;;
        "0x24047a8650") echo "133,203,208" ;;
        "0x24047a8654") echo "133,203,212" ;;
        "0x24047a8658") echo "133,203,216" ;;
        "0x24047a865c") echo "133,203,220" ;;
        "0x24047a8660") echo "133,204,0" ;;
        "0x24047a8664") echo "133,204,4" ;;
        "0x24047a8668") echo "133,204,8" ;;
        "0x24047a866c") echo "133,204,12" ;;
        "0x24047a8670") echo "133,204,16" ;;
        "0x24047a8674") echo "133,204,20" ;;
        "0x24047a8678") echo "133,204,24" ;;
        "0x24047a867c") echo "133,204,28" ;;
        "0x24047a8680") echo "133,204,64" ;;
        "0x24047a8684") echo "133,204,68" ;;
        "0x24047a8688") echo "133,204,72" ;;
        "0x24047a868c") echo "133,204,76" ;;
        "0x24047a8690") echo "133,204,80" ;;
        "0x24047a8694") echo "133,204,84" ;;
        "0x24047a8698") echo "133,204,88" ;;
        "0x24047a869c") echo "133,204,92" ;;
        "0x24047a86a0") echo "221,171,112" ;;
        "0x24047a86a4") echo "221,171,116" ;;
        "0x24047a86a8") echo "221,171,120" ;;
        "0x24047a86ac") echo "221,171,124" ;;
        "0x24047a86b0") echo "125,195,184" ;;
        "0x24047a86b4") echo "125,196,216" ;;
        "0x24047a86b8") echo "221,171,108" ;;
        "0x24047a86bc") echo "219,107,152" ;;
        "0x24047a86c0") echo "60,239,128" ;;
        "0x24047a86c4") echo "60,239,132" ;;
        "0x24047a86c8") echo "60,239,136" ;;
        "0x24047a86cc") echo "60,239,140" ;;
        "0x24047a86d0") echo "118,110,80" ;;
        "0x24047a86d4") echo "118,110,84" ;;
        "0x24047a86d8") echo "118,110,88" ;;
        "0x24047a86dc") echo "118,110,92" ;;
        "0x24047a86e0") echo "125,194,176" ;;
        "0x24047a86e4") echo "125,194,180" ;;
        "0x24047a86e8") echo "125,194,184" ;;
        "0x24047a86ec") echo "125,194,188" ;;
        "0x24047a86f0") echo "60,239,112" ;;
        "0x24047a86f4") echo "60,239,116" ;;
        "0x24047a86f8") echo "60,239,120" ;;
        "0x24047a86fc") echo "60,239,124" ;;
        "0x24047a8700") echo "125,195,56" ;;
        "0x24047a8704") echo "125,195,60" ;;
        "0x24047a8708") echo "125,196,32" ;;
        "0x24047a870c") echo "125,196,36" ;;
        "0x24047a8710") echo "118,108,80" ;;
        "0x24047a8714") echo "118,108,84" ;;
        "0x24047a8718") echo "118,111,80" ;;
        "0x24047a871c") echo "118,111,84" ;;
        "0x24047a8720") echo "218,227,176" ;;
        "0x24047a8724") echo "218,227,180" ;;
        "0x24047a8728") echo "60,239,208" ;;
        "0x24047a872c") echo "60,239,212" ;;
        "0x24047a8730") echo "118,109,56" ;;
        "0x24047a8734") echo "118,109,60" ;;
        "0x24047a8738") echo "122,131,88" ;;
        "0x24047a873c") echo "122,131,92" ;;
        "0x24047a8740") echo "122,131,96" ;;
        "0x24047a8744") echo "122,131,100" ;;
        "0x24047a8748") echo "122,130,48" ;;
        "0x24047a874c") echo "122,130,52" ;;
        "0x24047a8750") echo "125,198,224" ;;
        "0x24047a8754") echo "125,198,228" ;;
        "0x24047a8758") echo "119,243,104" ;;
        "0x24047a875c") echo "119,243,108" ;;
        "0x24047a8760") echo "118,109,152" ;;
        "0x24047a8764") echo "118,109,156" ;;
        "0x24047a8768") echo "118,111,104" ;;
        "0x24047a876c") echo "118,111,108" ;;
        "0x24047a8770") echo "119,239,48" ;;
        "0x24047a8774") echo "119,239,52" ;;
        "0x24047a8778") echo "122,130,16" ;;
        "0x24047a877c") echo "122,130,20" ;;
        "0x24047a8780") echo "125,196,128" ;;
        "0x24047a8784") echo "125,196,132" ;;
        "0x24047a8788") echo "122,131,48" ;;
        "0x24047a878c") echo "122,131,52" ;;
        "0x24047a8790") echo "122,134,104" ;;
        "0x24047a8794") echo "122,134,108" ;;
        "0x24047a8798") echo "60,238,208" ;;
        "0x24047a879c") echo "60,238,212" ;;
        "0x24047a87a0") echo "220,144,192" ;;
        "0x24047a87a4") echo "220,144,196" ;;
        "0x24047a87a8") echo "110,233,48" ;;
        "0x24047a87ac") echo "122,131,84" ;;
        "0x24047a87b0") echo "111,169,152" ;;
        "0x24047a87b4") echo "119,241,132" ;;
        "0x24047a87b8") echo "119,241,136" ;;
        "0x24047a87bc") echo "119,244,68" ;;
        "0x24047a87c0") echo "60,236,92" ;;
        "0x24047a87c4") echo "60,237,108" ;;
        "0x24047a87c8") echo "60,238,12" ;;
        "0x24047a87cc") echo "60,238,44" ;;
        "0x24047a87d0") echo "60,238,216" ;;
        "0x24047a87d4") echo "60,238,232" ;;
        "0x24047a87d8") echo "49,129,72" ;;
        "0x24047a87dc") echo "110,233,4" ;;
        "0x24047a87e0") echo "110,233,192" ;;
        "0x24047a87e4") echo "119,243,20" ;;
        "0x24047a87e8") echo "119,243,24" ;;
        "0x24047a87ec") echo "125,193,4" ;;
        "0x24047a87f0") echo "125,193,148" ;;
        "0x24047a87f4") echo "118,110,76" ;;
        "0x24047a87f8") echo "118,110,96" ;;
        "0x24047a87fc") echo "125,193,152" ;;
        *) echo "" ;;
    esac
}

# プレフィックスに対応するIPv4ベースアドレスを取得（prefix38_20用）
get_ruleprefix38_20_value() {
    local prefix="$1"

    case "$prefix" in
        "0x2400405000") echo "153,240,0" ;;
        "0x2400405004") echo "153,240,16" ;;
        "0x2400405008") echo "153,240,32" ;;
        "0x240040500c") echo "153,240,48" ;;
        "0x2400405010") echo "153,240,64" ;;
        "0x2400405014") echo "153,240,80" ;;
        "0x2400405018") echo "153,240,96" ;;
        "0x240040501c") echo "153,240,112" ;;
        "0x2400405020") echo "153,240,128" ;;
        "0x2400405024") echo "153,240,144" ;;
        "0x2400405028") echo "153,240,160" ;;
        "0x240040502c") echo "153,240,176" ;;
        "0x2400405030") echo "153,240,192" ;;
        "0x2400405034") echo "153,240,208" ;;
        "0x2400405038") echo "153,240,224" ;;
        "0x240040503c") echo "153,240,240" ;;
        "0x2400405040") echo "153,241,0" ;;
        "0x2400405044") echo "153,241,16" ;;
        "0x2400405048") echo "153,241,32" ;;
        "0x240040504c") echo "153,241,48" ;;
        "0x2400405050") echo "153,241,64" ;;
        "0x2400405054") echo "153,241,80" ;;
        "0x2400405058") echo "153,241,96" ;;
        "0x240040505c") echo "153,241,112" ;;
        "0x2400405060") echo "153,241,128" ;;
        "0x2400405064") echo "153,241,144" ;;
        "0x2400405068") echo "153,241,160" ;;
        "0x240040506c") echo "153,241,176" ;;
        "0x2400405070") echo "153,241,192" ;;
        "0x2400405074") echo "153,241,208" ;;
        "0x2400405078") echo "153,241,224" ;;
        "0x240040507c") echo "153,241,240" ;;
        "0x2400405080") echo "153,242,0" ;;
        "0x2400405084") echo "153,242,16" ;;
        "0x2400405088") echo "153,242,32" ;;
        "0x240040508c") echo "153,242,48" ;;
        "0x2400405090") echo "153,242,64" ;;
        "0x2400405094") echo "153,242,80" ;;
        "0x2400405098") echo "153,242,96" ;;
        "0x240040509c") echo "153,242,112" ;;
        "0x24004050a0") echo "153,242,128" ;;
        "0x24004050a4") echo "153,242,144" ;;
        "0x24004050a8") echo "153,242,160" ;;
        "0x24004050ac") echo "153,242,176" ;;
        "0x24004050b0") echo "153,242,192" ;;
        "0x24004050b4") echo "153,242,208" ;;
        "0x24004050b8") echo "153,242,224" ;;
        "0x24004050bc") echo "153,242,240" ;;
        "0x24004050c0") echo "153,243,0" ;;
        "0x24004050c4") echo "153,243,16" ;;
        "0x24004050c8") echo "153,243,32" ;;
        "0x24004050cc") echo "153,243,48" ;;
        "0x24004050d0") echo "153,243,64" ;;
        "0x24004050d4") echo "153,243,80" ;;
        "0x24004050d8") echo "153,243,96" ;;
        "0x24004050dc") echo "153,243,112" ;;
        "0x24004050e0") echo "153,243,128" ;;
        "0x24004050e4") echo "153,243,144" ;;
        "0x24004050e8") echo "153,243,160" ;;
        "0x24004050ec") echo "153,243,176" ;;
        "0x24004050f0") echo "153,243,192" ;;
        "0x24004050f4") echo "153,243,208" ;;
        "0x24004050f8") echo "153,243,224" ;;
        "0x24004050fc") echo "153,243,240" ;;
        "0x2400405100") echo "122,26,0" ;;
        "0x2400405104") echo "122,26,16" ;;
        "0x2400405108") echo "122,26,32" ;;
        "0x240040510c") echo "122,26,48" ;;
        "0x2400405110") echo "122,26,64" ;;
        "0x2400405114") echo "122,26,80" ;;
        "0x2400405118") echo "122,26,96" ;;
        "0x240040511c") echo "122,26,112" ;;
        "0x2400405120") echo "114,146,64" ;;
        "0x2400405124") echo "114,146,80" ;;
        "0x2400405128") echo "114,146,96" ;;
        "0x240040512c") echo "114,146,112" ;;
        "0x2400405130") echo "114,148,192" ;;
        "0x2400405134") echo "114,148,208" ;;
        "0x2400405138") echo "114,148,224" ;;
        "0x240040513c") echo "114,148,240" ;;
        "0x2400405140") echo "114,150,192" ;;
        "0x2400405144") echo "114,150,208" ;;
        "0x2400405148") echo "114,150,224" ;;
        "0x240040514c") echo "114,150,240" ;;
        "0x2400405150") echo "114,163,64" ;;
        "0x2400405154") echo "114,163,80" ;;
        "0x2400405158") echo "114,163,96" ;;
        "0x240040515c") echo "114,163,112" ;;
        "0x2400405180") echo "114,172,192" ;;
        "0x2400405184") echo "114,172,208" ;;
        "0x2400405188") echo "114,172,224" ;;
        "0x240040518c") echo "114,172,240" ;;
        "0x2400405190") echo "114,177,64" ;;
        "0x2400405194") echo "114,177,80" ;;
        "0x2400405198") echo "114,177,96" ;;
        "0x240040519c") echo "114,177,112" ;;
        "0x24004051a0") echo "118,0,64" ;;
        "0x24004051a4") echo "118,0,80" ;;
        "0x24004051a8") echo "118,0,96" ;;
        "0x24004051ac") echo "118,0,112" ;;
        "0x24004051b0") echo "118,7,64" ;;
        "0x24004051b4") echo "118,7,80" ;;
        "0x24004051b8") echo "118,7,96" ;;
        "0x24004051bc") echo "118,7,112" ;;
        "0x2400405200") echo "123,225,192" ;;
        "0x2400405204") echo "123,225,208" ;;
        "0x2400405208") echo "123,225,224" ;;
        "0x240040520c") echo "123,225,240" ;;
        "0x2400405210") echo "153,134,0" ;;
        "0x2400405214") echo "153,134,16" ;;
        "0x2400405218") echo "153,134,32" ;;
        "0x240040521c") echo "153,134,48" ;;
        "0x2400405220") echo "153,139,128" ;;
        "0x2400405224") echo "153,139,144" ;;
        "0x2400405228") echo "153,139,160" ;;
        "0x240040522c") echo "153,139,176" ;;
        "0x2400405230") echo "153,151,64" ;;
        "0x2400405234") echo "153,151,80" ;;
        "0x2400405238") echo "153,151,96" ;;
        "0x240040523c") echo "153,151,112" ;;
        "0x24004051c0") echo "118,8,192" ;;
        "0x24004051c4") echo "118,8,208" ;;
        "0x24004051c8") echo "118,8,224" ;;
        "0x24004051cc") echo "118,8,240" ;;
        "0x24004051d0") echo "118,9,0" ;;
        "0x24004051d4") echo "118,9,16" ;;
        "0x24004051d8") echo "118,9,32" ;;
        "0x24004051dc") echo "118,9,48" ;;
        "0x24004051e0") echo "123,218,64" ;;
        "0x24004051e4") echo "123,218,80" ;;
        "0x24004051e8") echo "123,218,96" ;;
        "0x24004051ec") echo "123,218,112" ;;
        "0x24004051f0") echo "123,220,128" ;;
        "0x24004051f4") echo "123,220,144" ;;
        "0x24004051f8") echo "123,220,160" ;;
        "0x24004051fc") echo "123,220,176" ;;
        "0x2400405240") echo "153,170,64" ;;
        "0x2400405244") echo "153,170,80" ;;
        "0x2400405248") echo "153,170,96" ;;
        "0x240040524c") echo "153,170,112" ;;
        "0x2400405250") echo "153,170,192" ;;
        "0x2400405254") echo "153,170,208" ;;
        "0x2400405258") echo "153,170,224" ;;
        "0x240040525c") echo "153,170,240" ;;
        "0x2400405260") echo "61,127,128" ;;
        "0x2400405264") echo "61,127,144" ;;
        "0x2400405268") echo "114,146,0" ;;
        "0x240040526c") echo "114,146,16" ;;
        "0x2400405270") echo "114,146,128" ;;
        "0x2400405274") echo "114,146,144" ;;
        "0x2400405278") echo "114,148,64" ;;
        "0x240040527c") echo "114,148,80" ;;
        "0x2400405280") echo "114,148,160" ;;
        "0x2400405284") echo "114,148,176" ;;
        "0x2400405288") echo "114,149,0" ;;
        "0x240040528c") echo "114,149,16" ;;
        "0x2400405290") echo "114,150,160" ;;
        "0x2400405294") echo "114,150,176" ;;
        "0x2400405298") echo "114,158,0" ;;
        "0x240040529c") echo "114,158,16" ;;
        "0x2400405160") echo "114,163,128" ;;
        "0x2400405164") echo "114,163,144" ;;
        "0x2400405168") echo "114,163,160" ;;
        "0x240040516c") echo "114,163,176" ;;
        "0x2400405170") echo "114,167,64" ;;
        "0x2400405174") echo "114,167,80" ;;
        "0x2400405178") echo "114,167,96" ;;
        "0x240040517c") echo "114,167,112" ;;
        "0x2400405300") echo "114,162,128" ;;
        "0x2400405304") echo "114,162,144" ;;
        "0x2400405308") echo "114,163,0" ;;
        "0x240040530c") echo "114,163,16" ;;
        "0x2400405310") echo "114,165,224" ;;
        "0x2400405314") echo "114,165,240" ;;
        "0x2400405318") echo "114,167,192" ;;
        "0x240040531c") echo "114,167,208" ;;
        "0x2400405320") echo "114,177,128" ;;
        "0x2400405324") echo "114,177,144" ;;
        "0x2400405328") echo "114,178,224" ;;
        "0x240040532c") echo "114,178,240" ;;
        "0x2400405330") echo "118,1,0" ;;
        "0x2400405334") echo "118,1,16" ;;
        "0x2400405338") echo "118,3,192" ;;
        "0x240040533c") echo "118,3,208" ;;
        "0x2400405340") echo "118,6,64" ;;
        "0x2400405344") echo "118,6,80" ;;
        "0x2400405348") echo "118,7,160" ;;
        "0x240040534c") echo "118,7,176" ;;
        "0x2400405360") echo "118,9,128" ;;
        "0x2400405364") echo "118,9,144" ;;
        "0x2400405368") echo "118,22,128" ;;
        "0x240040536c") echo "118,22,144" ;;
        "0x2400405370") echo "122,16,0" ;;
        "0x2400405374") echo "122,16,16" ;;
        "0x2400405378") echo "123,220,0" ;;
        "0x240040537c") echo "123,220,16" ;;
        "0x2400405350") echo "118,7,192" ;;
        "0x2400405354") echo "118,7,208" ;;
        "0x2400405358") echo "118,9,64" ;;
        "0x240040535c") echo "118,9,80" ;;
        "0x2400405380") echo "153,173,0" ;;
        "0x2400405384") echo "153,173,16" ;;
        "0x2400405388") echo "153,173,32" ;;
        "0x240040538c") echo "153,173,48" ;;
        "0x2400405390") echo "153,173,64" ;;
        "0x2400405394") echo "153,173,80" ;;
        "0x2400405398") echo "153,173,96" ;;
        "0x240040539c") echo "153,173,112" ;;
        "0x24004053a0") echo "153,173,128" ;;
        "0x24004053a4") echo "153,173,144" ;;
        "0x24004053a8") echo "153,173,160" ;;
        "0x24004053ac") echo "153,173,176" ;;
        "0x24004053b0") echo "153,173,192" ;;
        "0x24004053b4") echo "153,173,208" ;;
        "0x24004053b8") echo "153,173,224" ;;
        "0x24004053bc") echo "153,173,240" ;;
        "0x24004053c0") echo "153,238,0" ;;
        "0x24004053c4") echo "153,238,16" ;;
        "0x24004053c8") echo "153,238,32" ;;
        "0x24004053cc") echo "153,238,48" ;;
        "0x24004053d0") echo "153,238,64" ;;
        "0x24004053d4") echo "153,238,80" ;;
        "0x24004053d8") echo "153,238,96" ;;
        "0x24004053dc") echo "153,238,112" ;;
        "0x24004053e0") echo "153,238,128" ;;
        "0x24004053e4") echo "153,238,144" ;;
        "0x24004053e8") echo "153,238,160" ;;
        "0x24004053ec") echo "153,238,176" ;;
        "0x24004053f0") echo "153,238,192" ;;
        "0x24004053f4") echo "153,238,208" ;;
        "0x24004053f8") echo "153,238,224" ;;
        "0x24004053fc") echo "153,238,240" ;;
        "0x2400415000") echo "153,239,0" ;;
        "0x2400415004") echo "153,239,16" ;;
        "0x2400415008") echo "153,239,32" ;;
        "0x240041500c") echo "153,239,48" ;;
        "0x2400415010") echo "153,239,64" ;;
        "0x2400415014") echo "153,239,80" ;;
        "0x2400415018") echo "153,239,96" ;;
        "0x240041501c") echo "153,239,112" ;;
        "0x2400415020") echo "153,239,128" ;;
        "0x2400415024") echo "153,239,144" ;;
        "0x2400415028") echo "153,239,160" ;;
        "0x240041502c") echo "153,239,176" ;;
        "0x2400415030") echo "153,239,192" ;;
        "0x2400415034") echo "153,239,208" ;;
        "0x2400415038") echo "153,239,224" ;;
        "0x240041503c") echo "153,239,240" ;;
        "0x2400415040") echo "153,252,0" ;;
        "0x2400415044") echo "153,252,16" ;;
        "0x2400415048") echo "153,252,32" ;;
        "0x240041504c") echo "153,252,48" ;;
        "0x2400415050") echo "153,252,64" ;;
        "0x2400415054") echo "153,252,80" ;;
        "0x2400415058") echo "153,252,96" ;;
        "0x240041505c") echo "153,252,112" ;;
        "0x2400415060") echo "153,252,128" ;;
        "0x2400415064") echo "153,252,144" ;;
        "0x2400415068") echo "153,252,160" ;;
        "0x240041506c") echo "153,252,176" ;;
        "0x2400415070") echo "153,252,192" ;;
        "0x2400415074") echo "153,252,208" ;;
        "0x2400415078") echo "153,252,224" ;;
        "0x240041507c") echo "153,252,240" ;;
        "0x2400415080") echo "123,222,96" ;;
        "0x2400415084") echo "123,222,112" ;;
        "0x2400415088") echo "123,225,96" ;;
        "0x240041508c") echo "123,225,112" ;;
        "0x2400415090") echo "123,225,160" ;;
        "0x2400415094") echo "123,225,176" ;;
        "0x2400415098") echo "124,84,96" ;;
        "0x240041509c") echo "124,84,112" ;;
        "0x2400415380") echo "180,12,128" ;;
        "0x2400415384") echo "180,12,144" ;;
        "0x2400415388") echo "180,26,96" ;;
        "0x240041538c") echo "180,26,112" ;;
        "0x2400415390") echo "180,26,160" ;;
        "0x2400415394") echo "180,26,176" ;;
        "0x2400415398") echo "180,26,224" ;;
        "0x240041539c") echo "180,26,240" ;;
        "0x24004153a0") echo "180,30,0" ;;
        "0x24004153a4") echo "180,30,16" ;;
        "0x24004153a8") echo "180,31,96" ;;
        "0x24004153ac") echo "180,31,112" ;;
        "0x24004153c0") echo "180,46,0" ;;
        "0x24004153c4") echo "180,46,16" ;;
        "0x24004153c8") echo "180,48,0" ;;
        "0x24004153cc") echo "180,48,16" ;;
        "0x24004153d0") echo "180,50,192" ;;
        "0x24004153d4") echo "180,50,208" ;;
        "0x24004153d8") echo "180,53,0" ;;
        "0x24004153dc") echo "180,53,16" ;;
        "0x24004153b0") echo "180,32,64" ;;
        "0x24004153b4") echo "180,32,80" ;;
        "0x24004153b8") echo "180,34,160" ;;
        "0x24004153bc") echo "180,34,176" ;;
        "0x24004153e0") echo "218,230,128" ;;
        "0x24004153e4") echo "218,230,144" ;;
        "0x24004153e8") echo "219,161,64" ;;
        "0x24004153ec") echo "219,161,80" ;;
        "0x24004153f0") echo "220,96,64" ;;
        "0x24004153f4") echo "220,96,80" ;;
        "0x24004153f8") echo "220,99,0" ;;
        "0x24004153fc") echo "220,99,16" ;;
        "0x2400415100") echo "180,60,0" ;;
        "0x2400415104") echo "180,60,16" ;;
        "0x2400415108") echo "180,60,32" ;;
        "0x240041510c") echo "180,60,48" ;;
        "0x2400415110") echo "180,60,64" ;;
        "0x2400415114") echo "180,60,80" ;;
        "0x2400415118") echo "180,60,96" ;;
        "0x240041511c") echo "180,60,112" ;;
        "0x2400415120") echo "180,60,128" ;;
        "0x2400415124") echo "180,60,144" ;;
        "0x2400415128") echo "180,60,160" ;;
        "0x240041512c") echo "180,60,176" ;;
        "0x2400415130") echo "180,60,192" ;;
        "0x2400415134") echo "180,60,208" ;;
        "0x2400415138") echo "180,60,224" ;;
        "0x240041513c") echo "180,60,240" ;;
        "0x2400415140") echo "153,139,0" ;;
        "0x2400415144") echo "153,139,16" ;;
        "0x2400415148") echo "153,139,32" ;;
        "0x240041514c") echo "153,139,48" ;;
        "0x2400415150") echo "153,139,64" ;;
        "0x2400415154") echo "153,139,80" ;;
        "0x2400415158") echo "153,139,96" ;;
        "0x240041515c") echo "153,139,112" ;;
        "0x2400415160") echo "219,161,128" ;;
        "0x2400415164") echo "219,161,144" ;;
        "0x2400415168") echo "219,161,160" ;;
        "0x240041516c") echo "219,161,176" ;;
        "0x2400415170") echo "219,161,192" ;;
        "0x2400415174") echo "219,161,208" ;;
        "0x2400415178") echo "219,161,224" ;;
        "0x240041517c") echo "219,161,240" ;;
        "0x24004151c0") echo "124,84,128" ;;
        "0x24004151c4") echo "124,84,144" ;;
        "0x24004151c8") echo "124,98,192" ;;
        "0x24004151cc") echo "124,98,208" ;;
        "0x2400415180") echo "153,187,0" ;;
        "0x2400415184") echo "153,187,16" ;;
        "0x2400415188") echo "153,187,32" ;;
        "0x240041518c") echo "153,187,48" ;;
        "0x2400415190") echo "153,191,0" ;;
        "0x2400415194") echo "153,191,16" ;;
        "0x2400415198") echo "153,191,32" ;;
        "0x240041519c") echo "153,191,48" ;;
        "0x24004151a0") echo "180,12,64" ;;
        "0x24004151a4") echo "180,12,80" ;;
        "0x24004151a8") echo "180,12,96" ;;
        "0x24004151ac") echo "180,12,112" ;;
        "0x24004151b0") echo "180,13,0" ;;
        "0x24004151b4") echo "180,13,16" ;;
        "0x24004151b8") echo "180,13,32" ;;
        "0x24004151bc") echo "180,13,48" ;;
        "0x24004151d0") echo "124,100,0" ;;
        "0x24004151d4") echo "124,100,16" ;;
        "0x24004151d8") echo "124,100,224" ;;
        "0x24004151dc") echo "124,100,240" ;;
        "0x2400415300") echo "153,165,96" ;;
        "0x2400415304") echo "153,165,112" ;;
        "0x2400415308") echo "153,165,160" ;;
        "0x240041530c") echo "153,165,176" ;;
        "0x2400415310") echo "153,171,224" ;;
        "0x2400415314") echo "153,171,240" ;;
        "0x2400415318") echo "153,175,0" ;;
        "0x240041531c") echo "153,175,16" ;;
        "0x2400415344") echo "220,106,48" ;;
        "0x2400415374") echo "220,106,80" ;;
        "0x2400415340") echo "220,106,32" ;;
        "0x2400415370") echo "220,106,64" ;;
        "0x2400415320") echo "153,181,0" ;;
        "0x2400415324") echo "153,181,16" ;;
        "0x2400415328") echo "153,183,224" ;;
        "0x240041532c") echo "153,183,240" ;;
        "0x2400415330") echo "153,184,128" ;;
        "0x2400415334") echo "153,184,144" ;;
        "0x2400415338") echo "153,187,224" ;;
        "0x240041533c") echo "153,187,240" ;;
        "0x2400415360") echo "153,191,192" ;;
        "0x2400415364") echo "153,191,208" ;;
        "0x2400415348") echo "153,188,0" ;;
        "0x240041534c") echo "153,188,16" ;;
        "0x2400415350") echo "153,190,128" ;;
        "0x2400415354") echo "153,190,144" ;;
        "0x2400415358") echo "153,191,64" ;;
        "0x240041535c") echo "153,191,80" ;;
        "0x2400415368") echo "153,194,96" ;;
        "0x240041536c") echo "153,194,112" ;;
        "0x2400415200") echo "180,16,0" ;;
        "0x2400415204") echo "180,16,16" ;;
        "0x2400415208") echo "180,16,32" ;;
        "0x240041520c") echo "180,16,48" ;;
        "0x2400415210") echo "180,29,128" ;;
        "0x2400415214") echo "180,29,144" ;;
        "0x2400415218") echo "180,29,160" ;;
        "0x240041521c") echo "180,29,176" ;;
        "0x2400415220") echo "180,59,64" ;;
        "0x2400415224") echo "180,59,80" ;;
        "0x2400415228") echo "180,59,96" ;;
        "0x240041522c") echo "180,59,112" ;;
        "0x2400415230") echo "219,161,0" ;;
        "0x2400415234") echo "219,161,16" ;;
        "0x2400415238") echo "219,161,32" ;;
        "0x240041523c") echo "219,161,48" ;;
        "0x2400415250") echo "153,131,96" ;;
        "0x2400415254") echo "153,131,112" ;;
        "0x2400415260") echo "153,131,128" ;;
        "0x2400415264") echo "153,131,144" ;;
        "0x2400415268") echo "153,132,128" ;;
        "0x240041526c") echo "153,132,144" ;;
        "0x2400415240") echo "153,129,160" ;;
        "0x2400415244") echo "153,129,176" ;;
        "0x2400415248") echo "153,130,0" ;;
        "0x240041524c") echo "153,130,16" ;;
        "0x2400415270") echo "153,134,64" ;;
        "0x2400415274") echo "153,134,80" ;;
        "0x2400415278") echo "153,137,0" ;;
        "0x240041527c") echo "153,137,16" ;;
        "0x2400415280") echo "153,139,192" ;;
        "0x2400415284") echo "153,139,208" ;;
        "0x2400415288") echo "153,151,32" ;;
        "0x240041528c") echo "153,151,48" ;;
        "0x2400415290") echo "153,156,96" ;;
        "0x2400415294") echo "153,156,112" ;;
        "0x2400415298") echo "153,156,128" ;;
        "0x240041529c") echo "153,156,144" ;;
        *) echo "" ;;
    esac
}

# ======================================================================
# USER INPUT FUNCTION to set global MAP-E variables (auto PD/GUA detect)
# ======================================================================
prompt_for_mape_input() {
    debug_log "DEBUG" "prompt_for_mape_input: Function started."
    printf "\n" 
    printf "%s" "$(color yellow "$(get_message "MENU_INTERNET_MAPE_TEST_MODE")")"
    read -r input_ipv6_prefix

    if [ -z "$input_ipv6_prefix" ]; then
        printf "ERROR: IPv6 prefix cannot be empty.\n" >&2
        debug_log "ERROR" "prompt_for_mape_input: IPv6 prefix was empty."
        return 1
    fi

    # デフォルト値
    local method="unknown"
    local prefix_part="$input_ipv6_prefix"
    local plen=""

    # プレフィックス長（/nnn）があれば分離
    if echo "$input_ipv6_prefix" | grep -q '/'; then
        prefix_part="${input_ipv6_prefix%%/*}"
        plen="${input_ipv6_prefix##*/}"
    fi

    # 自動判定ロジック
    if [ -n "$plen" ]; then
        if [ "$plen" -le 64 ]; then
            method="pd"
        else
            method="gua"
        fi
    else
        # /がない場合、アドレス末尾が::（ゼロ埋め）ならPD寄り
        if echo "$prefix_part" | grep -qE '::$'; then
            method="pd"
        else
            method="gua"
        fi
    fi

    NEW_IP6_PREFIX="$input_ipv6_prefix"
    MAPE_IPV6_ACQUISITION_METHOD="$method"

    debug_log "DEBUG" "prompt_for_mape_input: Auto-detected method='$method', NEW_IP6_PREFIX='$NEW_IP6_PREFIX'"
    return 0
}

# Function to get the source IPv6 information for MAP-E calculation.
# It tries to obtain a global unicast address (GUA) first, then falls back to a delegated prefix (PD).
# Sets global variables:
#   NEW_IP6_PREFIX: The IPv6 address string (full GUA if available, otherwise PD prefix) to be used.
#   MAPE_IPV6_ACQUISITION_METHOD: "gua", "pd", or "none".
# Arguments:
#   $1: WAN interface name (e.g., "wan6")
# Returns:
#   0 on success (NEW_IP6_PREFIX and MAPE_IPV6_ACQUISITION_METHOD are set).
#   1 on failure (NEW_IP6_PREFIX is empty, MAPE_IPV6_ACQUISITION_METHOD is "none").
NG_pd_decision() {
    local wan_iface="$1"
    local delegated_prefix_with_length
    local address_part_for_mape
    local direct_gua
    local ip6assign_current

    # Initialize global variables for this attempt
    NEW_IP6_PREFIX=""
    MAPE_IPV6_ACQUISITION_METHOD="none"

    if [ -z "$wan_iface" ]; then
        debug_log "DEBUG" "pd_decision: WAN interface name not provided."
        return 1
    fi

    # Try to get direct GUA (global unicast address) first
    debug_log "DEBUG" "pd_decision: Attempting to get direct GUA from interface '${wan_iface}'."
    network_get_ipaddr6 direct_gua "${wan_iface}"

    if [ -n "$direct_gua" ]; then
        # Check if the obtained address is global (2000::/3)
        case "$direct_gua" in
            2[0-9a-fA-F]*|3[0-9a-fA-F]*)
                NEW_IP6_PREFIX="$direct_gua"
                MAPE_IPV6_ACQUISITION_METHOD="gua"
                debug_log "DEBUG" "pd_decision: Using direct global GUA: $NEW_IP6_PREFIX"
                return 0 # Success with GUA
                ;;
            fe80:*)
                # Only link-local address found, treat as error
                printf "%s\n" "$(color yellow "$(get_message "MSG_MAPE_GUA_LINKLOCAL_ONLY")")"
                debug_log "DEBUG" "pd_decision: Only link-local IPv6 address detected: $direct_gua"
                return 1
                ;;
            *)
                # Not a recognized global address, fallback to PD
                debug_log "DEBUG" "pd_decision: Not a global GUA, trying PD. Got: $direct_gua"
                ;;
        esac
    else
        debug_log "DEBUG" "pd_decision: No GUA address found, fallback to PD."
    fi

    # Try to get delegated prefix (PD)
    debug_log "DEBUG" "pd_decision: Attempting to get delegated prefix from interface '${wan_iface}'."
    network_get_prefix6 delegated_prefix_with_length "${wan_iface}"

    if [ -n "$delegated_prefix_with_length" ]; then
        address_part_for_mape=$(echo "$delegated_prefix_with_length" | cut -d'/' -f1)
        if [ -n "$address_part_for_mape" ]; then
            NEW_IP6_PREFIX="$address_part_for_mape"
            MAPE_IPV6_ACQUISITION_METHOD="pd"
            debug_log "DEBUG" "pd_decision: Using address part from PD: $NEW_IP6_PREFIX"
            return 0 # Success with PD
        else
            debug_log "DEBUG" "pd_decision: Delegated prefix obtained, but failed to extract address part from '${delegated_prefix_with_length}'."
        fi
    else
        debug_log "DEBUG" "pd_decision: Failed to obtain delegated prefix on '${wan_iface}'."
    fi

    # --- ここから追加: ip6assign未設定時のみセット ---
    ip6assign_current="$(uci -q get network."$wan_iface".ip6assign 2>/dev/null)"
    if [ -z "$ip6assign_current" ]; then
        debug_log "INFO" "pd_decision: ip6assign not set, setting ip6assign=64 and retrying."
        uci -q set network."$wan_iface".ip6assign='64'
        uci -q commit network
        /etc/init.d/network reload >/dev/null 2>&1
        sleep 2

        network_get_prefix6 delegated_prefix_with_length "${wan_iface}"
        if [ -n "$delegated_prefix_with_length" ]; then
            address_part_for_mape=$(echo "$delegated_prefix_with_length" | cut -d'/' -f1)
            if [ -n "$address_part_for_mape" ]; then
                NEW_IP6_PREFIX="$address_part_for_mape"
                MAPE_IPV6_ACQUISITION_METHOD="pd"
                debug_log "INFO" "pd_decision: Using address part from PD after ip6assign=64: $NEW_IP6_PREFIX"
                # クリーンアップ
                debug_log "WARN" "pd_decision: Cleanup ip6assign after fallback."
                uci -q delete network."$wan_iface".ip6assign
                uci -q commit network
                /etc/init.d/network reload >/dev/null 2>&1
                return 0 # Success with PD after fallback
            fi
        fi
        # クリーンアップ
        debug_log "WARN" "pd_decision: Cleanup ip6assign (PD still not obtained after fallback)."
        uci -q delete network."$wan_iface".ip6assign
        uci -q commit network
        /etc/init.d/network reload >/dev/null 2>&1
    else
        debug_log "DEBUG" "pd_decision: ip6assign already set, not overwriting. (current: $ip6assign_current)"
    fi

    debug_log "DEBUG" "pd_decision: Failed to obtain any usable IPv6 information (GUA or PD)."
    return 1 # Failure
}

pd_decision() {
    local wan_iface="$1"
    local delegated_prefix_with_length
    local address_part_for_mape
    local direct_gua

    # Initialize global variables for this attempt
    NEW_IP6_PREFIX=""
    MAPE_IPV6_ACQUISITION_METHOD="none"

    if [ -z "$wan_iface" ]; then
        debug_log "DEBUG" "pd_decision: WAN interface name not provided."
        return 1
    fi

    # Try to get direct GUA (global unicast address) first
    debug_log "DEBUG" "pd_decision: Attempting to get direct GUA from interface '${wan_iface}'."
    network_get_ipaddr6 direct_gua "${wan_iface}"

    if [ -n "$direct_gua" ]; then
        # Check if the obtained address is global (2000::/3)
        case "$direct_gua" in
            2[0-9a-fA-F]*|3[0-9a-fA-F]*)
                NEW_IP6_PREFIX="$direct_gua"
                MAPE_IPV6_ACQUISITION_METHOD="gua"
                debug_log "DEBUG" "pd_decision: Using direct global GUA: $NEW_IP6_PREFIX"
                return 0 # Success with GUA
                ;;
            fe80:*)
                # Only link-local address found, treat as error
                printf "%s\n" "$(color red "$(get_message "MSG_MAPE_GUA_LINKLOCAL_ONLY")")"
                debug_log "DEBUG" "pd_decision: Only link-local IPv6 address detected: $direct_gua"
                return 1
                ;;
            *)
                # Not a recognized global address, fallback to PD
                debug_log "DEBUG" "pd_decision: Not a global GUA, trying PD. Got: $direct_gua"
                ;;
        esac
    else
        debug_log "DEBUG" "pd_decision: No GUA address found, fallback to PD."
    fi

    # Try to get delegated prefix (PD)
    debug_log "DEBUG" "pd_decision: Attempting to get delegated prefix from interface '${wan_iface}'."
    network_get_prefix6 delegated_prefix_with_length "${wan_iface}"

    if [ -n "$delegated_prefix_with_length" ]; then
        address_part_for_mape=$(echo "$delegated_prefix_with_length" | cut -d'/' -f1)
        if [ -n "$address_part_for_mape" ]; then
            NEW_IP6_PREFIX="$address_part_for_mape"
            MAPE_IPV6_ACQUISITION_METHOD="pd"
            debug_log "DEBUG" "pd_decision: Using address part from PD: $NEW_IP6_PREFIX"
            return 0 # Success with PD
        else
            debug_log "DEBUG" "pd_decision: Delegated prefix obtained, but failed to extract address part from '${delegated_prefix_with_length}'."
        fi
    else
        debug_log "DEBUG" "pd_decision: Failed to obtain delegated prefix on '${wan_iface}'."
    fi

    # If both methods failed
    debug_log "DEBUG" "pd_decision: Failed to obtain any usable IPv6 information (GUA or PD)."
    return 1 # Failure
}

mold_mape() {
    local NET_IF6
    if [ -z "$NET_IF6" ]; then
        NET_IF6="wan6"
    fi
    if ! pd_decision "$NET_IF6"; then
        printf "\n%s\n" "$(color yellow "$(get_message "MSG_MAPE_PD_DECISION")")"
        debug_log "ERROR" "mold_mape: pd_decision reported failure."
        # return 1
    fi
    if ! prompt_for_mape_input; then
        debug_log "ERROR" "mold_mape: Failed to get user input via prompt_for_mape_input."
        return 1
    fi
    debug_log "DEBUG" "mold_mape: User input successful. NEW_IP6_PREFIX='$NEW_IP6_PREFIX', METHOD='$MAPE_IPV6_ACQUISITION_METHOD'."

    local ipv6_addr="$NEW_IP6_PREFIX"
    local h0_str h1_str h2_str h3_str
    local awk_output

    awk_output=$(echo "$ipv6_addr" | awk '
    BEGIN {
        FS=":"; OFS=" ";
    }
    {
        num_colons = 0; for (i=1; i<=length($0); i++) { if (substr($0, i, 1) == ":") num_colons++; }
        if (index($0, "::")) {
            left_part = ""; right_part = ""; double_colon_pos = index($0, "::");
            if (double_colon_pos == 1) { right_part = substr($0, 3); }
            else if (double_colon_pos == length($0) - 1) { left_part = substr($0, 1, length($0) - 2); }
            else if (double_colon_pos > 1) { left_part = substr($0, 1, double_colon_pos - 1); right_part = substr($0, double_colon_pos + 2); }
            num_fields_left = 0; if (left_part != "") { split(left_part, arr_left, ":"); num_fields_left = length(arr_left); }
            num_fields_right = 0; if (right_part != "") { split(right_part, arr_right, ":"); num_fields_right = length(arr_right); }
            zeros_to_insert = 8 - (num_fields_left + num_fields_right);
            if ($0 == "::") zeros_to_insert = 8;
            expanded_addr = left_part;
            for (i=1; i<=zeros_to_insert; i++) { expanded_addr = expanded_addr (expanded_addr == "" && left_part == "" ? "" : ":") "0"; }
            if (right_part != "") { expanded_addr = expanded_addr (zeros_to_insert > 0 || left_part != "" ? ":" : "") right_part; }
            if ($0 == "::") expanded_addr = "0:0:0:0:0:0:0:0";
            split(expanded_addr, flds, ":"); NF = length(flds); for(i=1; i<=NF; i++) $i = flds[i];
        } else {
            split($0, flds, ":"); NF = length(flds); for(i=1; i<=NF; i++) $i = flds[i];
        }
        for (i = NF + 1; i <= 8; i++) { $i = "0"; }
        NF = 8;
        h0 = ($1 == "" ? "0" : $1); h1 = ($2 == "" ? "0" : $2); h2 = ($3 == "" ? "0" : $3); h3 = ($4 == "" ? "0" : $4);
        print h0, h1, h2, h3;
    }
    ')

    debug_log "DEBUG" "mold_mape: awk_output='${awk_output}'"

    read -r h0_str h1_str h2_str h3_str <<EOF
$awk_output
EOF
    debug_log "DEBUG" "mold_mape: Parsed hex_strings: h0='${h0_str}', h1='${h1_str}', h2='${h2_str}', h3='${h3_str}'"

    local HEXTET0 HEXTET1 HEXTET2 HEXTET3
    HEXTET0=$((0x${h0_str:-0}))
    HEXTET1=$((0x${h1_str:-0}))
    HEXTET2=$((0x${h2_str:-0}))
    HEXTET3=$((0x${h3_str:-0}))

    debug_log "DEBUG" "HEXTET0=${HEXTET0} HEXTET1=${HEXTET1} HEXTET2=${HEXTET2} HEXTET3=${HEXTET3}"

    if [ $((HEXTET3 & 0xff)) -ne 0 ]; then
        printf "\n%s\n" "$(color yellow "$(get_message "MSG_MAPE_CE_AND_64_DIFFERENT")")"
        return 1
    fi

    OFFSET=6; RFC=false; IP6PREFIXLEN=""; PSIDLEN=""; IPADDR=""; IPV4=""; PSID=0; PORTS=""; EALEN=""; IP4PREFIXLEN=""; IP6PFX=""; BR=""; CE=""; IPV6PREFIX=""
    local PREFIX31 PREFIX38
    local h0_mul=$(( HEXTET0 * 65536 ))
    local h1_masked=$(( HEXTET1 & 0xfffe ))
    PREFIX31=$(( h0_mul + h1_masked ))
    local h0_mul2=$(( HEXTET0 * 16777216 ))
    local h1_mul=$(( HEXTET1 * 256 ))
    local h2_masked=$(( HEXTET2 & 64512 ))
    local h2_shift=$(( h2_masked >> 8 ))
    PREFIX38=$(( h0_mul2 + h1_mul + h2_shift ))
    local prefix31_hex=$(printf 0x%x "$PREFIX31")
    local prefix38_hex=$(printf 0x%x "$PREFIX38")
    local octet1 octet2 octet3 octet4 octet

    debug_log "DEBUG" "PREFIX31=$PREFIX31 (hex=$(printf 0x%x $PREFIX31)), PREFIX38=$PREFIX38 (hex=$(printf 0x%x $PREFIX38))"

    if [ -n "$(get_ruleprefix38_value "$prefix38_hex")" ]; then
        octet="$(get_ruleprefix38_value "$prefix38_hex")"
        debug_log "DEBUG" "mold_mape: Matched ruleprefix38 ($octet), setting PSIDLEN=8"
        IFS=',' read -r octet1 octet2 octet3 <<EOF
$octet
EOF
        local temp1=$(( HEXTET2 & 768 ))
        local temp2=$(( temp1 >> 8 ))
        octet3=$(( octet3 | temp2 ))
        octet4=$(( HEXTET2 & 255 ))
        IPADDR="${octet1}.${octet2}.${octet3}.${octet4}"
        IPV4="${octet1}.${octet2}.0.0"
        IP6PREFIXLEN=38
        PSIDLEN=8
        OFFSET=4
    elif [ -n "$(get_ruleprefix31_value "$prefix31_hex")" ]; then
        octet="$(get_ruleprefix31_value "$prefix31_hex")"
        debug_log "DEBUG" "mold_mape: Matched ruleprefix31 ($octet), setting PSIDLEN=8"
        IFS=',' read -r octet1 octet2 <<EOF
$octet
EOF
        octet2=$(( octet2 | (HEXTET1 & 1) ))
        local temp1=$(( HEXTET2 & 65280 ))
        octet3=$(( temp1 >> 8 ))
        octet4=$(( HEXTET2 & 255 ))
        IPADDR="${octet1}.${octet2}.${octet3}.${octet4}"
        IPV4="${octet1}.${octet2}.0.0"
        IP6PREFIXLEN=31
        PSIDLEN=8
        OFFSET=4
    elif [ -n "$(get_ruleprefix38_20_value "$prefix38_hex")" ]; then
        octet="$(get_ruleprefix38_20_value "$prefix38_hex")"
        debug_log "DEBUG" "mold_mape: Matched ruleprefix38_20 ($octet), setting PSIDLEN=6"
        IFS=',' read -r octet1 octet2 octet3 <<EOF
$octet
EOF
        local temp1=$(( HEXTET2 & 960 ))
        local temp2=$(( temp1 >> 6 ))
        octet3=$(( octet3 | temp2 ))
        local temp3=$(( HEXTET2 & 63 ))
        local temp4=$(( temp3 << 2 ))
        local temp5=$(( HEXTET3 & 49152 ))
        local temp6=$(( temp5 >> 14 ))
        octet4=$(( temp4 | temp6 ))
        IPADDR="${octet1}.${octet2}.${octet3}.${octet4}"
        IPV4="${octet1}.${octet2}.0.0"
        IP6PREFIXLEN=38
        PSIDLEN=6
        OFFSET=6
    else
        printf "\n%s\n" "$(color yellow "$(get_message "MSG_MAPE_UNSUPPORTED_PREFIX")")"
        debug_log "DEBUG" "mold_mape: No matching ruleprefix. prefix31_hex=${prefix31_hex}, prefix38_hex=${prefix38_hex}."
        return 1
    fi

    debug_log "DEBUG" "PSIDLEN=${PSIDLEN} HEXTET3=${HEXTET3}"
    if [ "$PSIDLEN" -eq 8 ]; then
        local val_masked=$(( HEXTET3 & 65280 ))
        PSID=$(( val_masked >> 8 ))
        debug_log "DEBUG" "PSID(8) val_masked=${val_masked} PSID=${PSID}"
    elif [ "$PSIDLEN" -eq 6 ]; then
        local val_masked=$(( HEXTET3 & 16128 ))
        PSID=$(( val_masked >> 8 ))
        debug_log "DEBUG" "PSID(6) val_masked=${val_masked} PSID=${PSID}"
    else
        debug_log "DEBUG" "PSIDLEN (${PSIDLEN}) is not 8 or 6, PSID remains ${PSID} (default 0)."
    fi

    PORTS=""
    local AMAX=$(( (1 << OFFSET) - 1 ))
    local A
    for A in $(seq 1 "$AMAX"); do
        local shift_bits=$(( 16 - OFFSET ))
        local port_base=$(( A << shift_bits ))
        local psid_shift=$(( 16 - OFFSET - PSIDLEN ))
        if [ "$psid_shift" -lt 0 ]; then psid_shift=0; fi
        local psid_part=$(( PSID << psid_shift ))
        local port=$(( port_base | psid_part ))
        local port_range_size=$(( 1 << psid_shift ))
        if [ "$port_range_size" -le 0 ]; then port_range_size=1; fi
        local port_end=$(( port + port_range_size - 1 ))
        PORTS="${PORTS}${port}-${port_end}"
        if [ "$A" -lt "$AMAX" ]; then
            if [ $(( A % 3 )) -eq 0 ]; then
                PORTS="${PORTS}\\n"
            else
                PORTS="${PORTS} "
            fi
        fi
    done

    # CE address calculation
    local local_CE_HEXTET0 local_CE_HEXTET1 local_CE_HEXTET2 local_CE_HEXTET3_calc local_CE_HEXTET4 local_CE_HEXTET5 local_CE_HEXTET6 local_CE_HEXTET7_calc
    local_CE_HEXTET0=$HEXTET0
    local_CE_HEXTET1=$HEXTET1
    local_CE_HEXTET2=$HEXTET2
    local_CE_HEXTET3_calc=$(( HEXTET3 & 65280 ))
    local ce_octet1=$(echo "$IPADDR" | cut -d. -f1)
    local ce_octet2=$(echo "$IPADDR" | cut -d. -f2)
    local ce_octet3=$(echo "$IPADDR" | cut -d. -f3)
    local ce_octet4=$(echo "$IPADDR" | cut -d. -f4)
    if [ "$RFC" = "true" ]; then
        local_CE_HEXTET4=0
        local_CE_HEXTET5=$(( (ce_octet1 << 8) | ce_octet2 ))
        local_CE_HEXTET6=$(( (ce_octet3 << 8) | ce_octet4 ))
        local_CE_HEXTET7_calc=$PSID
    else
        local_CE_HEXTET4=$ce_octet1
        local_CE_HEXTET5=$(( (ce_octet2 << 8) | ce_octet3 ))
        local_CE_HEXTET6=$(( ce_octet4 << 8 ))
        local_CE_HEXTET7_calc=$(( PSID << 8 ))
    fi
    local CE0=$(printf %04x "${local_CE_HEXTET0:-0}")
    local CE1=$(printf %04x "${local_CE_HEXTET1:-0}")
    local CE2=$(printf %04x "${local_CE_HEXTET2:-0}")
    local CE3=$(printf %04x "${local_CE_HEXTET3_calc:-0}")
    local CE4=$(printf %04x "${local_CE_HEXTET4:-0}")
    local CE5=$(printf %04x "${local_CE_HEXTET5:-0}")
    local CE6=$(printf %04x "${local_CE_HEXTET6:-0}")
    local CE7=$(printf %04x "${local_CE_HEXTET7_calc:-0}")
    CE="${CE0}:${CE1}:${CE2}:${CE3}:${CE4}:${CE5}:${CE6}:${CE7}"
    IPV6PREFIX="${h0_str:-0}:${h1_str:-0}:${h2_str:-0}:${h3_str:-0}::"
    EALEN=$(( 56 - IP6PREFIXLEN ))
    IP4PREFIXLEN=$(( 32 - (EALEN - PSIDLEN) ))
    local IP6PFX0 IP6PFX1 IP6PFX2
    if [ "$IP6PREFIXLEN" -eq 38 ]; then
        local hextet2_2=$(( HEXTET2 & 64512 ))
        IP6PFX0=$(printf %x "${HEXTET0:-0}")
        IP6PFX1=$(printf %x "${HEXTET1:-0}")
        IP6PFX2=$(printf %x "${hextet2_2:-0}")
        IP6PFX="${IP6PFX0}:${IP6PFX1}:${IP6PFX2}"
    elif [ "$IP6PREFIXLEN" -eq 31 ]; then
        local hextet2_1=$(( HEXTET1 & 65534 ))
        IP6PFX0=$(printf %x "${HEXTET0:-0}")
        IP6PFX1=$(printf %x "${hextet2_1:-0}")
        IP6PFX="${IP6PFX0}:${IP6PFX1}"
    else
        IP6PFX=""
    fi

    # --- BR自動判定（JavaScript版と完全一致） ---
    debug_log "DEBUG" "BR判定: PREFIX31=$PREFIX31 (hex=$(printf 0x%x $PREFIX31)), IP6PREFIXLEN=$IP6PREFIXLEN"

    BR=""
    if [ "$IP6PREFIXLEN" -eq 31 ]; then
        # 0x24047a80(604273280)～0x24047a84(604273284)
        if [ "$PREFIX31" -ge 604273280 ] && [ "$PREFIX31" -lt 604273284 ]; then
            BR="2001:260:700:1::1:275"
        # 0x24047a84(604273284)～0x24047a88(604273288)
        elif [ "$PREFIX31" -ge 604273284 ] && [ "$PREFIX31" -lt 604273288 ]; then
            BR="2001:260:700:1::1:276"
        # 0x240b0010(604700688)～0x240b0014(604700692) または 0x240b0250(604701264)～0x240b0254(604701268)
        elif { [ "$PREFIX31" -ge 604700688 ] && [ "$PREFIX31" -lt 604700692 ]; } || { [ "$PREFIX31" -ge 604701264 ] && [ "$PREFIX31" -lt 604701268 ]; }; then
            BR="2404:9200:225:100::64"
        fi
    fi
    if [ -z "$BR" ] && [ -n "$(get_ruleprefix38_20_value "$prefix38_hex")" ]; then
        BR="2001:380:a120::9"
    fi
    
    debug_log "DEBUG" "BR after判定: BR='${BR}'"
    debug_log "DEBUG" "mold_mape: Exiting mold_mape() function successfully. IPv6 acquisition method: ${MAPE_IPV6_ACQUISITION_METHOD}."
    return 0
}

# prompt_wan6_prefix_configuration_method (仮の関数名)
#
# Prompts the user to determine how the wan6 IPv6 prefix should be configured,
# specifically whether 'network.wan6.ip6prefix' should be manually set by this script.
# This decision is based on the user's ISP contract type (speed, presence of Hikari Denwa),
# as these factors typically influence whether IPv6 prefixes are delegated via DHCPv6-PD
# or if a static /64 prefix is provided via RA.
#
# The general guideline provided to the user for selection is summarized as follows:
#
# | No. | ISP Speed (Approx) | Hikari Denwa Contract | WAN6 IPv6 Prefix Acquisition (Typical Assumption)      | Manual 'network.wan6.ip6prefix' Setting by Script?     |
# |:---:|:-------------------|:----------------------|:-------------------------------------------------------|:-------------------------------------------------------|
# |  1  | 1Gbps              | No                    | ISP provides /64 via RA (No or limited DHCPv6-PD).     | YES (Script will set '${CE_NETWORK_PREFIX_FOR_WAN6}::/64'). |
# |  2  | 1Gbps              | Yes                   | ISP delegates /56 (or similar) via DHCPv6-PD.          | NO (Script expects prefix to be acquired via DHCPv6-PD). |
# |  3  | 10Gbps             | No                    | ISP delegates /56 (or similar) via DHCPv6-PD.          | NO (Script expects prefix to be acquired via DHCPv6-PD). |
# |  4  | 10Gbps             | Yes                   | ISP delegates /56 (or similar) via DHCPv6-PD.          | NO (Script expects prefix to be acquired via DHCPv6-PD). |
#
# The user will be asked if their situation corresponds to No.1.
# Based on their 'y' or 'n' response, a global variable (e.g., USER_REQUESTS_MANUAL_WAN6_PREFIX)
# will be set. The config_mape() function will then use this variable to conditionally
# execute 'uci set network.wan6.ip6prefix...' or 'uci delete network.wan6.ip6prefix'.
#
# This function takes no arguments.
# It sets a global variable reflecting the user's choice.
config_mape() {
    local WANMAP='wanmap'

    # WANファイアウォールゾーンのインデックスを特定する
    # まず 'wan' という名前のゾーンを探す
    local ZONE_NO
    local wan_zone_name_to_find="wan"
    ZONE_NO=$(uci show firewall | grep -E "firewall\.@zone\[([0-9]+)\].name='$wan_zone_name_to_find'" | sed -n 's/firewall\.@zone\[\([0-9]*\)\].name=.*/\1/p' | head -n1)

    if [ -z "$ZONE_NO" ]; then
        debug_log "DEBUG" "config_mape: Firewall zone named '$wan_zone_name_to_find' not found. Defaulting to zone index '1' for WAN. This might not be correct for all configurations. Please verify your firewall setup."
        ZONE_NO="1" # 'wan' という名前のゾーンが見つからない場合のフォールバック (一般的なWANゾーンのインデックス)
    else
        debug_log "DEBUG" "config_mape: Using firewall zone '$wan_zone_name_to_find' (index $ZONE_NO) for the $WANMAP interface."
    fi

    # インターフェース名は変数で上書きできるように
    local WAN_IF="${WAN_IF:-wan}"
    local WAN6_IF="${WAN6_IF:-wan6}"
    local LAN_IF="${LAN_IF:-lan}"

    local osversion_file="${CACHE_DIR}/osversion.ch"
    local osversion=""

    debug_log "DEBUG" "config_mape: Backing up /etc/config/network, /etc/config/dhcp, /etc/config/firewall."
    cp /etc/config/network /etc/config/network.map-e.bak 2>/dev/null
    cp /etc/config/dhcp /etc/config/dhcp.map-e.bak 2>/dev/null
    cp /etc/config/firewall /etc/config/firewall.map-e.bak 2>/dev/null

    debug_log "DEBUG" "config_mape: Applying UCI settings for MAP-E interfaces and dhcp."
    
    uci -q set network.${WAN_IF}.disabled='1'
    uci -q set network.${WAN_IF}.auto='0'

    uci -q set dhcp.${LAN_IF}.ra='relay'
    uci -q set dhcp.${LAN_IF}.dhcpv6='relay' # MAP-Eでは通常 relay
    uci -q set dhcp.${LAN_IF}.ndp='relay'
    uci -q set dhcp.${LAN_IF}.force='1'

    uci -q set dhcp.${WAN6_IF}=dhcp
    uci -q set dhcp.${WAN6_IF}.interface="$WAN6_IF" # 修正: シェル変数を展開
    uci -q set dhcp.${WAN6_IF}.master='1'
    uci -q set dhcp.${WAN6_IF}.ra='relay'
    uci -q set dhcp.${WAN6_IF}.dhcpv6='relay'
    uci -q set dhcp.${WAN6_IF}.ndp='relay'

    uci -q set network.${WAN6_IF}.proto='dhcpv6'
    uci -q set network.${WAN6_IF}.reqaddress='try'
    uci -q set network.${WAN6_IF}.reqprefix='auto' # MAP-Eでは通常 'auto' またはISP指定の長さ
    
    debug_log "DEBUG" "config_mape: IPv6 acquisition method is '${MAPE_IPV6_ACQUISITION_METHOD}'."
    if [ "$MAPE_IPV6_ACQUISITION_METHOD" = "gua" ]; then
        if [ -n "$IPV6PREFIX" ]; then # IPV6PREFIX は mold_mape で h0:h1:h2:h3:: 形式で設定される
            debug_log "DEBUG" "config_mape: Setting network.${WAN6_IF}.ip6prefix to '${IPV6PREFIX}/64' (GUA method)."
            uci -q set network.${WAN6_IF}.ip6prefix="${IPV6PREFIX}/64" # GUAの場合は/64を期待
        else
            debug_log "DEBUG" "config_mape: IPV6PREFIX is empty, cannot set network.${WAN6_IF}.ip6prefix for GUA method." # DEBUGからWARNINGに変更
            uci -q delete network.${WAN6_IF}.ip6prefix
        fi
    elif [ "$MAPE_IPV6_ACQUISITION_METHOD" = "pd" ]; then
        debug_log "DEBUG" "config_mape: Deleting network.${WAN6_IF}.ip6prefix (PD method, prefix delegation expected)."
        uci -q delete network.${WAN6_IF}.ip6prefix # PDの場合は DHCPv6クライアントがプレフィックスを管理
    else
        debug_log "DEBUG" "config_mape: Unknown or no IPv6 acquisition method ('${MAPE_IPV6_ACQUISITION_METHOD}'). No specific action for network.${WAN6_IF}.ip6prefix." # DEBUGからWARNINGに変更
        uci -q delete network.${WAN6_IF}.ip6prefix # 不明な場合は削除が無難
    fi

    uci -q set network.${WANMAP}=interface
    uci -q set network.${WANMAP}.proto='map'
    uci -q set network.${WANMAP}.maptype='map-e'
    uci -q set network.${WANMAP}.peeraddr="${BR}"
    uci -q set network.${WANMAP}.ipaddr="${IPV4}"
    uci -q set network.${WANMAP}.ip4prefixlen="${IP4PREFIXLEN}"
    uci -q set network.${WANMAP}.ip6prefix="${IP6PFX}::" # IP6PFXはmold_mapeで計算
    uci -q set network.${WANMAP}.ip6prefixlen="${IP6PREFIXLEN}"
    uci -q set network.${WANMAP}.ealen="${EALEN}"
    uci -q set network.${WANMAP}.psidlen="${PSIDLEN}"
    uci -q set network.${WANMAP}.offset="${OFFSET}"
    uci -q set network.${WANMAP}.mtu='1460'
    uci -q set network.${WANMAP}.encaplimit='ignore'
    
    if [ -f "$osversion_file" ]; then
        osversion=$(cat "$osversion_file")
        debug_log "DEBUG" "config_mape: OS Version from '$osversion_file': $osversion"
    else
        osversion="unknown"
        debug_log "DEBUG" "config_mape: OS version file '$osversion_file' not found. Applying default/latest version settings."
    fi

    if echo "$osversion" | grep -q "^19"; then
        debug_log "DEBUG" "config_mape: Applying settings for OpenWrt 19.x compatible version."
        uci -q delete network.${WANMAP}.tunlink
        uci -q add_list network.${WANMAP}.tunlink="${WAN6_IF}" # シェル変数を展開
        uci -q delete network.${WANMAP}.legacymap
    else # OpenWrt 21.02+ or unknown
        debug_log "DEBUG" "config_mape: Applying settings for OpenWrt non-19.x version (e.g., 21.02+ or undefined)."
        uci -q set dhcp.${WAN6_IF}.ignore='1' # 21.02+ではwan6をignoreすることが多い
        uci -q set network.${WANMAP}.legacymap='1' # 21.02+ではlegacymapが必要な場合がある
        uci -q set network.${WANMAP}.tunlink="${WAN6_IF}" # シェル変数を展開
    fi
    
    # ファイアウォール設定: WANゾーンにwanmapインターフェースを追加し、従来のwanインターフェースを削除
    local current_wan_networks
    current_wan_networks=$(uci -q get firewall.@zone[${ZONE_NO}].network 2>/dev/null) # エラー出力を抑制

    # 既存の 'wan' インターフェースをWANゾーンから削除
    if echo "$current_wan_networks" | grep -q "\b${WAN_IF}\b"; then
        uci -q del_list firewall.@zone[${ZONE_NO}].network="${WAN_IF}"
        debug_log "DEBUG" "config_mape: Removed '${WAN_IF}' from firewall WAN zone ${ZONE_NO} network list."
    fi

    # 'wanmap' インターフェースをWANゾーンに追加 (存在しない場合のみ)
    if ! echo "$current_wan_networks" | grep -q "\b${WANMAP}\b"; then
        uci -q add_list firewall.@zone[${ZONE_NO}].network="${WANMAP}" # WANMAP変数を使用
        debug_log "DEBUG" "config_mape: Added '${WANMAP}' to firewall WAN zone ${ZONE_NO} network list."
    else
        debug_log "DEBUG" "config_mape: '${WANMAP}' already in firewall WAN zone ${ZONE_NO} network list."
    fi
    uci -q set firewall.@zone[${ZONE_NO}].masq='1'
    uci -q set firewall.@zone[${ZONE_NO}].mtu_fix='1'
    
    debug_log "DEBUG" "config_mape: Committing UCI changes..."
    local commit_failed=0 # どのコミットが失敗したか記録するため
    local commit_errors=""

    uci -q commit network
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}network "
        debug_log "DEBUG" "config_mape: Failed to commit network."
    fi

    uci -q commit dhcp
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}dhcp "
        debug_log "DEBUG" "config_mape: Failed to commit dhcp."
    fi
    
    uci -q commit firewall
    if [ $? -ne 0 ]; then
        commit_failed=1
        commit_errors="${commit_errors}firewall "
        debug_log "DEBUG" "config_mape: Failed to commit firewall."
    fi

    if [ "$commit_failed" -eq 1 ]; then
        debug_log "DEBUG" "config_mape: One or more UCI sections failed to commit: ${commit_errors}."
        # 復元処理を促すか、エラーメッセージを表示して終了するか検討
        return 1 # コミット失敗
    else
        debug_log "DEBUG" "config_mape: All UCI sections committed successfully."
    fi
    
    return 0
}

replace_map_sh() {
    local proto_script_path="/lib/netifd/proto/map.sh"
    local backup_script_path="${proto_script_path}.bak"
    local osversion_file="${CACHE_DIR}/osversion.ch"
    local osversion=""
    local source_url=""
    local wget_rc
    local chmod_rc

    debug_log "DEBUG" "replace_map_sh: Function started. Method: cp backup, then direct wget overwrite with -6."

    # 1. OSバージョンに基づいてソースURLを決定
    if [ -f "$osversion_file" ]; then
        osversion=$(cat "$osversion_file")
        debug_log "DEBUG" "replace_map_sh: OS Version from '$osversion_file': $osversion"
    else
        osversion="unknown"
        debug_log "DEBUG" "replace_map_sh: OS version file '$osversion_file' not found. Using default: $osversion"
    fi

    if echo "$osversion" | grep -q "^19"; then
        source_url="https://raw.githubusercontent.com/site-u2023/map-e/main/map.sh.19"
    else
        source_url="https://raw.githubusercontent.com/site-u2023/map-e/main/map.sh.new"
    fi
    debug_log "DEBUG" "replace_map_sh: Determined source URL: $source_url"

    # 2. 既存のスクリプトをバックアップ (cp)
    if [ -f "$proto_script_path" ]; then
        debug_log "DEBUG" "replace_map_sh: Attempting to back up '$proto_script_path' to '$backup_script_path'."
        if command cp "$proto_script_path" "$backup_script_path"; then
            debug_log "DEBUG" "replace_map_sh: Backup successful: '$backup_script_path' created."
        else
            local cp_rc=$?
            debug_log "DEBUG" "replace_map_sh: Backup FAILED for '$proto_script_path'. 'cp' exit code: $cp_rc."
        fi
    else
        debug_log "DEBUG" "replace_map_sh: Original script '$proto_script_path' not found. Skipping backup."
    fi

    # 3. 新しいスクリプトをダウンロードして直接上書き (wget -O、IPタイプ -6 固定)
    debug_log "DEBUG" "replace_map_sh: Attempting to download from '$source_url' to '$proto_script_path' using wget with -6 option."
    
    command wget -q ${WGET_IPV_OPT} --no-check-certificate -O "$proto_script_path" "$source_url"
    wget_rc=$?
    debug_log "DEBUG" "replace_map_sh: wget command finished. Exit code: $wget_rc."

    if [ "$wget_rc" -eq 0 ]; then
        if [ -s "$proto_script_path" ]; then
            debug_log "DEBUG" "replace_map_sh: Download successful. '$proto_script_path' has been updated and is not empty."
            
            # 4. 実行権限を付与
            debug_log "DEBUG" "replace_map_sh: Setting execute permission on '$proto_script_path'."
            if command chmod +x "$proto_script_path"; then
                debug_log "DEBUG" "replace_map_sh: Execute permission set successfully for '$proto_script_path'."
                debug_log "DEBUG" "replace_map_sh: Function finished successfully."
                
                if type get_message > /dev/null 2>&1; then
                    printf "%s\n" "$(color green "$(get_message "MSG_MAP_SH_UPDATE_SUCCESS")")"
                fi
                return 0 # 全て成功
            else
                local chmod_rc=$?
                debug_log "DEBUG" "replace_map_sh: chmod +x FAILED for '$proto_script_path'. Exit code: $chmod_rc."
                return 2 # chmod失敗 (ダウンロードは成功)
            fi
        else
            debug_log "DEBUG" "replace_map_sh: wget reported success (exit code 0), but the downloaded file '$proto_script_path' is EMPTY."
            return 1 # ダウンロードしたがファイルが空
        fi
    else
        debug_log "DEBUG" "replace_map_sh: wget download FAILED. Exit code: $wget_rc."
        return 1 # wget失敗
    fi
}

# MAP-E設定情報を表示する関数
display_mape() {

    printf "\n"
    printf "%s\n" "$(color blue "Prefix Information:")" # "プレフィックス情報:"
    local ipv6_label
    case "$MAPE_IPV6_ACQUISITION_METHOD" in
        gua)
            ipv6_label="IPv6 address:"
            ;;
        pd)
            ipv6_label="IPv6 prefix:"
            ;;
        *)
            ipv6_label="IPv6 prefix or address:"
            ;;
    esac
    printf "  %s %s\n" "$ipv6_label" "$NEW_IP6_PREFIX"
    printf "  CE: %s\n" "$CE" # "  CE IPv6アドレス: $CE"
    printf "  IPv4 address: %s\n" "$IPADDR" # "  IPv4アドレス: $IPADDR"
    printf "  PSID (Decimal): %s\n" "$PSID" # "  PSID値(10進数): $PSID"

    printf "\n"
    printf "%s\n" "$(color yellow "Note: True values may differ")"

    printf "\n"
    printf "%s\n" "$(color blue "OpenWrt Configuration Values:")" # "OpenWrt設定値:"
    printf "  option peeraddr '%s'\n" "$BR" # BRが空の場合もあるためクォート
    printf "  option ipaddr %s\n" "$IPV4"
    printf "  option ip4prefixlen '%s'\n" "$IP4PREFIXLEN"
    printf "  option ip6prefix '%s::'\n" "$IP6PFX" # IP6PFXが空の場合もあるためクォート
    printf "  option ip6prefixlen '%s'\n" "$IP6PREFIXLEN"
    printf "  option ealen '%s'\n" "$EALEN"
    printf "  option psidlen '%s'\n" "$PSIDLEN"
    printf "  option offset '%s'\n" "$OFFSET"
    printf "\n"
    printf "  export LEGACY=1\n"

    # ポート情報の計算を最適化
    local max_port_blocks=$(( (1 << OFFSET) ))
    local ports_per_block=$(( 1 << (16 - OFFSET - PSIDLEN) ))
    local total_ports=$(( ports_per_block * ((1 << OFFSET) - 1) )) 
    
    # local port_start_for_A1=$(( (1 << (16 - OFFSET)) | (PSID << (16 - OFFSET - PSIDLEN)) )) 
    local shift_val1
    local term1
    local shift_val2
    local term2
    local port_start_for_A1

    shift_val1=$((16 - OFFSET))
    term1=$((1 << shift_val1))
    shift_val2=$((16 - OFFSET - PSIDLEN)) 
    term2=$((PSID << shift_val2))
    port_start_for_A1=$((term1 | term2))

    debug_log "DEBUG" "Port calculation for display: blocks=$max_port_blocks, ports_per_block=$ports_per_block, total_ports=$total_ports, first_port_start_A1=$port_start_for_A1" 

    printf "\n"
    printf "%s\n" "$(color blue "Port Information:")" # "ポート情報:"
    printf "  Available Ports: %s\n" "$total_ports" # "  利用可能なポート数: $total_ports"

    # ポート範囲を表示（PORTSをバッファリングして最適化）
    printf "\n"
    printf "%s\n" "$(color blue "Port Ranges:")" # "ポート範囲:"
    
    # PORTSが既にmold_mape()で計算済みかつ正常な場合は、それを表示
    if [ -n "$PORTS" ]; then
        # ポート範囲の各行の先頭にスペースを追加し、エスケープシーケンスを解釈
        printf "  %b\n" "$(echo "$PORTS" | sed 's/\\n/\\n  /g')"
    else
        # PORTSが空の場合のフォールバック処理（再計算）
        local shift_bits=$(( 16 - OFFSET ))
        local psid_shift=$(( 16 - OFFSET - PSIDLEN ))
        if [ "$psid_shift" -lt 0 ]; then
            psid_shift=0
        fi
        local port_range_size=$(( 1 << psid_shift ))
        local port_max_index=$(( (1 << OFFSET) - 1 )) # A=1 から AMAX まで
        local line_buffer=""
        local items_in_line=0
        local max_items_per_line=3 # 現在のロジックに合わせる
        
        for A in $(seq 1 "$port_max_index"); do
            local port_base=$(( A << shift_bits ))
            local psid_part=$(( PSID << psid_shift ))
            local port_start_val=$(( port_base | psid_part )) # 変数名を変更
            local port_end_val=$(( port_start_val + port_range_size - 1 )) # 変数名を変更
            
            # バッファに追加
            if [ "$items_in_line" -eq 0 ]; then
                line_buffer="${port_start_val}-${port_end_val}"
            else
                line_buffer="${line_buffer} ${port_start_val}-${port_end_val}"
            fi
            
            items_in_line=$((items_in_line + 1))
            
            # 行ごとに出力（最大表示項目数に達したか、最後の項目の場合）
            if [ "$items_in_line" -ge "$max_items_per_line" ] || [ "$A" -eq "$port_max_index" ]; then
                printf "  %s\n" "$line_buffer" # echo を printf に変更
                line_buffer=""
                items_in_line=0
            fi
        done
    fi

    printf "\n"
    printf "%s\n" "$(color white "Powered by config-softwire")"
    printf "\n"
    printf "%s\n" "$(color green "$(get_message "MSG_MAPE_PARAMS_CALC_SUCCESS")")"
    printf "%s\n" "$(color yellow "$(get_message "MSG_MAPE_APPLY_SUCCESS")")"
    read -r -n 1 -s
    
    return 0
}

# MAP-E設定のバックアップを復元する関数
# 戻り値:
# 0: 1つ以上のバックアップが正常に復元され、再起動プロセス開始
# 1: 復元対象のバックアップファイルが1つも見つからなかった / またはその他のエラー
# 2: 1つ以上のファイルの復元に失敗したが、処理は継続し再起動プロセス開始
restore_mape() {
    local backup_files_restored_count=0
    local backup_files_not_found_count=0
    local restore_failed_count=0
    local total_files_to_check=0
    local overall_restore_status=1 # 初期値を「失敗または何もせず」に設定

    # 対象ファイルとバックアップファイルのマッピング
    # 構造: "オリジナルファイル名:バックアップファイル名"
    local files_to_restore="
        /etc/config/network:/etc/config/network.map-e.bak
        /etc/config/dhcp:/etc/config/dhcp.map-e.bak
        /etc/config/firewall:/etc/config/firewall.map-e.bak
        /lib/netifd/proto/map.sh:/lib/netifd/proto/map.sh.bak
    "

    debug_log "DEBUG" "Starting restore_mape function." # 関数名を修正

    # 各ファイルの復元処理
    for item in $files_to_restore; do
        total_files_to_check=$((total_files_to_check + 1))
        local original_file
        local backup_file
        original_file=$(echo "$item" | cut -d':' -f1)
        backup_file=$(echo "$item" | cut -d':' -f2)

        if [ -f "$backup_file" ]; then
            debug_log "DEBUG" "Attempting to restore '$original_file' from '$backup_file'."
            if cp "$backup_file" "$original_file"; then
                debug_log "DEBUG" "Successfully restored '$original_file' from '$backup_file'."
                backup_files_restored_count=$((backup_files_restored_count + 1))
            else
                debug_log "DEBUG" "Failed to copy '$backup_file' to '$original_file'."
                restore_failed_count=$((restore_failed_count + 1))
            fi
        else
            debug_log "DEBUG" "Backup file '$backup_file' not found. Skipping restore for '$original_file'."
            backup_files_not_found_count=$((backup_files_not_found_count + 1))
        fi
    done

    debug_log "DEBUG" "Restore process summary: Total checked=$total_files_to_check, Restored=$backup_files_restored_count, Not found=$backup_files_not_found_count, Failed=$restore_failed_count."

    if [ "$restore_failed_count" -gt 0 ]; then
        debug_log "DEBUG" "Restore completed with errors."
        overall_restore_status=2 # 1つ以上のファイルの復元に失敗
    elif [ "$backup_files_restored_count" -gt 0 ]; then
        debug_log "DEBUG" "Restore completed successfully for at least one file."
        overall_restore_status=0 # 1つ以上のバックアップが正常に復元された
    else
        # この分岐は backup_files_not_found_count == total_files_to_check と同義
        debug_log "DEBUG" "No backup files were found to restore."
        overall_restore_status=1 # 復元対象のバックアップファイルが1つも見つからなかった
    fi

    # overall_restore_status が 0 (成功) または 2 (一部失敗だが復元試行はあった) の場合に後続処理を実行
    if [ "$overall_restore_status" -eq 0 ] || [ "$overall_restore_status" -eq 2 ]; then
        debug_log "DEBUG" "Attempting to remove 'map' package as part of restore process."
        if opkg remove map >/dev/null 2>&1; then
            debug_log "DEBUG" "'map' package removed successfully."
        else
            debug_log "DEBUG" "Failed to remove 'map' package or package was not installed. Continuing."
        fi
        
        printf "\n%s\n" "$(color green "$(get_message "MSG_MAPE_RESTORE_COMPLETE")")"
        printf "%s\n" "$(color yellow "$(get_message "MSG_MAPE_APPLY_SUCCESS")")"
        read -r -n 1 -s
        printf "\n"
        
        debug_log "DEBUG" "Rebooting system after restore."
        reboot
        return 0 # reboot が呼ばれるので、ここには到達しないはずだが念のため
    elif [ "$overall_restore_status" -eq 1 ]; then
        # バックアップファイルが見つからなかった場合
        printf "\n%s\n" "$(color yellow "$(get_message "MSG_NO_BACKUP_FOUND")")"
        return 1 # 失敗として返す
    fi
    
    # 通常はここまで来ないはずだが、万が一のためのフォールバック
    return "$overall_restore_status"
}

internet_map_main() {
    
    # MAP-Eパラメータ計算
    if ! mold_mape; then
        debug_log "DEBUG" "internet_map_main: mold_mape function failed. Exiting script."
        return 1
    fi

    # `map` パッケージのインストール 
    # if ! install_package map hidden; then
    #     debug_log "DEBUG" "internet_map_main: Failed to install 'map' package or it was already installed. Continuing."
    #     return 1
    # fi

    # if ! replace_map_sh; then
    #     return 1
    # fi
    
    # UCI設定の適用
    # if ! config_mape; then
    #     debug_log "DEBUG" "internet_map_main: config_mape function failed. UCI settings might be inconsistent."
    #     return 1
    # fi

    if ! display_mape; then
        debug_log "DEBUG" "internet_map_main: display_mape function failed. Aborting reboot."
        return 1
    fi
    
    # 再起動
    # debug_log "DEBUG" "internet_map_main: Configuration complete. Rebooting system."
    # reboot

    return 0 # Explicitly exit with success status
}

# internet_map_main

#!/bin/sh
# =============================================================
#  sing-box-onekey.sh — Alpine 裸机一键搭建 vless-reality / hysteria2
#  (专用 Alpine,OpenRC;与 fscarmen 等第三方脚本完全隔离共存)
#
#  用法:
#    curl -fsSL https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh | sh
#    sh sing-box-onekey.sh              # 安装(交互选协议/端口/域名/节点名)
#    PROTOCOLS=vless sh sing-box-onekey.sh          # 只装 vless-reality
#    PROTOCOLS=hy2 sh sing-box-onekey.sh            # 只装 hysteria2
#    PROTOCOLS=vless,hy2 VLESS_PORT=6501 HY2_PORT=6502 sh ... # 全参数非交互
#
#  安装完成后脚本自身会被装成命令 sb,直接敲 sb 出交互菜单:
#    sb                  # 交互菜单(1看 2改 3协议 4重启 5升级 6删节点 7卸载)
#    sb -n  查看节点信息      sb -e  修改节点配置      sb -p  增减协议
#    sb -s  重启服务          sb -v  升级 sing-box     sb -b  开启 BBR
#    sb -r  删除节点(留命令)  sb -u  彻底卸载          sb -h  帮助
#    sb -e SNI=www.nvidia.com VLESS_PORT=65010    # 非交互编辑
# =============================================================
set -u

SB_FALLBACK_VERSION="1.14.3"          # GitHub API 不可用时的兜底版本
SCRIPT_VER="1.8"                      # 本脚本自身版本(用于判断 sb 是否需要更新)
CONF_DIR="/etc/sb-onekey"
PARAMS="$CONF_DIR/params.env"
BIN="/usr/local/bin/sb-onekey"        # sing-box 二进制(不是本脚本)
SELF_BIN="/usr/local/bin/sb"          # 本脚本自装的命令入口(菜单)
SELF_BIN_ALT="/usr/local/bin/sbctl"   # 兼容旧名(软链到 sb)
SELF_URL="https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh"
PROTOCOLS="${PROTOCOLS:-}"
VLESS_PORT="${VLESS_PORT:-}"
HY2_PORT="${HY2_PORT:-}"
SNI="${SNI:-}"
NODE_NAME="${NODE_NAME:-}"
SB_VERSION="${SB_VERSION:-}"
ENABLE_VLESS="${ENABLE_VLESS:-}"
ENABLE_HY2="${ENABLE_HY2:-}"

RED='\033[31m'; GRN='\033[32m'; CYN='\033[36m'; YLW='\033[33m'; NC='\033[0m'
ok()  { printf "${GRN}[OK]${NC} %s\n" "$1"; }
info(){ printf "${CYN}[INFO]${NC} %s\n" "$1"; }
warn(){ printf "${YLW}[警告]${NC} %s\n" "$1"; }
die() { printf "${RED}[错误]${NC} %s\n" "$1" >&2; exit 1; }

# ---------- 基础检查 ----------
[ "$(id -u)" = "0" ] || die "请用 root 运行"

# 静默环境检查(菜单/内部调用用,不打 INFO)
check_env() {
    [ -f /etc/alpine-release ] || die "本脚本仅支持 Alpine 系统(检测到非 Alpine)"
    command -v rc-service >/dev/null 2>&1 || die "未检测到 OpenRC(rc-service),请确认系统完整"
}

detect_os() {
    check_env
    info "系统: Alpine $(cat /etc/alpine-release) / init: OpenRC"
}

install_deps() {
    _need=""
    for _c in curl openssl tar; do
        command -v "$_c" >/dev/null 2>&1 || _need="$_need $_c"
    done
    if [ -z "$_need" ]; then
        ok "依赖已存在(curl/openssl/tar),无需安装"
        return 0
    fi
    info "缺少:$_need —— 开始安装..."
    apk update >/dev/null 2>&1 || warn "apk update 失败(源可能不可达),继续尝试安装"
    if ! apk add --no-cache curl openssl tar >/dev/null 2>&1; then
        die "依赖安装失败。请依次检查:
  1) Alpine 源是否可用: cat /etc/apk/repositories
  2) 网络/DNS 是否通:   ping -c2 dl-cdn.alpinelinux.org
  3) 磁盘是否满:        df -h /
  手动补装: apk add curl openssl tar"
    fi
    for _c in curl openssl tar; do
        command -v "$_c" >/dev/null 2>&1 || die "$_c 安装后仍不可用,请手动执行: apk add $_c"
    done
    ok "依赖就绪"
}

# ---------- 交互输入(管道执行时自动从 /dev/tty 读取,环境变量优先) ----------
tty_read() {
    _line=""
    if [ -t 0 ]; then
        IFS= read -r _line
    elif has_tty; then
        # 必须用子 shell 包住整条命令:否则 "< /dev/tty" 重定向失败的错误会绕过 2>/dev/null
        # 直接打到 stderr,非交互环境下每次都刷一行 "can't open /dev/tty"
        _line="$( ( IFS= read -r _l < /dev/tty && printf '%s' "$_l" ) 2>/dev/null )" || return 1
    else
        return 1
    fi
    printf '%s\n' "$_line"
}

has_tty() {
    # 注意:不能用 [ -r /dev/tty ] 判断 —— 设备文件有读权限,但无控制终端时 open 会 ENXIO
    [ -t 0 ] && return 0
    ( : < /dev/tty ) 2>/dev/null && return 0
    return 1
}

env_val() { eval "printf '%s' \"\${$1:-}\""; }

ask_port() {  # $1=变量名 $2=提示  端口必填,无默认
    _v="$(env_val "$1")"
    if [ -z "$_v" ]; then
        printf '%s' "$2"
        _v="$(tty_read)" || die "当前为非交互环境,请用环境变量指定端口: $1=端口号 sb -i"
    fi
    case "$_v" in ''|*[!0-9]*) die "端口必须是纯数字,收到: $_v" ;; esac
    [ "$_v" -ge 1 ] && [ "$_v" -le 65535 ] || die "端口范围 1-65535"
    eval "$1=\$_v"
}

ask_text() {  # $1=变量名 $2=提示 $3=默认值(可空)
    _v="$(env_val "$1")"
    if [ -z "$_v" ]; then
        printf '%s' "$2"
        _v="$(tty_read)" || _v=""
    fi
    [ -z "$_v" ] && _v="$3"
    eval "$1=\$_v"
}

urlencode() {
    # 只编码 unreserved 之外的字节,保留 A-Za-z0-9-._~
    # (旧实现全字节编码,节点名 "hk-1 reality" 会变成 %68%6b%2d31... ,链接可读性极差)
    printf '%s' "$1" | od -An -tu1 -v | tr -s ' ' '\n' | grep -v '^$' | awk '
        {
            c = $1 + 0
            if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) \
                || c == 45 || c == 46 || c == 95 || c == 126)
                printf "%c", c
            else
                printf "%%%02X", c
        }'
}

# 端口监听探测(纯 /proc,不依赖 ss/netstat;Alpine 最小安装里可能都没有)
# $1=端口 $2=tcp|udp → 0=监听 1=未监听 2=无法判断
# ★必须同时查 v4 和 v6:本脚本 inbound 的 listen 是 "::",内核把它记在 /proc/net/tcp6,
#   只查 /proc/net/tcp 会误报"未监听"(实测踩过)
port_listen() {
    _h="$(printf '%04X' "$1" 2>/dev/null)" || return 2
    if [ "$2" = "udp" ]; then _f4=/proc/net/udp; _f6=/proc/net/udp6
    else _f4=/proc/net/tcp; _f6=/proc/net/tcp6; fi
    [ -r "$_f4" ] || [ -r "$_f6" ] || return 2
    for _f in "$_f4" "$_f6"; do
        [ -r "$_f" ] || continue
        awk -v h="$_h" 'NR>1 { n=split($2,a,":"); if (n==2 && toupper(a[2])==h) { f=1; exit } } END { exit f?0:1 }' "$_f" 2>/dev/null && return 0
    done
    return 1
}

# ---------- 协议选择 ----------
ask_protocols() {
    _v="$PROTOCOLS"
    [ -n "$_v" ] || _v="$(env_val PROTOCOLS)"
    if [ -z "$_v" ]; then
        if has_tty; then
            printf '\n请选择要安装的协议:\n'
            printf '  1) 仅 vless-reality\n'
            printf '  2) 仅 hysteria2\n'
            printf '  3) 两个都装\n'
            printf '请选择 [1/2/3, 回车默认 3]: '
            _v="$(tty_read)" || _v=""
            [ -z "$_v" ] && _v="3"
        else
            _v="3"
            warn "非交互环境,默认安装全部协议(可用 PROTOCOLS=vless|hy2|vless,hy2 指定)"
        fi
    fi
    case "$_v" in
        1|vless|VLESS|reality|REALITY) _v="vless" ;;
        2|hy2|HY2|hysteria2|HYSTERIA2) _v="hy2" ;;
        3|both|all|"")                  _v="vless,hy2" ;;
    esac
    ENABLE_VLESS=0; ENABLE_HY2=0
    case ",$_v," in *,vless,*) ENABLE_VLESS=1 ;; esac
    case ",$_v," in *,hy2,*)   ENABLE_HY2=1   ;; esac
    if [ "$ENABLE_VLESS" = "0" ] && [ "$ENABLE_HY2" = "0" ]; then
        die "协议选择无效: $_v (可用: vless / hy2 / vless,hy2)"
    fi
    _names=""
    [ "$ENABLE_VLESS" = "1" ] && _names="vless-reality"
    [ "$ENABLE_HY2" = "1" ]   && _names="${_names:+$_names + }hysteria2"
    ok "将安装: $_names"
}

# ---------- sing-box 安装 ----------
latest_version() {
    _v="$(curl -fsSL --max-time 10 https://api.github.com/repos/SagerNet/sing-box/releases/latest 2>/dev/null \
        | sed -n 's/.*"tag_name": *"v\([0-9.]*\)".*/\1/p' | head -1)"
    [ -n "$_v" ] || _v="$SB_FALLBACK_VERSION"
    printf '%s\n' "$_v"
}

install_singbox() {
    [ -n "$SB_VERSION" ] || SB_VERSION="$(latest_version)"
    case "$(uname -m)" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        *) die "不支持的架构: $(uname -m)" ;;
    esac
    info "下载 sing-box v$SB_VERSION ($ARCH)..."
    _tmp="$(mktemp -d)"
    curl -fsSL "https://github.com/SagerNet/sing-box/releases/download/v${SB_VERSION}/sing-box-${SB_VERSION}-linux-${ARCH}.tar.gz" -o "$_tmp/sb.tar.gz" \
        || die "sing-box 下载失败(检查网络/安全组)"
    tar xzf "$_tmp/sb.tar.gz" -C "$_tmp"
    install -m755 "$_tmp/sing-box-${SB_VERSION}-linux-${ARCH}/sing-box" "$BIN"
    rm -rf "$_tmp"
    ok "sing-box $( $BIN version | head -1 | awk '{print $3}') 安装完成"
}

# ---------- 参数生成与持久化 ----------
save_params() {
    mkdir -p "$CONF_DIR"
    cat > "$PARAMS" <<EOF
ENABLE_VLESS=$ENABLE_VLESS
ENABLE_HY2=$ENABLE_HY2
VLESS_PORT=$VLESS_PORT
HY2_PORT=$HY2_PORT
SNI=$SNI
NODE_NAME=$NODE_NAME
SB_VERSION=$SB_VERSION
REALITY_PRIV=$REALITY_PRIV
REALITY_PUB=$REALITY_PUB
UUID=$UUID
SHORT_ID=$SHORT_ID
HY2_PASS=$HY2_PASS
EOF
    chmod 600 "$PARAMS"
}

gen_params() {
    _kp="$($BIN generate reality-keypair)"
    REALITY_PRIV="$(printf '%s' "$_kp" | awk '/PrivateKey/{print $2}')"
    REALITY_PUB="$(printf '%s' "$_kp" | awk '/PublicKey/{print $2}')"
    [ -n "$REALITY_PRIV" ] && [ -n "$REALITY_PUB" ] || die "reality 密钥对生成失败"
    UUID="$($BIN generate uuid)"
    SHORT_ID="$(openssl rand -hex 8)"
    HY2_PASS="$($BIN generate uuid)"
    save_params
    ok "参数已持久化到 $PARAMS"
}

load_params() {
    [ -f "$PARAMS" ] || die "未找到 $PARAMS,请先安装"
    . "$PARAMS"
    # 兼容 v1.2 及更早(无 ENABLE_* 字段):默认两个协议都启用
    : "${ENABLE_VLESS:=1}"
    : "${ENABLE_HY2:=1}"
    # 协议启用但端口为空 => 参数残缺
    if [ "$ENABLE_VLESS" = "1" ] && [ -z "${VLESS_PORT:-}" ]; then
        die "参数异常: ENABLE_VLESS=1 但 VLESS_PORT 为空,请重新安装"
    fi
    if [ "$ENABLE_HY2" = "1" ] && [ -z "${HY2_PORT:-}" ]; then
        die "参数异常: ENABLE_HY2=1 但 HY2_PORT 为空,请重新安装"
    fi
}

# ---------- hy2 自签证书(换证书前必须先停服务) ----------
gen_cert() {
    rc-service sb-onekey stop >/dev/null 2>&1 || true
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$CONF_DIR/hy2.key" -out "$CONF_DIR/hy2.crt" \
        -days 3650 -nodes \
        -subj "/CN=$SNI" -addext "subjectAltName=DNS:$SNI" 2>/dev/null \
        || die "证书生成失败"
    ok "hy2 自签证书生成 ($SNI, 10年)"
}

# ---------- 配置生成(协议块模块化,新协议加一个 gen_inbound_xxx 再挂进 write_config) ----------
gen_inbound_vless() {
    cat <<EOF
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": $VLESS_PORT,
      "users": [
        { "uuid": "$UUID", "flow": "xtls-rprx-vision" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "reality": {
          "enabled": true,
          "handshake": { "server": "$SNI", "server_port": 443 },
          "private_key": "$REALITY_PRIV",
          "short_id": [ "$SHORT_ID" ]
        }
      }
    }
EOF
}

gen_inbound_hy2() {
    cat <<EOF
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $HY2_PORT,
      "users": [
        { "password": "$HY2_PASS" }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$SNI",
        "certificate_path": "$CONF_DIR/hy2.crt",
        "key_path": "$CONF_DIR/hy2.key"
      }
    }
EOF
}

write_config() {
    mkdir -p "$CONF_DIR"
    _blocks=""
    if [ "${ENABLE_VLESS:-1}" = "1" ]; then
        _blocks="$(gen_inbound_vless)"
    fi
    if [ "${ENABLE_HY2:-1}" = "1" ]; then
        if [ -n "$_blocks" ]; then
            _blocks="$_blocks,
$(gen_inbound_hy2)"
        else
            _blocks="$(gen_inbound_hy2)"
        fi
    fi
    [ -n "$_blocks" ] || die "没有启用任何协议,拒绝生成空配置"
    {
        printf '{\n  "log": { "level": "warn", "timestamp": true },\n  "inbounds": [\n'
        printf '%s\n' "$_blocks"
        printf '\n  ],\n  "outbounds": [ { "type": "direct", "tag": "direct" } ]\n}\n'
    } > "$CONF_DIR/config.json"
    $BIN check -c "$CONF_DIR/config.json" || die "配置校验失败"
    ok "配置校验通过"
}

# ---------- 服务管理(OpenRC,独立服务名 sb-onekey,与 fscarmen 等第三方隔离) ----------
svc_install() {
    _desc="sb-onekey node"
    [ "${ENABLE_VLESS:-1}" = "1" ] && _desc="$_desc vless-reality"
    [ "${ENABLE_HY2:-1}" = "1" ]   && _desc="$_desc hysteria2"
    cat > /etc/init.d/sb-onekey <<EOF
#!/sbin/openrc-run
name="sb-onekey"
description="$_desc"
command="/usr/local/bin/sb-onekey"
command_args="run -c /etc/sb-onekey/config.json"
command_background="yes"
pidfile="/run/sb-onekey.pid"
output_log="/var/log/sb-onekey.log"
error_log="/var/log/sb-onekey.log"
depend() { need net; }
EOF
    chmod +x /etc/init.d/sb-onekey
    rc-update add sb-onekey default 2>/dev/null || true
    rc-service sb-onekey restart
    sleep 1
    svc_status || die "服务启动失败,查看日志: tail -30 /var/log/sb-onekey.log"
}

svc_status() {
    rc-service sb-onekey status >/dev/null 2>&1
}

get_ip() {
    _ip="$(curl -fs4 --max-time 6 https://api.ipify.org 2>/dev/null)" \
        || _ip="$(curl -fs4 --max-time 6 http://ifconfig.me 2>/dev/null)" \
        || _ip="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | head -1 | cut -d/ -f1)"
    [ -n "$_ip" ] || die "公网 IP 获取失败"
    printf '%s\n' "$_ip"
}

port_state() {  # $1=端口 $2=tcp|udp  输出带颜色的监听状态
    port_listen "$1" "$2"
    case $? in
        0) printf "${GRN}监听中${NC}" ;;
        1) printf "${RED}未监听${NC}" ;;
        *) printf "${YLW}无法判断${NC}" ;;
    esac
}

# ---------- 系统信息(菜单横幅用) ----------
sys_desc() {
    printf '%s / 内核 %s / %s' "Alpine $(cat /etc/alpine-release 2>/dev/null)" "$(uname -r)" "$(uname -m)"
}

# 查 IP 归属地,结果缓存在 _REGION(同一次运行内只查一次)
region_of() {  # $1=ip
    [ -n "${_REGION:-}" ] && return 0
    _REGION="$(curl -fsSL --max-time 5 "http://ip-api.com/line/${1}?fields=country&lang=zh-CN" 2>/dev/null | head -1)"
    [ -n "$_REGION" ] || _REGION="$(curl -fsSL --max-time 5 "https://ipinfo.io/${1}/country" 2>/dev/null | head -1)"
    [ -n "$_REGION" ] || _REGION="未知地区"
}

show_banner() {
    printf "${CYN}================================================================${NC}\n"
    printf " ${GRN}sing-box-onekey${NC}  v%s\n" "$SCRIPT_VER"
    printf " 系统: %s\n" "$(sys_desc)"
    if [ -z "${_IP_CACHE:-}" ]; then
        _IP_CACHE="$(get_ip 2>/dev/null)" || _IP_CACHE=""
    fi
    if [ -n "$_IP_CACHE" ]; then
        region_of "$_IP_CACHE"
        printf " IP  : %s (%s)\n" "$_IP_CACHE" "$_REGION"
    else
        printf " IP  : ${YLW}获取失败${NC}\n"
    fi
    if [ -f "$PARAMS" ]; then
        load_params
        printf " 服务: "
        if svc_status; then printf "${GRN}运行中${NC}"; else printf "${RED}未运行${NC}"; fi
        printf "   协议: "
        _any=""
        if [ "$ENABLE_VLESS" = "1" ]; then printf 'vless-reality'; _any=1; fi
        if [ "$ENABLE_HY2" = "1" ]; then [ -n "$_any" ] && printf ' + '; printf 'hysteria2'; fi
        printf "\n 端口: "
        _any=""
        if [ "$ENABLE_VLESS" = "1" ]; then
            printf '%s/TCP(%s)' "$VLESS_PORT" "$(port_state "$VLESS_PORT" tcp)"; _any=1
        fi
        if [ "$ENABLE_HY2" = "1" ]; then
            [ -n "$_any" ] && printf '  '
            printf '%s/UDP(%s)' "$HY2_PORT" "$(port_state "$HY2_PORT" udp)"
        fi
        printf "\n"
    else
        printf " 状态: ${YLW}未安装${NC}\n"
    fi
    printf "${CYN}================================================================${NC}\n"
}

# 把脚本自身装成 sb(菜单入口),并建 sbctl 兼容软链
install_self() {
    # 已装且版本一致 => 什么都不做(避免每次 info 都白下载一遍)
    if [ -x "$SELF_BIN" ] && grep -q "^SCRIPT_VER=\"$SCRIPT_VER\"" "$SELF_BIN" 2>/dev/null; then
        _ensure_alt_link
        return 0
    fi
    _tmp="/tmp/.sb-install.$$"
    _src=""
    # curl|sh 场景下 $0 是 sh 或 /dev/fd/63,不可用 => 回源下载
    if [ -f "$0" ] && grep -q "sing-box-onekey" "$0" 2>/dev/null; then
        cp -f "$0" "$_tmp" 2>/dev/null && _src="$0"
    fi
    if [ -z "$_src" ]; then
        if ! curl -fsSL --max-time 25 "$SELF_URL" -o "$_tmp" 2>/dev/null; then
            rm -f "$_tmp"
            warn "未能安装 sb 命令(下载失败);仍可用 sh sing-box-onekey.sh 运行"
            return 0
        fi
    fi
    if ! grep -q "sing-box-onekey" "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"
        warn "sb 内容校验失败,已跳过(不影响节点)"
        return 0
    fi
    chmod 755 "$_tmp"
    # 用 mv 而非 install:覆盖正在执行的文件时,install 会报 Text file busy
    mv -f "$_tmp" "$SELF_BIN" 2>/dev/null || { rm -f "$_tmp"; warn "sb 安装失败(权限?)"; return 0; }
    _ensure_alt_link
    ok "命令已安装: $SELF_BIN  (v$SCRIPT_VER,直接敲 sb 出菜单)"
}

# sbctl 只是兼容旧名的软链,删了也无所谓
_ensure_alt_link() {
    [ -e "$SELF_BIN_ALT" ] && [ ! -L "$SELF_BIN_ALT" ] && rm -f "$SELF_BIN_ALT" 2>/dev/null
    ln -sf sb "$SELF_BIN_ALT" 2>/dev/null || true
}

show_links() {
    load_params
    _ip="$(get_ip)"
    echo ""
    printf "${CYN}========== 分享链接 ==========${NC}\n"
    if [ "${ENABLE_VLESS:-1}" = "1" ]; then
        _n1="$(urlencode "${NODE_NAME} reality")"
        echo "vless://${UUID}@${_ip}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${REALITY_PUB}&sid=${SHORT_ID}&type=tcp&headerType=none#${_n1}"
        echo ""
    fi
    if [ "${ENABLE_HY2:-1}" = "1" ]; then
        _fp="$(openssl x509 -in "$CONF_DIR/hy2.crt" -outform der 2>/dev/null | openssl dgst -sha256 -hex | awk '{print $2}' | tr -d ':' | tr 'a-z' 'A-Z')"
        [ -n "$_fp" ] || die "hy2 证书缺失或损坏,请执行: sb -e 重新生成证书"
        _n2="$(urlencode "${NODE_NAME} hy2")"
        echo "hysteria2://${HY2_PASS}@${_ip}:${HY2_PORT}?sni=${SNI}&insecure=1&pinSHA256=${_fp}#${_n2}"
        echo ""
    fi
    printf "${CYN}==============================${NC}\n"
}

port_busy() {  # $1=端口
    (netstat -tuln 2>/dev/null || ss -tuln 2>/dev/null) | grep -q "[:.]$1[^0-9]"
}

check_new_port() {  # $1=新端口 $2=旧端口  返回 0=可用
    case "$1" in ''|*[!0-9]*) warn "端口必须是纯数字"; return 1 ;; esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ] || { warn "端口范围 1-65535"; return 1; }
    if [ "$1" != "$2" ] && port_busy "$1"; then
        warn "端口 $1 已被占用(可能是其他服务或另一个协议)"
        return 1
    fi
    return 0
}

detect_existing() {
    # fscarmen 版 sing-box:二进制在 /etc/sing-box/、配置在 /etc/sing-box/conf
    if [ -x /etc/sing-box/sing-box ] || [ -d /etc/sing-box/conf ]; then
        warn "检测到 fscarmen 版 sing-box,本脚本与其完全隔离(服务名 sb-onekey,目录 /etc/sb-onekey),可共存"
    fi
}

# ---------- 安装 ----------
do_install() {
    [ -f "$PARAMS" ] && die "已安装过(参数在 $PARAMS)。看状态: sb -n;改配置: sb -e;重装请先: sb -r"
    detect_os
    detect_existing
    install_deps
    install_self
    install_singbox
    ask_protocols

    if [ "$ENABLE_VLESS" = "1" ]; then
        ask_port VLESS_PORT "$(printf 'vless-reality 端口(必填,1-65535): ')"
    fi
    if [ "$ENABLE_HY2" = "1" ]; then
        ask_port HY2_PORT   "$(printf 'hysteria2 端口   (必填,1-65535): ')"
    fi
    if [ "$ENABLE_VLESS" = "1" ] && [ "$ENABLE_HY2" = "1" ]; then
        [ "$VLESS_PORT" != "$HY2_PORT" ] || die "两个端口不能相同"
    fi
    if [ "$ENABLE_VLESS" = "1" ] && port_busy "$VLESS_PORT"; then
        die "TCP 端口 $VLESS_PORT 已被占用(可能是已有节点),换一个"
    fi
    if [ "$ENABLE_HY2" = "1" ] && port_busy "$HY2_PORT"; then
        die "UDP 端口 $HY2_PORT 已被占用(可能是已有节点),换一个"
    fi

    ask_text SNI       "$(printf 'SNI 域名(回车默认 www.icloud.com): ')" "www.icloud.com"
    ask_text NODE_NAME "$(printf '节点名称(回车默认用主机名: '$(hostname)') : ')" "$(hostname)"
    info "预检 SNI: https://$SNI"
    if ! curl -fsI --max-time 8 "https://$SNI" >/dev/null 2>&1; then
        warn "域名 $SNI 预检不通(reality 握手可能失败),建议 Ctrl+C 换一个"
    else
        ok "域名可达"
    fi

    gen_params
    if [ "$ENABLE_HY2" = "1" ]; then
        gen_cert
    fi
    write_config
    svc_install
    ok "服务已启动并设为开机自启"

    echo ""
    _fw=""
    [ "$ENABLE_VLESS" = "1" ] && _fw="TCP $VLESS_PORT"
    [ "$ENABLE_HY2" = "1" ]   && _fw="${_fw:+$_fw + }UDP $HY2_PORT"
    warn "记得在云厂商安全组/防火墙放行: $_fw"
    show_links
    printf "\n  ${GRN}装好了${NC} —— 以后直接敲 ${CYN}sb${NC} 出菜单,${CYN}sb -h${NC} 看快捷参数\n\n"
}

# ---------- 查看 ----------
do_info() {
    detect_os
    [ -f "$PARAMS" ] || die "未安装(找不到 $PARAMS)。安装: sb -i"
    load_params
    _ip="$(get_ip)"

    printf "\n${CYN}========== 当前状态 ==========${NC}\n"
    printf '  服务状态  : '
    if svc_status; then printf "${GRN}运行中${NC}\n"
    else printf "${RED}未运行${NC}  (启动: rc-service sb-onekey start)\n"; fi
    if [ -x "$BIN" ]; then
        printf '  sing-box  : v%s\n' "$( "$BIN" version 2>/dev/null | head -1 | awk '{print $3}')"
    else
        printf '  sing-box  : %s\n' "${RED}二进制缺失${NC}"
    fi
    printf '  服务器 IP : %s\n' "$_ip"
    printf '  节点名称  : %s\n' "$NODE_NAME"
    printf '  SNI       : %s\n' "$SNI"
    printf '  配置文件  : %s\n' "$CONF_DIR/config.json"
    printf '\n  已装协议  : '
    _any=""
    if [ "$ENABLE_VLESS" = "1" ]; then printf 'vless-reality'; _any=1; fi
    if [ "$ENABLE_HY2" = "1" ]; then [ -n "$_any" ] && printf ' + '; printf 'hysteria2'; _any=1; fi
    [ -n "$_any" ] || printf "${RED}无(配置异常,执行 sb -p 启用协议)${NC}"
    printf '\n'
    if [ "$ENABLE_VLESS" = "1" ]; then
        printf '    vless   : 端口 %s/TCP  %s\n' "$VLESS_PORT" "$(port_state "$VLESS_PORT" tcp)"
    fi
    if [ "$ENABLE_HY2" = "1" ]; then
        printf '    hy2     : 端口 %s/UDP  %s\n' "$HY2_PORT" "$(port_state "$HY2_PORT" udp)"
    fi
    printf "${CYN}==============================${NC}\n"
    show_links
    printf "\n  改配置: ${CYN}sb -e${NC}    卸载: ${CYN}sb -u${NC}    菜单: ${CYN}sb${NC}    帮助: ${CYN}sb -h${NC}\n\n"
}

# ---------- 编辑 ----------
show_current() {
    printf "\n${CYN}========== 当前配置 ==========${NC}\n"
    printf '  协议      : '
    [ "${ENABLE_VLESS:-1}" = "1" ] && printf 'vless-reality '
    [ "${ENABLE_HY2:-1}" = "1" ]   && printf 'hysteria2'
    printf '\n'
    printf '  节点名称  : %s\n' "$NODE_NAME"
    printf '  SNI       : %s\n' "$SNI"
    [ "${ENABLE_VLESS:-1}" = "1" ] && printf '  vless 端口: %s\n' "$VLESS_PORT"
    [ "${ENABLE_HY2:-1}" = "1" ]   && printf '  hy2 端口  : %s\n' "$HY2_PORT"
    printf "${CYN}==============================${NC}\n"
}

apply_edit() {  # $1=是否重签证书(1/0)
    save_params
    if [ "${ENABLE_HY2:-1}" = "1" ]; then
        if [ "${1:-0}" = "1" ] || [ ! -f "$CONF_DIR/hy2.crt" ] || [ ! -f "$CONF_DIR/hy2.key" ]; then
            gen_cert
        fi
    fi
    write_config
    svc_install >/dev/null 2>&1 || true
    rc-service sb-onekey restart >/dev/null 2>&1
    sleep 1
    svc_status || die "重启失败,查看: tail -30 /var/log/sb-onekey.log"
    ok "已应用并重启"
    show_links
}

toggle_protocols() {
    # 先把当前状态摆出来,用户才知道"删"是删哪个
    if [ "$ENABLE_VLESS" = "1" ]; then _vs="${GRN}已启用${NC} (端口 $VLESS_PORT/TCP)"
    else _vs="${RED}已关闭${NC}"; fi
    if [ "$ENABLE_HY2" = "1" ]; then _hs="${GRN}已启用${NC} (端口 $HY2_PORT/UDP)"
    else _hs="${RED}已关闭${NC}"; fi

    printf '\n当前协议:\n'
    printf '  vless-reality : %b\n' "$_vs"
    printf '  hysteria2     : %b\n' "$_hs"
    printf '\n请选择:\n'
    printf '  1) 删除 hysteria2      → 只留 vless-reality,释放 UDP 端口\n'
    printf '  2) 删除 vless-reality  → 只留 hysteria2,释放 TCP 端口\n'
    printf '  3) 两个都启用          → 缺的自动补上(需要时会问端口)\n'
    printf '  0) 取消\n'
    printf "  ${YLW}提示${NC}: 想连节点配置一起删掉,请选 7 / sb -r\n"
    printf '请选择 [0-3]: '

    _v="$(tty_read)" || { warn "取消"; return 0; }
    _nv="$ENABLE_VLESS"; _nh="$ENABLE_HY2"
    case "$_v" in
        1) _nv=1; _nh=0 ;;
        2) _nv=0; _nh=1 ;;
        3) _nv=1; _nh=1 ;;
        0|'') warn "已取消"; return 0 ;;
        *) warn "无效选择: $_v,已取消"; return 0 ;;
    esac
    if [ "$_nv" = "$ENABLE_VLESS" ] && [ "$_nh" = "$ENABLE_HY2" ]; then
        ok "当前已是该状态,无需修改"; return 0
    fi
    ENABLE_VLESS="$_nv"; ENABLE_HY2="$_nh"
    _del=""
    [ "$ENABLE_VLESS" = "0" ] && _del="vless-reality"
    [ "$ENABLE_HY2" = "0" ] && _del="${_del:+$_del + }hysteria2"

    if [ "$ENABLE_VLESS" = "1" ] && [ -z "${VLESS_PORT:-}" ]; then
        printf 'vless 端口: '
        VLESS_PORT="$(tty_read)"
        case "$VLESS_PORT" in ''|*[!0-9]*) warn "端口非法,已取消"; return 0 ;; esac
    fi
    if [ "$ENABLE_HY2" = "1" ] && [ -z "${HY2_PORT:-}" ]; then
        printf 'hy2 端口: '
        HY2_PORT="$(tty_read)"
        case "$HY2_PORT" in ''|*[!0-9]*) warn "端口非法,已取消"; return 0 ;; esac
    fi
    if [ "$ENABLE_VLESS" = "1" ] && [ "$ENABLE_HY2" = "1" ] && [ "$VLESS_PORT" = "$HY2_PORT" ]; then
        warn "两个端口不能相同,已取消"; return 0
    fi
    apply_edit 0
    [ -n "$_del" ] && ok "已删除协议: $_del(对应端口已释放)"
}

do_edit() {
    detect_os
    load_params

    # ---- 非交互模式: sb -e SNI=xxx VLESS_PORT=6501 ----
    # 注意:必须写 `shift || true`,不能写 `shift 2>/dev/null`
    # (busybox ash 会把 `2` 当成 shift 的参数,直接移掉两个位置参数)
    shift || true
    if [ $# -gt 0 ]; then
        _need_cert=0
        for _kv in "$@"; do
            case "$_kv" in
                *=*) ;;
                *) die "参数格式错误: $_kv (应形如 KEY=VALUE)" ;;
            esac
            _k="${_kv%%=*}"
            _val="${_kv#*=}"
            case "$_k" in
                NODE_NAME)  NODE_NAME="$_val" ;;
                SNI)        SNI="$_val"; _need_cert=1 ;;
                VLESS_PORT) check_new_port "$_val" "${VLESS_PORT:-}" || die "端口不可用: $_val"; VLESS_PORT="$_val" ;;
                HY2_PORT)   check_new_port "$_val" "${HY2_PORT:-}"   || die "端口不可用: $_val"; HY2_PORT="$_val" ;;
                UUID)       UUID="$_val" ;;
                HY2_PASS)   HY2_PASS="$_val" ;;
                SHORT_ID)   SHORT_ID="$_val" ;;
                ENABLE_VLESS) case "$_val" in 0|1) ENABLE_VLESS="$_val" ;; *) die "ENABLE_VLESS 只能是 0 或 1" ;; esac ;;
                ENABLE_HY2)   case "$_val" in 0|1) ENABLE_HY2="$_val"   ;; *) die "ENABLE_HY2 只能是 0 或 1" ;; esac ;;
                *) die "不支持修改: $_k (可用: NODE_NAME SNI VLESS_PORT HY2_PORT UUID HY2_PASS SHORT_ID ENABLE_VLESS ENABLE_HY2)" ;;
            esac
        done
        [ "$ENABLE_VLESS" = "1" ] || [ "$ENABLE_HY2" = "1" ] || die "至少保留一个协议"
        if [ "$ENABLE_VLESS" = "1" ] && [ "$ENABLE_HY2" = "1" ] && [ "$VLESS_PORT" = "$HY2_PORT" ]; then
            die "两个端口不能相同"
        fi
        apply_edit "$_need_cert"
        return
    fi

    # ---- 交互模式 ----
    has_tty || die "非交互环境请用: sb -e SNI=www.nvidia.com VLESS_PORT=6501"
    while :; do
        show_current
        printf '\n修改项:\n'
        printf '  1) 节点名称\n'
        printf '  2) SNI 域名(会重签 hy2 证书)\n'
        printf '  3) vless 端口\n'
        printf '  4) hy2 端口\n'
        printf '  5) 重置 vless UUID\n'
        printf '  6) 重置 hy2 密码\n'
        printf '  7) 重置 reality 密钥对\n'
        printf '  8) 启用/禁用协议\n'
        printf '  9) 只看分享链接\n'
        printf '  0) 退出\n'
        printf '请选择: '
        _c="$(tty_read)" || break
        case "$_c" in
            0|"") ok "退出"; break ;;
            1)
                printf '新节点名称: '
                _v="$(tty_read)" || break
                if [ -n "$_v" ]; then NODE_NAME="$_v"; apply_edit 0; else warn "未输入,已跳过"; fi
                ;;
            2)
                printf '新 SNI 域名: '
                _v="$(tty_read)" || break
                if [ -n "$_v" ]; then
                    info "预检 https://$_v ..."
                    curl -fsI --max-time 8 "https://$_v" >/dev/null 2>&1 \
                        && ok "域名可达" \
                        || warn "域名预检不通,reality 握手可能失败(仍继续)"
                    SNI="$_v"; apply_edit 1
                else
                    warn "未输入,已跳过"
                fi
                ;;
            3)
                if [ "${ENABLE_VLESS:-1}" != "1" ]; then warn "vless 未启用,请先用 8) 启用"; continue; fi
                printf '新 vless 端口(当前 %s): ' "$VLESS_PORT"
                _v="$(tty_read)" || break
                if check_new_port "$_v" "$VLESS_PORT"; then VLESS_PORT="$_v"; apply_edit 0; fi
                ;;
            4)
                if [ "${ENABLE_HY2:-1}" != "1" ]; then warn "hysteria2 未启用,请先用 8) 启用"; continue; fi
                printf '新 hy2 端口(当前 %s): ' "$HY2_PORT"
                _v="$(tty_read)" || break
                if check_new_port "$_v" "$HY2_PORT"; then HY2_PORT="$_v"; apply_edit 0; fi
                ;;
            5)
                UUID="$($BIN generate uuid)"
                ok "新 UUID: $UUID"
                apply_edit 0
                ;;
            6)
                HY2_PASS="$($BIN generate uuid)"
                ok "新 hy2 密码: $HY2_PASS"
                apply_edit 0
                ;;
            7)
                _kp="$($BIN generate reality-keypair)"
                REALITY_PRIV="$(printf '%s' "$_kp" | awk '/PrivateKey/{print $2}')"
                REALITY_PUB="$(printf '%s' "$_kp" | awk '/PublicKey/{print $2}')"
                SHORT_ID="$(openssl rand -hex 8)"
                ok "已重置 reality 密钥对与 short_id"
                apply_edit 0
                ;;
            8) toggle_protocols ;;
            9) show_links ;;
            *) warn "无效选择: $_c" ;;
        esac
    done
}

# ---------- 删除节点(保留 sb 命令,方便以后重装) ----------
do_remove() {
    detect_os
    if [ ! -f "$PARAMS" ] && [ ! -x "$BIN" ]; then
        warn "本机没有 sb-onekey 节点,无需删除"
        return 0
    fi
    rc-service sb-onekey stop >/dev/null 2>&1 || true
    rc-update del sb-onekey default >/dev/null 2>&1 || true
    rm -rf "$CONF_DIR" "$BIN" /var/log/sb-onekey.log /etc/init.d/sb-onekey
    ok "节点已删除,端口已释放"
    ok "sb 命令保留在 $SELF_BIN —— 随时可 sb -i 重装"
}

# ---------- 彻底卸载(节点 + sb 命令) ----------
do_uninstall() {
    detect_os
    rc-service sb-onekey stop >/dev/null 2>&1 || true
    rc-update del sb-onekey default >/dev/null 2>&1 || true
    rm -rf "$CONF_DIR" "$BIN" /var/log/sb-onekey.log /etc/init.d/sb-onekey "$SELF_BIN" "$SELF_BIN_ALT"
    ok "已彻底卸载(节点 + sb 命令都已删除,不影响 fscarmen 等第三方安装)"
    printf "  只想删节点、保留命令的话,下次用: %s\n" "sb -r"
}

# ---------- 重启 / 升级 / 协议切换 ----------
do_restart() {
    check_env
    load_params
    info "重启 sb-onekey..."
    rc-service sb-onekey restart >/dev/null 2>&1
    sleep 1
    if svc_status; then ok "服务运行中"; else die "重启失败,查看: tail -30 /var/log/sb-onekey.log"; fi
}

do_upgrade() {
    check_env
    load_params
    [ -x "$BIN" ] || die "sing-box 二进制缺失,建议先 sb -r 删除再 sb -i 重装"
    _cur="$("$BIN" version 2>/dev/null | head -1 | awk '{print $3}')"
    info "当前版本: v${_cur:-未知}"
    _new="$(latest_version)"
    info "最新版本: v$_new"
    if [ "$_cur" = "$_new" ]; then
        ok "已是最新,无需升级"
        return 0
    fi
    printf '升级到 v%s ? [y/N]: ' "$_new"
    _yn="$(tty_read)" || return 0
    case "$_yn" in y|Y|yes|YES) ;; *) warn "已取消"; return 0 ;; esac
    rc-service sb-onekey stop >/dev/null 2>&1 || true
    SB_VERSION="$_new"
    install_singbox
    save_params
    rc-service sb-onekey start >/dev/null 2>&1
    sleep 1
    if svc_status; then ok "升级完成,服务运行中"; else die "升级后启动失败,查看: tail -30 /var/log/sb-onekey.log"; fi
}

do_edit_protocols() {
    check_env
    load_params
    toggle_protocols
}

# ---------- BBR 加速 ----------
do_bbr() {
    check_env
    _cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    _qd="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    info "当前: 拥塞控制=${_cc:-未知}  队列调度=${_qd:-未知}"
    if [ "$_cc" = "bbr" ]; then
        ok "BBR 已开启,无需操作"
        return 0
    fi
    modprobe tcp_bbr 2>/dev/null || true
    if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
        die "当前内核不支持 BBR(可用算法: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null))"
    fi
    mkdir -p /etc/sysctl.d
    cat > /etc/sysctl.d/99-bbr.conf <<EOF
# 由 sing-box-onekey 写入 ($(date +%F))
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null 2>&1 \
        || sysctl -w net.core.default_qdisc=fq net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    # Alpine: 让 sysctl 服务开机自动加载 /etc/sysctl.d
    [ -f /etc/init.d/sysctl ] && rc-update add sysctl boot >/dev/null 2>&1
    _cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    _qd="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    if [ "$_cc" = "bbr" ]; then
        ok "BBR 已开启: 拥塞控制=$_cc  队列调度=${_qd:-未设置}"
        info "已写入 /etc/sysctl.d/99-bbr.conf,重启后自动生效"
    else
        die "开启失败,当前仍是 ${_cc:-未知}"
    fi
}

# ---------- 主菜单 ----------
do_menu() {
    check_env
    while :; do
        clear 2>/dev/null || true
        show_banner
        if [ -f "$PARAMS" ]; then
            cat <<EOF

 1 . 查看节点信息 / 分享链接       (sb -n)
 2 . 修改节点配置                 (sb -e)
 3 . 增加 / 删除协议              (sb -p)
 4 . 重启服务                     (sb -s)
 5 . 升级 sing-box                (sb -v)
 6 . 开启 BBR 加速                (sb -b)
 7 . 删除节点(保留 sb 命令)       (sb -r)
 8 . 彻底卸载(连 sb 一起删)       (sb -u)
 0 . 退出

EOF
        else
            cat <<EOF

 1 . 安装节点                     (sb -i)
 2 . 帮助                         (sb -h)
 0 . 退出

EOF
        fi
        printf '请选择: '
        _c="$(tty_read)" || return 0
        case "$_c" in
            1) if [ -f "$PARAMS" ]; then do_info; else do_install; fi ;;
            2) if [ -f "$PARAMS" ]; then do_edit; else do_help; fi ;;
            3) if [ -f "$PARAMS" ]; then do_edit_protocols; else warn "未安装"; fi ;;
            4) if [ -f "$PARAMS" ]; then do_restart; else warn "未安装"; fi ;;
            5) if [ -f "$PARAMS" ]; then do_upgrade; else warn "未安装"; fi ;;
            6) do_bbr ;;
            7) if [ -f "$PARAMS" ]; then do_remove; else warn "未安装"; fi ;;
            8) do_uninstall; return 0 ;;
            0|q|Q|exit) return 0 ;;
            '') return 0 ;;
            *) warn "无效选择: $_c" ;;
        esac
        printf '\n按回车返回菜单...'
        tty_read >/dev/null || return 0
    done
}

do_help() {
    printf "\n${CYN}sing-box-onekey — Alpine 一键搭建 vless-reality / hysteria2${NC}\n"
    cat <<EOF

用法:  sb                直接敲 = 出交互菜单(推荐)
       sb <参数>         或按下面短参数调用

  菜单项               短参数    说明
  ------------------   -------   --------------------------------------------
  查看节点信息         sb -n     协议/端口/监听状态/服务状态/分享链接
  修改节点配置         sb -e     改节点名/SNI/端口/重置凭据/启停协议
  增加 / 删除协议      sb -p     删 hy2 / 删 vless / 两个都开
  重启服务             sb -s     重启 sb-onekey 服务
  升级 sing-box        sb -v     检查并升级到最新 release
  开启 BBR 加速        sb -b     写 sysctl 并持久化(已是 BBR 则跳过)
  安装节点             sb -i     已安装会拒绝,需先 sb -r
  删除节点             sb -r     释放端口,保留 sb 命令,以后可再 sb -i
  彻底卸载             sb -u     节点 + sb 命令一起删
  帮助                 sb -h     显示本帮助

  长参数也认: --info / --edit / --protocol / --restart / --upgrade / --bbr
              --install / --remove / --uninstall / --help
  非交互编辑:  sb -e VLESS_PORT=65006 ENABLE_HY2=1

安装时可用的环境变量(非交互):
  PROTOCOLS=vless|hy2|both   选协议,默认交互询问(回车=both)
  VLESS_PORT / HY2_PORT      端口
  SNI                        伪装域名,默认 www.icloud.com
  NODE_NAME                  节点名,默认主机名
  SB_VERSION                 sing-box 版本,默认取最新 release

EOF
}

# 老版本(≤v1.6)装的没有 sb 命令。除安装/卸载类参数外顺手补装一次,
# 这样 `sh sing-box-onekey.sh info` 跑一下就自动有了 sb,不用卸载重装。
case "${1:-}" in
    install|-i|--install|uninstall|-u|--uninstall|purge|remove|-r|--remove|del|rm|delete|bbr|-b|--bbr) ;;
    *) install_self ;;
esac

# 参数分发
case "${1:-}" in
    "")
        if [ -f "$PARAMS" ]; then
            # 已装节点:有终端进菜单,无终端只打状态
            if has_tty; then do_menu; else do_info; fi
        elif [ "$(readlink -f "$0" 2>/dev/null)" = "$(readlink -f "$SELF_BIN" 2>/dev/null)" ] && has_tty; then
            # 敲的是已安装的 sb 命令但节点已删 => 出菜单(1安装/2帮助/0退出),别擅自开装
            do_menu
        else
            # 首次运行脚本(curl|sh 或 sh xxx.sh) => 直接进安装流程
            do_install
        fi
        ;;
    -i|--install|install)                          do_install ;;
    -n|--info|--status|info|status|show)           do_info ;;
    -e|--edit|edit)                                do_edit "$@" ;;
    -p|--protocol|protocol)                        do_edit_protocols ;;
    -s|--restart|restart)                          do_restart ;;
    -v|--upgrade|upgrade)                          do_upgrade ;;
    -b|--bbr|bbr)                                  do_bbr ;;
    -r|--remove|remove|del|rm|delete)              do_remove ;;
    -u|--uninstall|uninstall|purge)                do_uninstall ;;
    -h|--help|help)                                do_help ;;
    *) die "未知参数: $1  (敲 sb -h 看帮助)" ;;
esac

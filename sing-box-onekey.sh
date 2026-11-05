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
#    sb                  # 交互菜单(13 项:信息/改配置/协议/重启/升级/BBR/删节点/卸载/… )
#    sb -n  查看节点信息      sb -e  修改节点配置      sb -p  增减协议
#    sb -s  重启服务          sb -v  升级 sing-box     sb -b  开启 BBR
#    sb -r  删除节点(留命令)  sb -u  彻底卸载          sb -h  帮助
#    sb -e SNI=www.nvidia.com VLESS_PORT=65010    # 非交互编辑
#
#  v2.0 新增「伪装模式」: steal(借用大厂,默认) / own(自建伪装站点,自有域名+真证书)
#    sb domain        一键「自建伪装站点」:签 LE 证书 + 装 nginx 回落站 + 改配置 + 出链接
#    sb domain --adopt  只把现有手工配置反填进 params.env,不重建
#    sb doctor        体检(服务/端口归属/handshake/证书/解析/回落站)
#    sb backup        备份配置      sb rollback  回滚到上一份备份
#    sb site          伪装站点模板(内置 tech / poetry 两套)
#    sb reload-cert   给 acme.sh 当续期钩子(nginx reload + 同步证书 + 重启)
# =============================================================
set -u

SB_FALLBACK_VERSION="1.14.3"          # GitHub API 不可用时的兜底版本
SCRIPT_VER="2.4"                      # 本脚本自身版本(用于判断 sb 是否需要更新)
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

# ---------- 伪装模式相关(默认 steal,老用户行为不变) ----------
TLS_MODE="${TLS_MODE:-}"              # steal | own
DOMAIN="${DOMAIN:-}"                  # own 模式的自有域名(= SNI)
ACME_EMAIL="${ACME_EMAIL:-}"
WEBROOT="${WEBROOT:-/var/www/acme}"
SITE_ROOT="${SITE_ROOT:-/var/www/site}"
FALLBACK_PORT="${FALLBACK_PORT:-8001}"
CERT_DIR="${CERT_DIR:-}"
BACKUP_DIR="$CONF_DIR/backup"
NGX_DIR="/etc/nginx/http.d"
NGX_CONF="$NGX_DIR/sb-onekey.conf"
ACME_HOME="/root/.acme.sh"

# 内置伪装站点模板(tar.gz + base64)。源码在仓库 themes/ 下,改完跑 tools/embed-themes.sh 重新生成
THEME_TECH_B64='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'
THEME_POETRY_B64='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'

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

# 危险操作二次确认。无终端(脚本化调用)时跳过确认,保持 sb -r 可非交互使用
confirm_yn() {  # $1=提示语  0=确认 1=取消
    if ! has_tty; then
        warn "非交互环境,跳过确认直接执行"
        return 0
    fi
    printf '%s [y/N]: ' "$1"
    _yn="$(tty_read)" || return 1
    case "$_yn" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
    esac
}

install_deps() {
    _need=""
    for _c in curl openssl tar; do
        command -v "$_c" >/dev/null 2>&1 || _need="$_need $_c"
    done
    # ★ sing-box 官方 linux 二进制是 glibc 动态链接的,Alpine(musl) 必须有 gcompat 才能执行。
    #   缺它时报错是 `sh: /usr/local/bin/sb-onekey: not found`(不是 cannot execute),
    #   极易误判成"文件没装上",实际文件在、只是动态链接器找不到。
    apk info -e gcompat >/dev/null 2>&1 || _need="$_need gcompat"
    if [ -z "$_need" ]; then
        ok "依赖已存在(curl/openssl/tar/gcompat),无需安装"
        return 0
    fi
    info "缺少:$_need —— 开始安装..."
    apk update >/dev/null 2>&1 || warn "apk update 失败(源可能不可达),继续尝试安装"
    if ! apk add --no-cache curl openssl tar gcompat >/dev/null 2>&1; then
        die "依赖安装失败。请依次检查:
  1) Alpine 源是否可用: cat /etc/apk/repositories
  2) 网络/DNS 是否通:   ping -c2 dl-cdn.alpinelinux.org
  3) 磁盘是否满:        df -h /
  手动补装: apk add curl openssl tar gcompat"
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
    # ★ 必须显式判错:包损坏/磁盘满时 tar 静默失败 => $BIN 不存在 => 后面会误报"缺 gcompat"
    tar xzf "$_tmp/sb.tar.gz" -C "$_tmp" \
        || { rm -rf "$_tmp"; die "sing-box 解压失败(包损坏或磁盘空间不足),请检查 df -h /"; }
    install -m755 "$_tmp/sing-box-${SB_VERSION}-linux-${ARCH}/sing-box" "$BIN" \
        || { rm -rf "$_tmp"; die "sing-box 安装到 $BIN 失败(权限不足?),请检查 /usr/local/bin 是否可写"; }
    rm -rf "$_tmp"
    # ★ 装完必须试跑一次:musl 系统缺 gcompat 时二进制"在但不执行",旧版会打出
    #   `[OK] sing-box  安装完成`(版本号空),后面才在生成密钥时报 not found
    _v="$( "$BIN" version 2>/dev/null | head -1 | awk '{print $3}' )"
    if [ -z "$_v" ]; then
        warn "sing-box 二进制无法执行(常见原因:缺 gcompat),尝试自动补装..."
        apk add --no-cache gcompat >/dev/null 2>&1 || true
        _v="$( "$BIN" version 2>/dev/null | head -1 | awk '{print $3}' )"
        [ -n "$_v" ] || die "sing-box 已装上但跑不起来。手动排查:
  1) 补依赖:  apk add gcompat
  2) 看报错:  /usr/local/bin/sb-onekey version
  3) 查架构:  uname -m (应为 x86_64 或 aarch64)"
    fi
    ok "sing-box v$_v 安装完成"
}

# ---------- 参数生成与持久化 ----------
# 把值安全地写进 params.env:单引号包裹 + 去掉值里自带的单引号
# ★必须加引号 —— 否则 NODE_NAME="香港 节点1" 会写成 `NODE_NAME=香港 节点1`,
#   source 时被解析成「赋值 NODE_NAME=香港」+「执行命令 节点1」→ not found
_sq() { printf "'%s'" "$(printf '%s' "$1" | tr -d "'")"; }

save_params() {
    mkdir -p "$CONF_DIR"
    cat > "$PARAMS" <<EOF
ENABLE_VLESS=$ENABLE_VLESS
ENABLE_HY2=$ENABLE_HY2
VLESS_PORT=$VLESS_PORT
HY2_PORT=$HY2_PORT
SNI=$(_sq "$SNI")
NODE_NAME=$(_sq "$NODE_NAME")
SB_VERSION=$SB_VERSION
REALITY_PRIV=$REALITY_PRIV
REALITY_PUB=$REALITY_PUB
UUID=$UUID
SHORT_ID=$SHORT_ID
HY2_PASS=$HY2_PASS
TLS_MODE=$(_sq "${TLS_MODE:-steal}")
DOMAIN=$(_sq "${DOMAIN:-}")
ACME_EMAIL=$(_sq "${ACME_EMAIL:-}")
FALLBACK_PORT=$(_sq "${FALLBACK_PORT:-8001}")
CERT_DIR=$(_sq "${CERT_DIR:-}")
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
    # ★ 这里只生成、不落盘。落盘由调用方在 write_config($BIN check) 通过之后再做,
    #   否则校验失败时 params.env 已经存在 => 下次 do_install 判定"已安装"拒绝重装,
    #   用户被迫先 sb -r 清干净才能重来。
}

load_params() {
    [ -f "$PARAMS" ] || die "未找到 $PARAMS,请先安装"
    . "$PARAMS"
    # 兼容 v1.2 及更早(无 ENABLE_* 字段):默认两个协议都启用
    : "${ENABLE_VLESS:=1}"
    : "${ENABLE_HY2:=1}"
    # 兼容 v1.x(无 TLS_MODE 字段):按老行为 = 借用大厂
    : "${TLS_MODE:=steal}"
    : "${DOMAIN:=}"
    : "${ACME_EMAIL:=}"
    : "${FALLBACK_PORT:=8001}"
    : "${CERT_DIR:=}"
    # own 模式必须自洽:没有域名/证书目录就当参数残缺,直接拦住
    if [ "$TLS_MODE" = "own" ]; then
        [ -n "$DOMAIN" ] || die "TLS_MODE=own 但 DOMAIN 为空,请重新执行: sb domain"
        [ -n "$CERT_DIR" ] || die "TLS_MODE=own 但 CERT_DIR 为空,请重新执行: sb domain"
    fi
    # 协议启用但端口为空 => 参数残缺
    if [ "$ENABLE_VLESS" = "1" ] && [ -z "${VLESS_PORT:-}" ]; then
        die "参数异常: ENABLE_VLESS=1 但 VLESS_PORT 为空,请重新安装"
    fi
    if [ "$ENABLE_HY2" = "1" ] && [ -z "${HY2_PORT:-}" ]; then
        die "参数异常: ENABLE_HY2=1 但 HY2_PORT 为空,请重新安装"
    fi
}

# ---------- 证书路径与回落目标(按伪装模式分流) ----------
# steal: hy2 自签(链接必须带 insecure + pinSHA256);reality 回落到 $SNI:443(别人的站)
# own  : hy2 用 ACME 真证书(链接只带 sni);reality 回落到本机 nginx 127.0.0.1:8001
hy2_crt() {
    if [ "${TLS_MODE:-steal}" = "own" ]; then printf '%s/fullchain.pem' "$CERT_DIR"
    else printf '%s/hy2.crt' "$CONF_DIR"; fi
}
hy2_key() {
    if [ "${TLS_MODE:-steal}" = "own" ]; then printf '%s/key.pem' "$CERT_DIR"
    else printf '%s/hy2.key' "$CONF_DIR"; fi
}
# 返回 "host port" 两个字段,调用方用 set -- 拆
fallback_target() {
    if [ "${TLS_MODE:-steal}" = "own" ]; then
        printf '127.0.0.1 %s\n' "${FALLBACK_PORT:-8001}"
    else
        printf '%s 443\n' "$SNI"
    fi
}

# ---------- hy2 证书 ----------
gen_cert() {
    # own 模式不自签:证书由 sb domain 用 acme.sh 签好放在 CERT_DIR,这里只校验
    if [ "${TLS_MODE:-steal}" = "own" ]; then
        _c="$(hy2_crt)"; _k="$(hy2_key)"
        [ -f "$_c" ] && [ -f "$_k" ] || die "own 模式需要 ACME 证书,但 $_c 不存在。执行: sb domain"
        ok "hy2 使用 ACME 证书: $_c"
        return 0
    fi
    # ★ 自己保证目录存在:调用链上 gen_cert 早于 write_config/save_params,
    #   不能指望它们顺带 mkdir(2026-10-22 v1.13 实测踩过,报"证书生成失败")
    mkdir -p "$CONF_DIR"
    chmod 700 "$CONF_DIR" 2>/dev/null || true
    rc-service sb-onekey stop >/dev/null 2>&1 || true
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$CONF_DIR/hy2.key" -out "$CONF_DIR/hy2.crt" \
        -days 3650 -nodes \
        -subj "/CN=$SNI" -addext "subjectAltName=DNS:$SNI" 2>/dev/null \
        || die "证书生成失败"
    chmod 600 "$CONF_DIR/hy2.key" 2>/dev/null || true
    ok "hy2 自签证书生成 ($SNI, 10年)"
}

# ---------- 配置生成(协议块模块化,新协议加一个 gen_inbound_xxx 再挂进 write_config) ----------
gen_inbound_vless() {
    set -- $(fallback_target)
    _hs_srv="$1"; _hs_port="$2"
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
          "handshake": { "server": "$_hs_srv", "server_port": $_hs_port },
          "private_key": "$REALITY_PRIV",
          "short_id": [ "$SHORT_ID" ]
        }
      }
    }
EOF
}

gen_inbound_hy2() {
    _crt="$(hy2_crt)"; _key="$(hy2_key)"
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
        "certificate_path": "$_crt",
        "key_path": "$_key"
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
    # ★ config.json 含 reality 私钥 / hy2 密码 / UUID,不能让本机其它用户读到。
    #   Alpine 默认 umask 022 会落成 644,必须显式收紧(目录同理,否则能列文件名)
    chmod 700 "$CONF_DIR" 2>/dev/null || true
    chmod 600 "$CONF_DIR/config.json" 2>/dev/null || true
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
    svc_wait_ready || die "服务启动失败,查看日志: tail -30 /var/log/sb-onekey.log"
}

svc_status() {
    rc-service sb-onekey status >/dev/null 2>&1
}

# 等服务真正起来再判失败。低配机器加载 REALITY 密钥 + 绑端口可能超过 1 秒,
# 固定 sleep 1 会误报"启动失败"(用户看到失败但服务其实起来了)。
svc_wait_ready() {  # 最多等 5 秒
    _w=0
    while [ "$_w" -lt 5 ]; do
        svc_status && return 0
        _w=$((_w + 1))
        sleep 1
    done
    return 1
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
        0) printf "${GRN}监听中${NC}"
           _o="$(port_owner "$1" 2>/dev/null)"
           [ -n "$_o" ] && printf " %s" "$(printf "${YLW}(%s)${NC}" "$_o")" ;;
        1) printf "${RED}未监听${NC}" ;;
        *) printf "${YLW}无法判断${NC}" ;;
    esac
}

# 查端口归属进程(纯 /proc:端口 → inode → /proc/*/fd 反查)
# ★ 光看"监听中"会误判:nginx 占着 443 时,sb 菜单也会显示"vless 443 监听中",
#   实际 sing-box 根本没起来。必须把归属进程一起打出来。
port_owner() {  # $1=端口  输出 "pid:comm",找不到返回 1
    _hp="$(printf '%04X' "$1" 2>/dev/null)" || return 1
    _inodes=""
    for _f in /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do
        [ -r "$_f" ] || continue
        _inodes="$_inodes $(awk -v h="$_hp" 'NR>1 { n=split($2,a,":"); if (n==2 && toupper(a[2])==h) print $10 }' "$_f" 2>/dev/null)"
    done
    _inodes="$(printf '%s' "$_inodes" | tr ' ' '\n' | grep -v '^$' | sort -u)"
    [ -n "$_inodes" ] || return 1
    for _p in /proc/[0-9]*; do
        [ -d "$_p/fd" ] || continue
        for _fd in "$_p"/fd/*; do
            _t="$(readlink "$_fd" 2>/dev/null)" || continue
            case "$_t" in
                socket:\[*\]) _i="${_t#socket:[}"; _i="${_i%]}" ;;
                *) continue ;;
            esac
            for _want in $_inodes; do
                if [ "$_i" = "$_want" ]; then
                    # ★ 不能用 /proc/PID/comm:Alpine 上 sing-box 是经 ld-musl 启动的,
                    #   comm 会截成 "ld-musl-x86_64." ,按名字根本认不出是谁
                    _cmd="$(tr '\0' ' ' < "$_p/cmdline" 2>/dev/null)"
                    case "$_cmd" in
                        *sb-onekey*) _cmd="sb-onekey" ;;
                        *nginx*)     _cmd="nginx" ;;
                        *realm*)     _cmd="realm" ;;
                        *)
                            _cmd="${_cmd%% *}"; _cmd="${_cmd##*/}"
                            _cmd="$(printf '%.20s' "$_cmd")" ;;
                    esac
                    [ -n "$_cmd" ] || _cmd="$(cat "$_p/comm" 2>/dev/null)"
                    printf '%s:%s' "${_p#/proc/}" "$_cmd"
                    return 0
                fi
            done
        done
    done
    return 1
}

# 落盘前的硬检查:端口归属 / 域名解析 / 磁盘
# 2026-10-31 实战:cdt-2 上 nginx 占了 443 还去开 Reality,sing-box 直接
# `bind: address already in use` 崩溃,而菜单照样显示"443 监听中",排查半小时。
preflight() {  # 返回 0=可以继续
    _pf=0
    if [ "${ENABLE_VLESS:-1}" = "1" ] && [ "${VLESS_PORT:-}" = "443" ]; then
        _own="$(port_owner 443)"
        case "$_own" in
            ''|*:sb-onekey) ;;
            *) warn "443 已被占用: $_own —— Reality 绑不上"
               warn "若占用者是 nginx,删掉它配置里所有 listen 443 的 server 段,再 nginx -s reload"
               _pf=1 ;;
        esac
    elif [ "${TLS_MODE:-steal}" = "own" ] && [ "${ENABLE_VLESS:-1}" = "1" ]; then
        # Reality 不在 443:443 该由 nginx 提供伪装站,被别人占着就只能缺这块
        _own="$(port_owner 443)"
        case "$_own" in
            ''|*:nginx) ;;
            *) warn "443 被 $_own 占用 —— 伪装站挂不到 443(节点本身不受影响)"
               warn "腾出 443 后重跑 sb domain 即可补上" ;;
        esac
    fi
    if [ "${TLS_MODE:-steal}" = "own" ] && [ -n "${DOMAIN:-}" ]; then
        _pip="$(get_ip 2>/dev/null)" || _pip=""
        _dns="$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)"
        if [ -n "$_dns" ] && [ -n "$_pip" ] && [ "$_dns" != "$_pip" ]; then
            warn "$DOMAIN 解析到 $_dns,本机是 $_pip —— A 记录没指对,ACME 会签不下来"
            _pf=1
        fi
    fi
    _free="$(df -Pk / 2>/dev/null | awk 'NR==2{print int($4/1024)}')"
    if [ -n "$_free" ] && [ "$_free" -lt 50 ]; then
        warn "根分区只剩 ${_free}M,装 nginx + acme.sh 可能不够(需要约 15M)"
    fi
    return $_pf
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
    # ★ 用 mktemp 而不是 /tmp/.xxx.$$:PID 可预测,本机低权限用户可预先建同名符号链接,
    #   让 root 的 cp / curl -o / chmod 全部作用到链接目标 => 任意文件写入。
    #   mktemp 以 O_EXCL 创建不可预测文件名,天然免疫。
    _tmp="$(mktemp /tmp/.sb-install.XXXXXX 2>/dev/null)" || {
        warn "临时文件创建失败,跳过 sb 安装(不影响节点)"
        return 0
    }
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
    if ! grep -q "sing-box-onekey" "$_tmp" 2>/dev/null || ! sh -n "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"
        warn "sb 内容或语法校验失败,已跳过(不影响节点)"
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
        _crt="$(hy2_crt)"
        _n2="$(urlencode "${NODE_NAME} hy2")"
        if [ "${TLS_MODE:-steal}" = "own" ]; then
            # own 模式:ACME 真证书,客户端正常校验证书链 => 不带 insecure / pinSHA256
            [ -f "$_crt" ] || die "hy2 证书缺失: $_crt  (执行: sb domain)"
            _iss="$(openssl x509 -in "$_crt" -noout -issuer 2>/dev/null | sed 's/.*CN *= *//')"
            _end="$(openssl x509 -in "$_crt" -noout -enddate 2>/dev/null | sed 's/notAfter=//')"
            echo "hysteria2://${HY2_PASS}@${_ip}:${HY2_PORT}?sni=${SNI}#${_n2}"
            echo ""
            info "hy2 证书: ${_iss:-未知签发者} / 到期 ${_end:-未知}"
        else
            _fp="$(openssl x509 -in "$_crt" -outform der 2>/dev/null | openssl dgst -sha256 -hex | awk '{print $2}' | tr -d ':' | tr 'a-z' 'A-Z')"
            [ -n "$_fp" ] || die "hy2 证书缺失或损坏,请执行: sb -e 重新生成证书"
            echo "hysteria2://${HY2_PASS}@${_ip}:${HY2_PORT}?sni=${SNI}&insecure=1&pinSHA256=${_fp}#${_n2}"
            echo ""
        fi
    fi
    printf "${CYN}==============================${NC}\n"
}

port_busy() {  # $1=端口
    # 复用 port_listen(纯 /proc 实现),少一层对 busybox applet / net-tools 的依赖,
    # 也与菜单里"端口监听状态"的判定口径完全一致。
    port_listen "$1" tcp && return 0
    port_listen "$1" udp && return 0
    return 1
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

# SNI 白名单校验:只允许域名合法字符
# ★ 不能用黑名单(只拒空格)。SNI 有两个危险去向:
#   ① gen_cert 的 -subj "/CN=$SNI" —— 含 / = , + 会破坏 DN 结构,openssl 报错或生成畸形证书
#   ② gen_inbound_* 直接拼进 JSON —— 含 " 或 \ 会让 JSON 非法
#   两种情况最终都只会报"配置校验失败",排查成本高,不如在入口就拦住。
check_sni() {  # $1=SNI  合法返回 0
    case "$1" in
        '')                warn "SNI 不能为空"; return 1 ;;
        *[!A-Za-z0-9.-]*)  warn "SNI 只能含字母/数字/点/连字符,收到: $1"; return 1 ;;
    esac
    return 0
}

detect_existing() {
    # fscarmen 版 sing-box:二进制在 /etc/sing-box/、配置在 /etc/sing-box/conf
    if [ -x /etc/sing-box/sing-box ] || [ -d /etc/sing-box/conf ]; then
        warn "检测到 fscarmen 版 sing-box,本脚本与其完全隔离(服务名 sb-onekey,目录 /etc/sb-onekey),可共存"
    fi
}

# =============================================================
#  伪装模式:自建伪装站点(own) —— 自有域名 + ACME 真证书 + 本机回落站
#  设计取舍:
#   · 不碰 /etc/nginx/http.d/default.conf,本脚本只写自己的 sb-onekey.conf,
#     卸载时删这一个文件即可,不会把别人的站点配置搞坏
#   · 证书直接放 CERT_DIR,hy2 读同一份 => 不再有"自签副本忘了同步"的问题
#   · acme.sh 续期钩子只调 `sb reload-cert`,证书路径怎么变都不用改钩子
#   · 443 归属按 VLESS_PORT 动态决定:等于 443 留给 Reality;不等于 443 时由 nginx 接管,
#     否则 80 的 return 301 指向空端口,浏览器访问域名直接卡在 TLS 握手前(v2.4)
# =============================================================

# ---------- 备份 / 回滚 ----------
backup_now() {  # 成功则输出时间戳,失败返回 1
    [ -f "$CONF_DIR/config.json" ] || return 1
    _ts="$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR/$_ts" || return 1
    cp -f "$CONF_DIR/config.json" "$BACKUP_DIR/$_ts/" 2>/dev/null || true
    cp -f "$PARAMS" "$BACKUP_DIR/$_ts/" 2>/dev/null || true
    chmod -R 600 "$BACKUP_DIR/$_ts" 2>/dev/null || true
    # 只留最近 5 份,低配机器别把磁盘吃光
    ls -1 "$BACKUP_DIR" 2>/dev/null | sort -r | tail -n +6 | while read -r _d; do
        rm -rf "$BACKUP_DIR/$_d"
    done
    printf '%s' "$_ts"
}

do_backup() {
    _t="$(backup_now)" || die "备份失败(还没有 config.json?)"
    ok "已备份: $BACKUP_DIR/$_t"
}

do_rollback() {
    [ -d "$BACKUP_DIR" ] || die "没有备份目录($BACKUP_DIR)"
    _list="$(ls -1 "$BACKUP_DIR" 2>/dev/null | sort -r)"
    [ -n "$_list" ] || die "没有可用备份"
    printf '\n可用备份(新→旧):\n'
    printf '%s\n' "$_list" | sed 's/^/    /'
    _newest="$(printf '%s' "$_list" | head -1)"
    printf '恢复哪一份 [回车=最新 %s]: ' "$_newest"
    _pick="$(tty_read)" || _pick=""
    [ -n "$_pick" ] || _pick="$_newest"
    [ -d "$BACKUP_DIR/$_pick" ] || die "没有这份备份: $_pick"
    confirm_yn "用 $_pick 覆盖当前配置?" || { warn "已取消"; return 0; }
    cp -f "$BACKUP_DIR/$_pick/config.json" "$CONF_DIR/config.json" || die "恢复 config.json 失败"
    [ -f "$BACKUP_DIR/$_pick/params.env" ] && cp -f "$BACKUP_DIR/$_pick/params.env" "$PARAMS"
    chmod 600 "$CONF_DIR/config.json" "$PARAMS" 2>/dev/null || true
    rc-service sb-onekey restart >/dev/null 2>&1
    svc_wait_ready || die "回滚后服务起不来,看日志: tail -30 /var/log/sb-onekey.log"
    ok "已回滚到 $_pick"
}

# ---------- nginx ----------
ngx_ensure() {
    if ! command -v nginx >/dev/null 2>&1; then
        info "安装 nginx ..."
        apk add --no-cache nginx >/dev/null 2>&1 || die "nginx 安装失败(检查 apk 源 / 磁盘)"
    fi
    rc-update add nginx default >/dev/null 2>&1 || true
    mkdir -p "$WEBROOT/.well-known/acme-challenge" "$SITE_ROOT"
}

# nginx 1.25.1 起才有 `http2 on;`,老版本只认 listen 上的 http2 参数
_ngx_http2_line() {  # $1=listen 参数(如 "127.0.0.1:8001 ssl")
    _nv="$(nginx -v 2>&1 | sed -n 's#.*nginx/\([0-9][0-9.]*\).*#\1#p')"
    _maj="$(printf '%s' "$_nv" | cut -d. -f1)"
    _min="$(printf '%s' "$_nv" | cut -d. -f2)"
    if [ -n "$_maj" ] && { [ "$_maj" -gt 1 ] || { [ "$_maj" -eq 1 ] && [ "$_min" -ge 25 ]; }; }; then
        printf '    listen %s;\n    http2 on;\n' "$1"
    else
        printf '    listen %s http2;\n' "$1"
    fi
}

# 阶段 1:只有 80(签证书时还没证书文件,带 ssl 的 server 会让 nginx 起不来)
ngx_write_conf_stage1() {
    mkdir -p "$NGX_DIR"
    cat > "$NGX_CONF" <<EOF
# 由 sb domain 生成(阶段1:仅 ACME 验证)。别手工改,重跑 sb domain 会覆盖。
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ { root $WEBROOT; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
}

# Reality 不在 443 时,由 nginx 在 443 提供伪装站(与回落站同一份内容)
# 2026-11-05 实战:singapore 上 VLESS_PORT=65002,443 空转,
#   而 80 的 return 301 指向 443 => 浏览器打不开域名,来回死循环。
ngx_site_443() {
    {
        printf '\nserver {\n'
        _ngx_http2_line "443 ssl"
        cat <<EOF
    listen [::]:443 ssl;
    server_name $DOMAIN;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    root $SITE_ROOT;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
    }
}

# 阶段 2:加 127.0.0.1:FALLBACK_PORT 回落站(Reality 握手失败时兜底)
ngx_write_conf() {
    mkdir -p "$NGX_DIR"
    # 443 归谁:Reality 在 443 就留给它;不在 443 就让 nginx 接管,否则 80 的 301 落空
    _ngx_own443=0
    if [ "${VLESS_PORT:-}" != "443" ]; then
        _o443="$(port_owner 443 2>/dev/null)" || _o443=""
        case "$_o443" in
            ''|*:nginx) _ngx_own443=1 ;;
            *) warn "443 被 $_o443 占用,跳过 443 伪装站(节点不受影响)"
               warn "腾出 443 后重跑 sb domain 即可补上" ;;
        esac
    fi
    {
        printf '# 由 sb domain 生成。别手工改,重跑 sb domain 会覆盖。\n'
        if [ "$_ngx_own443" = "1" ]; then
            printf '# Reality 在 %s,443 由 nginx 提供伪装站(与回落站同一份内容)\n' "${VLESS_PORT:-}"
        else
            printf '# 注意:这里绝对不能 listen 443 —— 443 归 sing-box(Reality)\n'
        fi
        cat <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ { root $WEBROOT; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 127.0.0.1:$FALLBACK_PORT ssl default_server;
    ssl_reject_handshake on;
}

server {
EOF
        _ngx_http2_line "127.0.0.1:$FALLBACK_PORT ssl"
        cat <<EOF
    server_name $DOMAIN;

    ssl_certificate     $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/key.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    root $SITE_ROOT;
    index index.html;
    location / { try_files \$uri \$uri/ =404; }
}
EOF
    } > "$NGX_CONF"
    [ "$_ngx_own443" = "1" ] && ngx_site_443 >> "$NGX_CONF"
    return 0
}

ngx_apply() {  # 写配置并生效,失败自动删掉自己的配置并报错
    if ! nginx -t >/dev/null 2>&1; then
        _err="$(nginx -t 2>&1 | tail -3)"
        rm -f "$NGX_CONF"
        die "nginx 配置校验失败,已撤回 $NGX_CONF。原因:
$_err
常见: 别的配置文件里已有 listen 443 或占用了 $FALLBACK_PORT"
    fi
    if rc-service nginx status >/dev/null 2>&1; then
        nginx -s reload >/dev/null 2>&1 || rc-service nginx restart >/dev/null 2>&1 || true
    else
        rc-service nginx start >/dev/null 2>&1 || true
    fi
    # nginx -t 只验语法,不验端口占用。reload 撞端口时会静默失败,这里兜住
    if ! rc-service nginx status >/dev/null 2>&1; then
        die "nginx 起不来。常见原因: $FALLBACK_PORT 或 443 被别的进程占用
查: nginx -t; ss -tlnp | grep -E ':443 |:$FALLBACK_PORT '"
    fi
    if [ "${_ngx_own443:-0}" = "1" ] && ! port_listen 443; then
        warn "nginx 在跑但 443 没监听 —— 443 伪装站未生效,查: ss -tlnp | grep ':443 '"
    fi
}

# ---------- ACME ----------
acme_ensure() {
    if [ ! -x "$ACME_HOME/acme.sh" ]; then
        info "安装 acme.sh ..."
        _mail="${ACME_EMAIL:-admin@$DOMAIN}"
        curl -fsSL https://get.acme.sh | sh -s email="$_mail" >/dev/null 2>&1 \
            || die "acme.sh 安装失败。手动装: curl https://get.acme.sh | sh"
    fi
    [ -x "$ACME_HOME/acme.sh" ] || die "acme.sh 不可用($ACME_HOME/acme.sh)"
}

acme_issue() {
    acme_ensure
    mkdir -p "$CERT_DIR" "$WEBROOT/.well-known/acme-challenge"
    # 幂等:已有证书且 30 天内不过期就跳过签发,重跑 sb domain 不会去碰 ACME 频控
    if [ -f "$CERT_DIR/fullchain.pem" ] && \
       openssl x509 -in "$CERT_DIR/fullchain.pem" -noout -checkend 2592000 >/dev/null 2>&1; then
        ok "证书已存在且 30 天内不会过期,跳过签发"
    else
        info "申请证书 $DOMAIN (HTTP-01 / webroot) ..."
        "$ACME_HOME/acme.sh" --issue -d "$DOMAIN" -w "$WEBROOT" --keylength ec-256 \
            || die "证书签发失败。逐项检查:
  1) $DOMAIN 的 A 记录是否已指到本机(灰云,别开 CDN 代理)
  2) 安全组是否放行 80
  3) nginx 是否在跑: rc-service nginx status
  4) 验证路径是否可访问: curl -I http://$DOMAIN/.well-known/acme-challenge/test"
    fi
    "$ACME_HOME/acme.sh" --install-cert -d "$DOMAIN" --ecc \
        --key-file "$CERT_DIR/key.pem" \
        --fullchain-file "$CERT_DIR/fullchain.pem" \
        --reloadcmd "$SELF_BIN reload-cert" \
        || die "证书安装失败(acme.sh --install-cert)"
    chmod 600 "$CERT_DIR/key.pem" 2>/dev/null || true
    ok "证书已就位: $CERT_DIR"
}

# 给 acme.sh 当 --reloadcmd 用。只做"让新证书生效",不做签发
do_reload_cert() {
    [ -f "$PARAMS" ] || return 0
    ( . "$PARAMS" 2>/dev/null ) || true
    nginx -s reload >/dev/null 2>&1 || true
    rc-service sb-onekey restart >/dev/null 2>&1 || true
    printf '[sb reload-cert] %s  nginx reload + sb-onekey restart\n' "$(date '+%Y-%m-%d %H:%M:%S')"
}

# ---------- 内置伪装站点模板 ----------
# 两套主题以 tar.gz + base64 内嵌,离线可用;源码另存在仓库 themes/ 下,
# 改了模板用 tools/embed-themes.sh 重新生成下面两个变量。
site_install() {  # $1=主题 $2=目标目录
    _theme="${1:-tech}"; _dst="${2:-$SITE_ROOT}"
    case "$_theme" in
        tech)   _b64="$THEME_TECH_B64" ;;
        poetry) _b64="$THEME_POETRY_B64" ;;
        *) die "未知主题: $_theme (可用: tech / poetry)" ;;
    esac
    mkdir -p "$_dst" || die "目录创建失败: $_dst"
    _tmp="$(mktemp -d)" || die "临时目录创建失败"
    if ! printf '%s' "$_b64" | base64 -d > "$_tmp/t.tar.gz" 2>/dev/null; then
        rm -rf "$_tmp"
        die "主题解码失败(base64 -d 不可用)"
    fi
    tar xzf "$_tmp/t.tar.gz" -C "$_dst" || { rm -rf "$_tmp"; die "主题解压失败"; }
    rm -rf "$_tmp"
    ok "站点已铺到 $_dst (主题: $_theme)"
}

do_site() {
    load_params
    shift || true
    _theme=""; _dst=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --theme=*) _theme="${1#*=}" ;;
            --dir=*)   _dst="${1#*=}" ;;
            --theme)   shift; _theme="${1:-}" ;;
            --dir)     shift; _dst="${1:-}" ;;
            *) die "未知参数: $1  (用法: sb site --theme=poetry [--dir=/var/www/site])" ;;
        esac
        shift || true
    done
    [ -n "$_theme" ] || _theme="tech"
    [ -n "$_dst" ] || _dst="$SITE_ROOT"
    if [ -d "$_dst" ] && [ -n "$(ls -A "$_dst" 2>/dev/null)" ]; then
        confirm_yn "$_dst 非空,覆盖?" || { warn "已取消"; return 0; }
        _bak="$_dst.bak-$(date +%Y%m%d%H%M%S)"
        cp -a "$_dst" "$_bak" 2>/dev/null || true
        info "旧内容已备份到 $_bak"
        find "$_dst" -mindepth 1 -delete 2>/dev/null || true
    fi
    site_install "$_theme" "$_dst"
}

# ---------- 一键自建伪装站点 ----------
do_domain() {
    check_env
    [ -f "$PARAMS" ] || die "请先安装节点(sb -i),再用 sb domain 切换成自有域名"
    load_params
    shift || true

    case "${1:-}" in
        --adopt) do_adopt; return ;;
        '') ;;
        *) die "未知参数: $1  (用法: sb domain | sb domain --adopt)" ;;
    esac

    # 非交互也能跑:域名/邮箱可用环境变量给(DOMAIN=... ACME_EMAIL=... SITE_THEME=...)
    printf '\n当前: 模式=%s  SNI=%s\n' "$TLS_MODE" "$SNI"
    _d="$(env_val DOMAIN)"
    if [ -z "$_d" ]; then
        has_tty || die "非交互环境请用环境变量: DOMAIN=node.example.com sb domain"
        printf '自有域名(如 node.example.com,必须已把 A 记录指到本机): '
        _d="$(tty_read)" || _d=""
    fi
    [ -n "$_d" ] || die "域名不能为空"
    check_sni "$_d" || die "域名非法: $_d"
    DOMAIN="$_d"
    case "$DOMAIN" in *.*) ;; *) die "域名至少要有一个点: $DOMAIN" ;; esac

    _m="$(env_val ACME_EMAIL)"
    if [ -z "$_m" ] && has_tty; then
        printf 'ACME 通知邮箱(可空,回车跳过): '
        _m="$(tty_read)" || _m=""
    fi
    ACME_EMAIL="$_m"
    CERT_DIR="/etc/nginx/certs/$DOMAIN"
    [ -n "${FALLBACK_PORT:-}" ] || FALLBACK_PORT=8001

    # DNS 必须先指对,否则 ACME 必然失败(白等两分钟)
    _pip="$(get_ip 2>/dev/null)" || _pip=""
    _dns="$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)"
    if [ -n "$_dns" ] && [ -n "$_pip" ] && [ "$_dns" != "$_pip" ]; then
        warn "$DOMAIN 解析到 $_dns,本机是 $_pip"
        confirm_yn "A 记录还没指对,继续会签发失败。仍要继续?" || { warn "已取消,先把 A 记录改到 $_pip"; return 0; }
    else
        ok "DNS 指向: ${_dns:-未取到} / 本机 ${_pip:-未取到}"
    fi

    info "1/5 准备 nginx 与站点目录"
    ngx_ensure
    ngx_write_conf_stage1
    ngx_apply
    ok "nginx 就绪(80 端口 ACME 验证已开)"

    info "2/5 申请证书"
    acme_issue

    info "3/5 铺伪装站点"
    if [ -z "$(ls -A "$SITE_ROOT" 2>/dev/null)" ]; then
        _theme="$(env_val SITE_THEME)"
        if [ -z "$_theme" ] && has_tty; then
            printf '站点主题 1) tech(技术博客) 2) poetry(古诗词) [回车=tech]: '
            _t="$(tty_read)" || _t=""
            case "$_t" in 2|poetry) _theme="poetry" ;; *) _theme="tech" ;; esac
        fi
        [ -n "$_theme" ] || _theme="tech"
        site_install "$_theme" "$SITE_ROOT"
    else
        ok "$SITE_ROOT 已有内容,跳过铺站(要换主题: sb site --theme=poetry)"
    fi

    info "4/5 写回落站并生效"
    ngx_write_conf
    ngx_apply
    ok "回落站就绪: 127.0.0.1:$FALLBACK_PORT"

    info "5/5 切换节点到 own 模式"
    backup_now >/dev/null 2>&1 || true
    TLS_MODE="own"
    SNI="$DOMAIN"
    preflight || { warn "预检有问题(见上),已中止,配置未改"; return 1; }
    gen_cert
    write_config
    save_params
    svc_install >/dev/null 2>&1 || true
    rc-service sb-onekey restart >/dev/null 2>&1
    svc_wait_ready || die "服务起不来,看日志: tail -30 /var/log/sb-onekey.log"

    echo ""
    ok "已切换为「自建伪装站点」模式"
    printf '  Reality 回落 -> 127.0.0.1:%s (nginx)\n' "$FALLBACK_PORT"
    printf '  hy2 证书    -> %s (ACME 真证书,链接不再需要 insecure/pin)\n' "$CERT_DIR"
    if [ "${VLESS_PORT:-}" != "443" ] && port_listen 443; then
        printf '  伪装站点    -> https://%s (443,nginx;与回落站同一份内容)\n' "$DOMAIN"
    fi
    show_links
}

# 把已经手工配好的机器反填进 params.env,不重建任何东西
do_adopt() {
    check_env
    [ -f "$PARAMS" ] || die "未安装,没什么可收养的"
    load_params
    _hit=""
    [ -n "${DOMAIN:-}" ] || DOMAIN="$SNI"
    if [ -z "${CERT_DIR:-}" ] && [ -f "/etc/nginx/certs/$DOMAIN/fullchain.pem" ]; then
        CERT_DIR="/etc/nginx/certs/$DOMAIN"
    fi
    if grep '"handshake"' "$CONF_DIR/config.json" 2>/dev/null | grep -q '127\.0\.0\.1'; then
        TLS_MODE="own"; _hit="handshake 指向 127.0.0.1"
    fi
    if [ -f "$NGX_CONF" ] || [ -f "$NGX_DIR/default.conf" ]; then
        _hit="$_hit${_hit:+, }发现 nginx 回落配置"
    fi
    if [ "$TLS_MODE" != "own" ]; then
        warn "没检测到 own 模式特征(handshake 不指向 127.0.0.1),保持 $TLS_MODE 不变"
        save_params
        return 0
    fi
    [ -n "$CERT_DIR" ] || die "检测到 own 模式,但找不到证书目录。请手动指定: sb -e 不支持,直接编辑 $PARAMS 的 CERT_DIR"
    [ -f "$CERT_DIR/fullchain.pem" ] || die "证书不存在: $CERT_DIR/fullchain.pem"
    save_params
    ok "已收养(${_hit}): TLS_MODE=own DOMAIN=$DOMAIN CERT_DIR=$CERT_DIR"
    printf '  建议接着跑: %s\n' "sb doctor"
}

# ---------- 体检 ----------
_ck() {  # $1=名称 $2=0/1(1=通过) $3=说明
    if [ "$2" = "1" ]; then printf "  [${GRN}OK${NC}] %-14s %s\n" "$1" "$3"
    else printf "  [${RED}!!${NC}] %-14s %s\n" "$1" "$3"; _bad=$((_bad + 1)); fi
}

do_doctor() {
    check_env
    [ -f "$PARAMS" ] || die "未安装(sb -i)"
    load_params
    _bad=0
    _ip="$(get_ip 2>/dev/null)" || _ip=""

    printf "\n${CYN}========== 体检 (%s 模式) ==========${NC}\n" "$TLS_MODE"

    # 1 服务
    if svc_status; then _ck 服务 1 "运行中"
    else _ck 服务 0 "未运行 —— rc-service sb-onekey status / tail -30 /var/log/sb-onekey.log"; fi

    # 2 端口监听 + 归属
    if [ "$ENABLE_VLESS" = "1" ]; then
        if port_listen "$VLESS_PORT" tcp; then
            _o="$(port_owner "$VLESS_PORT" 2>/dev/null)"
            case "$_o" in
                *sb-onekey*) _ck "vless $VLESS_PORT" 1 "监听中 ($_o)" ;;
                '')          _ck "vless $VLESS_PORT" 1 "监听中" ;;
                *)           _ck "vless $VLESS_PORT" 0 "被别的进程占用: $_o" ;;
            esac
        else
            _ck "vless $VLESS_PORT" 0 "TCP 未监听"
        fi
    fi
    if [ "$ENABLE_HY2" = "1" ]; then
        if port_listen "$HY2_PORT" udp; then _ck "hy2 $HY2_PORT" 1 "UDP 监听中"
        else _ck "hy2 $HY2_PORT" 0 "UDP 未监听"; fi
    fi

    # 3 handshake 指向是否与模式一致
    _hs="$(grep '"handshake"' "$CONF_DIR/config.json" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')"
    if [ "$TLS_MODE" = "own" ]; then
        case "$_hs" in
            *127.0.0.1*) _ck handshake 1 "$_hs" ;;
            *)           _ck handshake 0 "应为 127.0.0.1:$FALLBACK_PORT,实际 $_hs (重跑 sb domain)" ;;
        esac
    else
        case "$_hs" in
            *127.0.0.1*) _ck handshake 0 "steal 模式却指向本机,Reality 会失败" ;;
            *)           _ck handshake 1 "$_hs" ;;
        esac
    fi

    # 4 hy2 证书
    if [ "$ENABLE_HY2" = "1" ]; then
        _crt="$(hy2_crt)"
        if [ -f "$_crt" ]; then
            _iss="$(openssl x509 -in "$_crt" -noout -issuer 2>/dev/null | sed 's/.*CN *= *//')"
            _sub="$(openssl x509 -in "$_crt" -noout -subject 2>/dev/null | sed 's/.*CN *= *//')"
            if [ "$TLS_MODE" = "own" ]; then
                case "$_iss" in
                    *Let*|*R3*|*R10*|*R11*|*E1*|*E5*|*E6*|*YE*|*ZeroSSL*|*ISRG*) _ck hy2证书 1 "$_sub / $_iss" ;;
                    *) _ck hy2证书 0 "不是 ACME 签发(${_iss:-未知}),own 模式下客户端会校验失败" ;;
                esac
            else
                _ck hy2证书 1 "自签 $_sub(链接需带 insecure+pinSHA256)"
            fi
            if openssl x509 -in "$_crt" -noout -checkend 1209600 >/dev/null 2>&1; then :; else
                _ck 证书有效期 0 "14 天内到期,检查 acme.sh cron: crontab -l | grep acme"
            fi
        else
            _ck hy2证书 0 "缺失: $_crt"
        fi
    fi

    # 5 域名解析
    if [ "$TLS_MODE" = "own" ]; then
        _dns="$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: /{print $2}' | tail -1)"
        if [ -z "$_dns" ]; then _ck "DNS $DOMAIN" 0 "解析不到"
        elif [ -n "$_ip" ] && [ "$_dns" != "$_ip" ]; then _ck "DNS $DOMAIN" 0 "$_dns ≠ 本机 $_ip"
        else _ck "DNS $DOMAIN" 1 "$_dns"; fi
    fi

    # 6/7 回落站:正确 SNI 通、错误 SNI 拒
    if [ "$TLS_MODE" = "own" ]; then
        _code="$(curl -s -o /dev/null -w '%{http_code}' -k --max-time 6 \
            --resolve "$DOMAIN:$FALLBACK_PORT:127.0.0.1" "https://$DOMAIN:$FALLBACK_PORT/" 2>/dev/null)"
        [ "$_code" = "200" ] && _ck 回落站 1 "本机 $DOMAIN:$FALLBACK_PORT -> 200" \
                             || _ck 回落站 0 "本机回落站返回 ${_code:-无响应}(nginx 起了吗)"
        _code2="$(curl -s -o /dev/null -w '%{http_code}' -k --max-time 6 \
            --resolve "x.invalid:$FALLBACK_PORT:127.0.0.1" "https://x.invalid:$FALLBACK_PORT/" 2>/dev/null)"
        [ "$_code2" = "000" ] && _ck 错SNI 1 "已拒绝(ssl_reject_handshake 生效)" \
                              || _ck 错SNI 0 "错误 SNI 也返回 $_code2,回落站会变成开放反代"
    fi

    printf "${CYN}===================================${NC}\n"
    if [ "$_bad" = "0" ]; then ok "全部通过"
    else warn "$_bad 项异常,按上面提示处理"; fi
    printf '\n'
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

    ask_text SNI       "$(printf 'SNI 域名(回车默认 www.broadcom.com): ')" "www.broadcom.com"
    check_sni "$SNI" || die "SNI 非法,已中止(换一个域名重试)"
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
    # 全部校验通过才落盘:失败时 params.env 不落地,可直接重跑 sb -i 重来
    save_params
    ok "参数已持久化到 $PARAMS"
    svc_install
    ok "服务已启动并设为开机自启"

    echo ""
    _fw=""
    [ "$ENABLE_VLESS" = "1" ] && _fw="TCP $VLESS_PORT"
    [ "$ENABLE_HY2" = "1" ]   && _fw="${_fw:+$_fw + }UDP $HY2_PORT"
    warn "记得在云厂商安全组/防火墙放行: $_fw"
    show_links
    printf "\n  ${GRN}装好了${NC} —— 以后直接敲 ${CYN}sb${NC} 出菜单,${CYN}sb -h${NC} 看快捷参数\n"
    printf "  想改用自建伪装站点? ${CYN}sb domain${NC}  (自动签证书 + 装回落站 + 改配置)\n\n"
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
        _sbv="$( "$BIN" version 2>/dev/null | head -1 | awk '{print $3}')"
        if [ -n "$_sbv" ]; then
            printf '  sing-box  : v%s\n' "$_sbv"
        else
            printf '  sing-box  : %s\n' "${RED}无法执行 —— 多半缺 gcompat,执行: apk add gcompat${NC}"
        fi
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
    # 先备份再动手:今天(cdt-2)就是 sb -e 把 handshake 改回指向自己导致服务起不来
    backup_now >/dev/null 2>&1 || true
    preflight || die "预检未通过(见上),配置未改动。修好后再试"
    if [ "${ENABLE_HY2:-1}" = "1" ]; then
        if [ "${1:-0}" = "1" ] || [ ! -f "$(hy2_crt)" ] || [ ! -f "$(hy2_key)" ]; then
            gen_cert
        fi
    fi
    write_config
    # 同 do_install:校验通过才落盘,避免"SNI 改了但配置没生成成功"的半残状态
    save_params
    svc_install >/dev/null 2>&1 || true
    rc-service sb-onekey restart >/dev/null 2>&1
    svc_wait_ready || die "重启失败,查看: tail -30 /var/log/sb-onekey.log"
    ok "已应用并重启"
    show_links
}

# 启用协议时的端口确认:回车沿用原值,输入新值就换
_pick_port() {  # $1=变量名 $2=显示名
    eval "_cur=\${$1:-}"
    printf '%s 端口 [回车沿用 %s]: ' "$2" "${_cur:-无记录}"
    _p="$(tty_read)" || _p=""
    [ -n "$_p" ] || _p="$_cur"
    case "$_p" in ''|*[!0-9]*) warn "端口非法,保持原值"; return 1 ;; esac
    [ "$_p" -ge 1 ] && [ "$_p" -le 65535 ] || { warn "端口范围 1-65535,保持原值"; return 1; }
    if [ "$_p" != "$_cur" ] && port_busy "$_p"; then
        warn "端口 $_p 已被占用,保持原值"; return 1
    fi
    eval "$1=\$_p"
    return 0
}

toggle_protocols() {
    # 一行一个协议,动作跟着当前状态走:启用着的显示「停用」,停用的显示「启用」。
    # 旧版是「1 删 hy2 / 2 删 vless / 3 两个都启用」——动作方向不一致,只有一个协议在跑时
    # 另一个选项还是无效动作,老板实测时看不明白,已改。
    if [ "$ENABLE_VLESS" = "1" ]; then _vs="${GRN}启用中${NC} ($VLESS_PORT/TCP)"
    else _vs="${RED}已停用${NC}"; fi
    if [ "$ENABLE_HY2" = "1" ]; then _hs="${GRN}启用中${NC} ($HY2_PORT/UDP)"
    else _hs="${RED}已停用${NC}"; fi
    if [ "$ENABLE_VLESS" = "1" ]; then _a1="停用 vless-reality  (释放 $VLESS_PORT/TCP)"
    else _a1="启用 vless-reality  (端口 ${VLESS_PORT:-未记录}/TCP)"; fi
    if [ "$ENABLE_HY2" = "1" ]; then _a2="停用 hysteria2      (释放 $HY2_PORT/UDP)"
    else _a2="启用 hysteria2      (端口 ${HY2_PORT:-未记录}/UDP)"; fi

    printf '\n当前状态:\n'
    printf '  vless-reality : %b\n' "$_vs"
    printf '  hysteria2     : %b\n' "$_hs"
    printf '\n不会重置 UUID / 密码 / 证书,已有链接继续有效。\n'
    printf '\n请选择:\n'
    printf '  1) %s\n' "$_a1"
    printf '  2) %s\n' "$_a2"
    printf '  0) 取消\n'
    printf '  （要删整个节点:先按 0 退出本菜单,再在主菜单按 7）\n'
    printf '请选择 [0-2]: '

    _v="$(tty_read)" || { warn "取消"; return 0; }
    case "$_v" in
        1) _which=vless ;;
        2) _which=hy2 ;;
        0|'') warn "已取消"; return 0 ;;
        *) warn "无效选择: $_v,已取消"; return 0 ;;
    esac

    if [ "$_which" = "vless" ]; then
        if [ "$ENABLE_VLESS" = "1" ]; then
            ENABLE_VLESS=0
            _done="已停用 vless-reality,端口 $VLESS_PORT/TCP 已释放"
        else
            ENABLE_VLESS=1
            _pick_port VLESS_PORT vless
            [ -n "${VLESS_PORT:-}" ] || die "vless 端口为空,无法启用"
            _done="已启用 vless-reality ($VLESS_PORT/TCP)"
        fi
    else
        if [ "$ENABLE_HY2" = "1" ]; then
            ENABLE_HY2=0
            _done="已停用 hysteria2,端口 $HY2_PORT/UDP 已释放"
        else
            ENABLE_HY2=1
            _pick_port HY2_PORT hy2
            [ -n "${HY2_PORT:-}" ] || die "hy2 端口为空,无法启用"
            _done="已启用 hysteria2 ($HY2_PORT/UDP)"
        fi
    fi

    if [ "$ENABLE_VLESS" = "1" ] && [ "$ENABLE_HY2" = "1" ] && [ "$VLESS_PORT" = "$HY2_PORT" ]; then
        warn "两个端口不能相同,已取消(配置未改动)"; return 0
    fi
    apply_edit 0
    ok "$_done"
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
                SNI)        check_sni "$_val" || die "SNI 非法: $_val"; SNI="$_val"; _need_cert=1 ;;
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
                    check_sni "$_v" || { warn "SNI 非法,已取消(配置未改动)"; continue; }
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
    check_env
    if [ ! -f "$PARAMS" ] && [ ! -x "$BIN" ]; then
        warn "本机没有 sb-onekey 节点,无需删除"
        return 0
    fi
    # 只读变量,不用 load_params(参数残缺时不该连删都删不掉)
    # ★ set -u 对 source 同样生效:params.env 里若有未定义变量引用,shell 会直接退出,
    #   2>/dev/null 只重定向 stderr、拦不住。必须先关掉 -u 再 source。
    if [ -f "$PARAMS" ]; then
        set +u
        . "$PARAMS" 2>/dev/null
        set -u
    fi

    printf "\n${YLW}========== 删除节点确认 ==========${NC}\n"
    printf '  节点名称  : %s\n' "${NODE_NAME:-未知}"
    printf '  已装协议  : '
    _any=""
    if [ "${ENABLE_VLESS:-0}" = "1" ]; then printf 'vless-reality(%s/TCP)' "${VLESS_PORT:-?}"; _any=1; fi
    if [ "${ENABLE_HY2:-0}" = "1" ]; then
        [ -n "$_any" ] && printf ' + '
        printf 'hysteria2(%s/UDP)' "${HY2_PORT:-?}"
    fi
    printf '\n\n'
    printf "  ${RED}将会删除${NC}:\n"
    printf '    · 服务 sb-onekey(停止 + 取消开机自启)\n'
    printf '    · /etc/sb-onekey(配置 / 参数 / 证书)\n'
    printf '    · /usr/local/bin/sb-onekey(sing-box 二进制)\n'
    printf '    · /var/log/sb-onekey.log\n'
    printf "\n  ${RED}后果${NC}: UUID / 密码 / 证书全部丢失,重装后分享链接会变\n"
    printf "  ${GRN}只想删一个协议?${NC} 取消后改用 ${CYN}3 / sb -p${NC} —— 另一个协议继续工作、凭据保留\n"
    printf "${YLW}==================================${NC}\n"
    if ! confirm_yn '确认删除节点?'; then
        warn "已取消,什么都没删"
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
    check_env
    printf "\n${YLW}========== 彻底卸载确认 ==========${NC}\n"
    printf "  ${RED}将会删除${NC}:\n"
    printf '    · 节点(服务 / /etc/sb-onekey / 二进制 / 日志)\n'
    printf '    · sb 命令本身(/usr/local/bin/sb 与 sbctl)\n'
    printf "\n  ${RED}后果${NC}: 删完 sb 就 not found,想再装得重新下载脚本\n"
    printf "  ${GRN}只想删节点?${NC} 取消后改用 ${CYN}7 / sb -r${NC} —— sb 命令会保留\n"
    printf "${YLW}==================================${NC}\n"
    if ! confirm_yn '确认彻底卸载?'; then
        warn "已取消,什么都没删"
        return 0
    fi
    rc-service sb-onekey stop >/dev/null 2>&1 || true
    rc-update del sb-onekey default >/dev/null 2>&1 || true
    rm -rf "$CONF_DIR" "$BIN" /var/log/sb-onekey.log /etc/init.d/sb-onekey "$SELF_BIN" "$SELF_BIN_ALT"
    ok "已彻底卸载(节点 + sb 命令都已删除,不影响 fscarmen 等第三方安装)"
    # nginx 回落站配置不自动删:它可能还托着别的域名,误删代价太大
    if [ -f "$NGX_CONF" ]; then
        printf "\n  ${YLW}注意${NC}: 回落站配置还在 —— %s\n" "$NGX_CONF"
        printf '  确认没别的域名在用,可手工清理:\n'
        printf '    rm %s && nginx -s reload\n' "$NGX_CONF"
        printf '  站点文件(如还需要): %s\n' "$SITE_ROOT"
    fi
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

    # ★ 已经是 bbr 也不能直接 return —— 镜像默认开 / 别人临时开过的机器,
    #   往往只有运行值、没有持久化,重启就退回 cubic。这里统一补齐三件套。
    _fixed=""
    if [ "$_cc" != "bbr" ] || [ "$_qd" != "fq" ]; then
        modprobe tcp_bbr 2>/dev/null || true
        if ! grep -qw bbr /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null; then
            die "当前内核不支持 BBR(可用算法: $(cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null))"
        fi
    fi
    if [ ! -f /etc/sysctl.d/99-bbr.conf ]; then
        mkdir -p /etc/sysctl.d
        cat > /etc/sysctl.d/99-bbr.conf <<EOF
# 由 sing-box-onekey 写入 ($(date +%F))
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
        _fixed=1
    fi
    if [ "$_cc" != "bbr" ] || [ "$_qd" != "fq" ]; then
        sysctl -p /etc/sysctl.d/99-bbr.conf >/dev/null 2>&1 \
            || sysctl -w net.core.default_qdisc=fq net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
        _fixed=1
    fi
    # 开机自动加载模块 + 应用 sysctl(缺一项重启后就可能失效)
    touch /etc/modules 2>/dev/null || true
    grep -qx tcp_bbr /etc/modules 2>/dev/null || { echo tcp_bbr >> /etc/modules; _fixed=1; }
    [ -f /etc/init.d/sysctl ]  && rc-update add sysctl boot  >/dev/null 2>&1
    [ -f /etc/init.d/modules ] && rc-update add modules boot >/dev/null 2>&1

    _cc="$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    _qd="$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    if [ "$_cc" != "bbr" ]; then
        die "开启失败,当前仍是 ${_cc:-未知}"
    fi
    if [ -n "$_fixed" ]; then
        ok "BBR 已开启: 拥塞控制=$_cc  队列调度=${_qd:-未设置}"
        info "已补齐持久化(99-bbr.conf + /etc/modules),重启后自动生效"
    else
        ok "BBR 已开启且持久化完整: 拥塞控制=$_cc  队列调度=${_qd:-未设置}"
    fi
}

# ---------- 检查 / 升级脚本自身 ----------
# 版本比较:$1 > $2 返回 0(纯数字点分,如 1.10 > 1.9)
_ver_gt() {
    _a="$1"; _b="$2"
    while :; do
        _x="${_a%%.*}"; _y="${_b%%.*}"
        case "$_x" in ''|*[!0-9]*) _x=0 ;; esac
        case "$_y" in ''|*[!0-9]*) _y=0 ;; esac
        [ "$_x" -gt "$_y" ] && return 0
        [ "$_x" -lt "$_y" ] && return 1
        case "$_a" in *.*) _a="${_a#*.}" ;; *) _a="" ;; esac
        case "$_b" in *.*) _b="${_b#*.}" ;; *) _b="" ;; esac
        [ -z "$_a" ] && [ -z "$_b" ] && return 1
    done
}

# 拉远端脚本、取版本号,并把「版本更高」的那份内容留在 $1 指向的文件里。
# ★ raw.githubusercontent.com 的 CDN 行为不稳定(2026-10-22 实测):
#   同一时刻「不带 query」拿到 v1.13(新)、「带 ?t=时间戳」反而拿到 v1.12(旧)。
#   v1.12 加 ?t= 的初衷是绕缓存,实际在某些边缘节点上适得其反。
#   所以两个都拉,按版本号取高的 —— 任一通道拿到新版都能升上去。
_fetch_remote_ver() {  # $1=输出文件  $2=单次超时秒数(默认 20)  输出=远端版本号(取不到则空)
    _frv_f="$1"
    _frv_to="${2:-20}"
    _frv_alt="$(mktemp /tmp/.sb-alt.XXXXXX 2>/dev/null)" || _frv_alt=""
    _frv_best=""
    curl -fsSL --max-time "$_frv_to" "$SELF_URL" -o "$_frv_f" 2>/dev/null || : > "$_frv_f"
    _frv_best="$(sed -n 's/^SCRIPT_VER="\([^"]*\)".*/\1/p' "$_frv_f" 2>/dev/null | head -1)"
    if [ -n "$_frv_alt" ]; then
        if curl -fsSL --max-time "$_frv_to" -H 'Cache-Control: no-cache' "$SELF_URL?t=$(date +%s)" -o "$_frv_alt" 2>/dev/null; then
            _frv_v2="$(sed -n 's/^SCRIPT_VER="\([^"]*\)".*/\1/p' "$_frv_alt" 2>/dev/null | head -1)"
            if [ -n "$_frv_v2" ] && { [ -z "$_frv_best" ] || _ver_gt "$_frv_v2" "$_frv_best"; }; then
                mv -f "$_frv_alt" "$_frv_f" 2>/dev/null && _frv_best="$_frv_v2"
            fi
        fi
        rm -f "$_frv_alt"
    fi
    printf '%s' "$_frv_best"
}

do_self_update() {
    check_env
    info "当前脚本版本: v$SCRIPT_VER"
    info "正在检查远端最新版..."
    _tmp="$(mktemp /tmp/.sb-onekey-upd.XXXXXX 2>/dev/null)" || die "临时文件创建失败(检查 /tmp 是否可写)"
    _rv="$(_fetch_remote_ver "$_tmp")"
    if [ -z "$_rv" ]; then
        rm -f "$_tmp"
        die "远端返回内容异常(取不到版本号),已中止,原脚本未改动"
    fi
    if [ "$_rv" = "$SCRIPT_VER" ]; then
        rm -f "$_tmp"
        ok "已是最新版 v$SCRIPT_VER,无需更新"
        return 0
    fi
    if _ver_gt "$SCRIPT_VER" "$_rv"; then
        rm -f "$_tmp"
        ok "本地 v$SCRIPT_VER 比远端 v$_rv 还新(自己改过?),不覆盖"
        return 0
    fi
    info "发现新版本: v$SCRIPT_VER → v$_rv"
    if ! confirm_yn "升级到 v$_rv?"; then
        rm -f "$_tmp"
        warn "已取消,脚本未改动"
        return 0
    fi
    # 下载内容必须语法通过,否则绝不覆盖(防止把 404 页面写进 sb)
    if ! sh -n "$_tmp" 2>/dev/null; then
        rm -f "$_tmp"
        die "下载的脚本语法校验失败,已中止,原脚本未改动"
    fi
    # ★ 不能 install 覆盖正在执行的自己(Text file busy):先落临时名再 mv
    if ! cp "$_tmp" "$SELF_BIN.new" 2>/dev/null || ! chmod 755 "$SELF_BIN.new" 2>/dev/null \
       || ! mv -f "$SELF_BIN.new" "$SELF_BIN" 2>/dev/null; then
        rm -f "$_tmp" "$SELF_BIN.new"
        die "覆盖 $SELF_BIN 失败(权限?),手动执行:
  curl -fsSL $SELF_URL -o $SELF_BIN && chmod +x $SELF_BIN"
    fi
    rm -f "$_tmp"
    _ensure_alt_link
    ok "脚本已升级: v$SCRIPT_VER → v$_rv"
    info "重新敲 sb 生效(当前这次运行的还是旧版)"
}

# ---------- 进菜单时静默自检版本 ----------
# 老版本不认识 sb -U(先有鸡还是先有蛋),所以菜单里常驻一行提示:
# 每次会话只查一次、仅交互终端才查、超时 4s 静默放弃,查不到就当没这回事。
_SELF_CHK=0
check_self_version_quiet() {
    [ "$_SELF_CHK" = "1" ] && return 0
    _SELF_CHK=1
    has_tty || return 0
    _tmp="$(mktemp /tmp/.sb-verchk.XXXXXX 2>/dev/null)" || return 0
    _rv="$(_fetch_remote_ver "$_tmp" 4)"
    rm -f "$_tmp"
    case "$_rv" in
        ''|*[!0-9.]*) return 0 ;;
    esac
    [ "$_rv" = "$SCRIPT_VER" ] && return 0
    _ver_gt "$SCRIPT_VER" "$_rv" && return 0
    printf "${YLW}[有新版本] 脚本 v$SCRIPT_VER → v$_rv,敲菜单里的「检查脚本更新」或 sb -U 升级${NC}\n"
}

# ---------- 主菜单 ----------
do_menu() {
    check_env
    while :; do
        clear 2>/dev/null || true
        show_banner
        if [ -f "$PARAMS" ]; then
            cat <<EOF

 1 . 查看节点信息 / 分享链接      (sb -n)
 2 . 修改节点配置                 (sb -e)
 3 . 启用 / 停用协议(单个)        (sb -p)
 4 . 重启服务                     (sb -s)
 5 . 升级 sing-box                (sb -v)
 6 . 开启 BBR 加速                (sb -b)
 7 . 删除整个节点(保留 sb 命令)   (sb -r)
 8 . 彻底卸载(连 sb 一起删)       (sb -u)
 9 . 检查脚本更新(升 sb 自身)     (sb -U)
 10. 自建伪装站点                 (sb domain)
 11. 体检(端口/证书/回落站)       (sb doctor)
 12. 备份配置 / 回滚              (sb backup / sb rollback)
 13. 伪装站点模板(tech/poetry)    (sb site)
 0 . 退出

EOF
        else
            cat <<EOF

 1 . 安装节点                     (sb -i)
 2 . 帮助                         (sb -h)
 3 . 彻底卸载(连 sb 一起删)       (sb -u)
 4 . 检查脚本更新(升 sb 自身)     (sb -U)
 0 . 退出

EOF
        fi
        check_self_version_quiet
        printf '请选择: '
        _c="$(tty_read)" || return 0
        case "$_c" in
            1) if [ -f "$PARAMS" ]; then do_info; else do_install; fi ;;
            2) if [ -f "$PARAMS" ]; then do_edit; else do_help; fi ;;
            3) if [ -f "$PARAMS" ]; then do_edit_protocols; else do_uninstall; return 0; fi ;;
            4) if [ -f "$PARAMS" ]; then do_restart; else do_self_update; fi ;;
            5) if [ -f "$PARAMS" ]; then do_upgrade; else warn "未安装"; fi ;;
            6) do_bbr ;;
            7) if [ -f "$PARAMS" ]; then do_remove; else warn "未安装"; fi ;;
            8) do_uninstall; return 0 ;;
            9) do_self_update ;;
            10) do_domain "$@" ;;
            11) do_doctor ;;
            12) do_backup; printf '\n回滚请用: sb rollback\n' ;;
            13) do_site "$@" ;;
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
  启用 / 停用协议      sb -p     只动单个协议,另一个继续用,凭据保留
  重启服务             sb -s     重启 sb-onekey 服务
  升级 sing-box        sb -v     检查并升级到最新 release
  开启 BBR 加速        sb -b     写 sysctl 并持久化(已是 BBR 则跳过)
  安装节点             sb -i     已安装会拒绝,需先 sb -r
  删除整个节点         sb -r     服务/配置/证书全清(会二次确认),保留 sb 命令
  彻底卸载             sb -u     节点 + sb 命令一起删
  检查脚本更新         sb -U     对比远端版本,有新版可一键升级 sb 自身
  自建伪装站点         sb domain  签 LE 证书 + 装 nginx 回落站 + 改配置 + 出链接
                      sb domain --adopt  只把现有手工配置反填进 params.env
  体检                 sb doctor 服务/端口归属/handshake/证书/解析/回落站 逐项检查
  备份 / 回滚          sb backup / sb rollback   配置改动前自动备份,留最近 5 份
  伪装站点模板         sb site --theme=poetry|tech [--dir=路径]
  续期钩子             sb reload-cert  给 acme.sh 当 --reloadcmd,别手工调
  帮助                 sb -h     显示本帮助

  长参数也认: --info / --edit / --protocol / --restart / --upgrade / --bbr
              --install / --remove / --uninstall / --update / --help
  非交互编辑:  sb -e VLESS_PORT=65006 ENABLE_HY2=1

  版本自检:    敲 sb 进菜单 —— 远端有新版时,菜单上方会自己冒出黄色提示
               或 sb -U 立即比对(顺便可一键升)
  升级脚本:    sb -U  (只换 sb 命令,不动节点/配置/证书)
  老版本升级:  当前 sb 若不认识 -U,先执行:
                 curl -fsSL https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh -o /usr/local/bin/sb && chmod +x /usr/local/bin/sb

安装时可用的环境变量(非交互):
  PROTOCOLS=vless|hy2|both   选协议,默认交互询问(回车=both)
  VLESS_PORT / HY2_PORT      端口
  SNI                        伪装域名,默认 www.broadcom.com
  NODE_NAME                  节点名,默认主机名
  SB_VERSION                 sing-box 版本,默认取最新 release

两种伪装模式(装完可随时用 sb domain 切换):
  steal(默认)  借用大厂:SNI 指向别人的站,Reality 回落到 $SNI:443;hy2 自签证书,
               链接必须带 insecure=1&pinSHA256=...
  own          自建伪装站点:自有域名 + ACME 真证书 + 本机 nginx 回落站(127.0.0.1:8001),
               hy2 链接只带 sni。要求:A 记录指到本机(灰云)、80 端口放行

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
    -U|--update|--self-update|update|self-update)  do_self_update ;;
    -d|--domain|domain)                            do_domain "$@" ;;
    -t|--doctor|doctor|check)                      do_doctor ;;
    -k|--backup|backup)                            do_backup ;;
    --rollback|rollback)                           do_rollback ;;
    --site|site)                                   do_site "$@" ;;
    --reload-cert|reload-cert)                     do_reload_cert ;;
    -h|--help|help)                                do_help ;;
    *) die "未知参数: $1  (敲 sb -h 看帮助)" ;;
esac

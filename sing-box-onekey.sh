#!/bin/sh
# =============================================================
#  sing-box-onekey.sh — 裸机一键搭建 vless-reality + hysteria2
#
#  支持: Alpine / Debian / Ubuntu (自动识别系统与 init)
#  用法:
#    wget -qO- https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh | sh
#    sh sing-box-onekey.sh              # 安装(交互输入端口/域名/节点名)
#    VLESS_PORT=6501 HY2_PORT=6502 sh sing-box-onekey.sh   # 环境变量跳过交互
#    sh sing-box-onekey.sh info         # 查看参数与分享链接
#    sh sing-box-onekey.sh uninstall    # 彻底卸载
# =============================================================
set -u

SB_FALLBACK_VERSION="1.14.3"          # GitHub API 不可用时的兜底版本
CONF_DIR="/etc/sb-onekey"
PARAMS="$CONF_DIR/params.env"
BIN="/usr/local/bin/sb-onekey"
VLESS_PORT="${VLESS_PORT:-}"
HY2_PORT="${HY2_PORT:-}"
SNI="${SNI:-}"
NODE_NAME="${NODE_NAME:-}"
SB_VERSION="${SB_VERSION:-}"

RED='\033[31m'; GRN='\033[32m'; CYN='\033[36m'; YLW='\033[33m'; NC='\033[0m'
ok()  { printf "${GRN}[OK]${NC} %s\n" "$1"; }
info(){ printf "${CYN}[INFO]${NC} %s\n" "$1"; }
warn(){ printf "${YLW}[警告]${NC} %s\n" "$1"; }
die() { printf "${RED}[错误]${NC} %s\n" "$1" >&2; exit 1; }

# ---------- 基础检查 ----------
[ "$(id -u)" = "0" ] || die "请用 root 运行"

detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS="alpine"
    elif command -v apt-get >/dev/null 2>&1; then
        OS="debian"
    else
        die "不支持的系统(仅支持 Alpine / Debian / Ubuntu)"
    fi
    # init 系统
    if [ -d /run/systemd/system ] || command -v systemctl >/dev/null 2>&1; then
        INIT="systemd"
    else
        INIT="openrc"
    fi
    info "系统: $OS / init: $INIT"
}

install_deps() {
    # 只装缺失的,已有就跳过(apk/apt 自动去重)
    info "检查并安装依赖 curl openssl tar..."
    if [ "$OS" = "alpine" ]; then
        apk update >/dev/null 2>&1 || true
        apk add --no-cache curl openssl tar >/dev/null
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null
        apt-get install -y -qq curl openssl tar >/dev/null
    fi
    command -v curl >/dev/null 2>&1 || die "curl 安装失败"
    command -v openssl >/dev/null 2>&1 || die "openssl 安装失败"
    ok "依赖就绪"
}

# ---------- 交互输入(管道执行时自动从 /dev/tty 读取,环境变量优先) ----------
tty_read() {
    _line=""
    if [ -t 0 ]; then
        IFS= read -r _line
    else
        IFS= read -r _line < /dev/tty 2>/dev/null || return 1
    fi
    printf '%s\n' "$_line"
}

env_val() { eval "printf '%s' \"\${$1:-}\""; }

ask_port() {  # $1=变量名 $2=提示  端口必填,无默认
    _v="$(env_val "$1")"
    if [ -z "$_v" ]; then
        printf '%s' "$2"
        _v="$(tty_read)" || die "当前为非交互环境,请用环境变量指定端口: $1=端口号 sh $0"
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

urlencode() { printf '%s' "$1" | od -An -tx1 | tr ' ' '\n' | grep . | sed 's/^/%/' | tr -d '\n'; }

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
gen_params() {
    _kp="$($BIN generate reality-keypair)"
    REALITY_PRIV="$(printf '%s' "$_kp" | awk '/PrivateKey/{print $2}')"
    REALITY_PUB="$(printf '%s' "$_kp" | awk '/PublicKey/{print $2}')"
    [ -n "$REALITY_PRIV" ] && [ -n "$REALITY_PUB" ] || die "reality 密钥对生成失败"
    UUID="$($BIN generate uuid)"
    SHORT_ID="$(openssl rand -hex 8)"
    HY2_PASS="$($BIN generate uuid)"
    cat > "$PARAMS" <<EOF
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
    ok "参数已持久化到 $PARAMS"
}

load_params() {
    [ -f "$PARAMS" ] || die "未找到 $PARAMS,请先安装"
    . "$PARAMS"
}

# ---------- hy2 自签证书(换证书前必须先停服务) ----------
gen_cert() {
    rc-service sb-onekey stop >/dev/null 2>&1 || systemctl stop sb-onekey 2>/dev/null || true
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$CONF_DIR/hy2.key" -out "$CONF_DIR/hy2.crt" \
        -days 3650 -nodes \
        -subj "/CN=$SNI" -addext "subjectAltName=DNS:$SNI" 2>/dev/null \
        || die "证书生成失败"
    ok "hy2 自签证书生成 ($SNI, 10年)"
}

# ---------- 配置生成(协议块模块化,新协议加一个 gen_inbound_xxx 再挂进 CONFIG_INBOUNDS) ----------
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
    {
        printf '{\n  "log": { "level": "warn", "timestamp": true },\n  "inbounds": [\n'
        gen_inbound_vless
        printf ',\n'
        gen_inbound_hy2
        printf '\n  ],\n  "outbounds": [ { "type": "direct", "tag": "direct" } ]\n}\n'
    } > "$CONF_DIR/config.json"
    $BIN check -c "$CONF_DIR/config.json" || die "配置校验失败"
    ok "配置校验通过"
}

# ---------- 服务管理 ----------
svc_install() {
    if [ "$INIT" = "openrc" ]; then
        cat > /etc/init.d/sb-onekey <<'EOF'
#!/sbin/openrc-run
name="sing-box"
description="sb-onekey node (vless-reality + hysteria2)"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background="yes"
pidfile="/run/sb-onekey.pid"
output_log="/var/log/sb-onekey.log"
error_log="/var/log/sb-onekey.log"
depend() { need net; }
EOF
        chmod +x /etc/init.d/sb-onekey
        rc-update add sb-onekey default 2>/dev/null || true
        rc-service sb-onekey restart
    else
        cat > /etc/systemd/system/sb-onekey.service <<'EOF'
[Unit]
After=network.target
[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable sb-onekey >/dev/null
        systemctl restart sb-onekey
    fi
    sleep 1
    svc_status || die "服务启动失败,查看日志: tail -30 /var/log/sing-box.log 或 journalctl -u sing-box"
}

svc_status() {
    if [ "$INIT" = "openrc" ]; then
        rc-service sb-onekey status >/dev/null 2>&1
    else
        systemctl is-active sb-onekey >/dev/null 2>&1
    fi
}

get_ip() {
    _ip="$(curl -fs4 --max-time 6 https://api.ipify.org 2>/dev/null)" \
        || _ip="$(curl -fs4 --max-time 6 http://ifconfig.me 2>/dev/null)" \
        || _ip="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | head -1 | cut -d/ -f1)"
    [ -n "$_ip" ] || die "公网 IP 获取失败"
    printf '%s\n' "$_ip"
}

show_links() {
    load_params
    _fp="$(openssl x509 -in "$CONF_DIR/hy2.crt" -outform der 2>/dev/null | openssl dgst -sha256 -hex | awk '{print $2}' | tr -d ':' | tr 'a-z' 'A-Z')"
    _ip="$(get_ip)"
    _n1="$(urlencode "🇭🇰 ${NODE_NAME} reality")"
    _n2="$(urlencode "🇭🇰 ${NODE_NAME} hy2")"
    echo ""
    printf "${CYN}========== 分享链接 ==========${NC}\n"
    echo "vless://${UUID}@${_ip}:${VLESS_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${REALITY_PUB}&sid=${SHORT_ID}&type=tcp&headerType=none#${_n1}"
    echo ""
    echo "hysteria2://${HY2_PASS}@${_ip}:${HY2_PORT}?sni=${SNI}&insecure=1&pinSHA256=${_fp}#${_n2}"
    printf "${CYN}==============================${NC}\n"
}

port_busy() {  # $1=端口
    (netstat -tuln 2>/dev/null || ss -tuln 2>/dev/null) | grep -q "[:.]$1[^0-9]"
}

detect_existing() {
    # fscarmen 版 sing-box:二进制在 /etc/sing-box/、配置在 /etc/sing-box/conf
    if [ -x /etc/sing-box/sing-box ] || [ -d /etc/sing-box/conf ]; then
        warn "检测到 fscarmen 版 sing-box,本脚本与其完全隔离(服务名 sb-onekey,目录 /etc/sb-onekey),可共存"
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files 2>/dev/null | grep -q "^sing-box"; then
        warn "检测到系统里已有 sing-box 服务,本脚本将以独立服务名 sb-onekey 运行,互不干扰"
    fi
}

do_install() {
    [ -f "$PARAMS" ] && die "已安装过(参数在 $PARAMS)。查看链接: sh $0 info ;重装请先: sh $0 uninstall"
    detect_os
    detect_existing
    install_deps
    install_singbox
    ask_port  VLESS_PORT "$(printf 'vless-reality 端口(必填,1-65535): ')"
    ask_port  HY2_PORT   "$(printf 'hysteria2 端口   (必填,1-65535): ')"
    [ "$VLESS_PORT" != "$HY2_PORT" ] || die "两个端口不能相同"
    port_busy "$VLESS_PORT" && die "TCP 端口 $VLESS_PORT 已被占用(可能是已有节点),换一个"
    port_busy "$HY2_PORT"   && die "UDP 端口 $HY2_PORT 已被占用(可能是已有节点),换一个"
    ask_text SNI      "$(printf 'SNI 域名(回车默认 www.icloud.com): ')" "www.icloud.com"
    ask_text NODE_NAME "$(printf '节点名称(回车默认用主机名: '$(hostname)') : ')" "$(hostname)"
    info "预检 SNI: https://$SNI"
    if ! curl -fsI --max-time 8 "https://$SNI" >/dev/null 2>&1; then
        warn "域名 $SNI 预检不通(reality 握手可能失败),建议 Ctrl+C 换一个"
    else
        ok "域名可达"
    fi
    gen_params
    gen_cert
    write_config
    svc_install
    ok "服务已启动并设为开机自启"
    echo ""
    warn "记得在云厂商安全组/防火墙放行: TCP $VLESS_PORT + UDP $HY2_PORT"
    show_links
}

do_info() {
    detect_os
    load_params
    svc_status && ok "服务运行中" || warn "服务未运行(启动: rc-service sing-box start / systemctl start sing-box)"
    show_links
}

do_uninstall() {
    detect_os
    if [ "$INIT" = "openrc" ]; then
        rc-service sb-onekey stop >/dev/null 2>&1 || true
        rc-update del sb-onekey default >/dev/null 2>&1 || true
        rm -f /etc/init.d/sb-onekey
    else
        systemctl stop sb-onekey 2>/dev/null || true
        systemctl disable sb-onekey >/dev/null 2>&1 || true
        rm -f /etc/systemd/system/sb-onekey.service
        systemctl daemon-reload
    fi
    rm -rf "$CONF_DIR" "$BIN" /var/log/sing-box.log
    ok "已彻底卸载(配置/二进制/服务/日志全清)"
}

case "${1:-install}" in
    install)   do_install ;;
    info)      do_info ;;
    uninstall) do_uninstall ;;
    *) die "用法: sh $0 [install|info|uninstall]" ;;
esac

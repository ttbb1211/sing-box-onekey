# sing-box-onekey

**Alpine 裸机一键搭建 sing-box 节点** — 支持 **vless-reality** / **hysteria2**，协议可自选，装完还能随时改。

> 专为 Alpine + OpenRC 设计，与 fscarmen 等第三方脚本**完全隔离共存**（独立服务名、独立目录、独立二进制）。

---

## 特性

| 特性 | 说明 |
|---|---|
| **协议自选** | 只装 vless、只装 hy2、或两个都装；装完还能随时启用/禁用 |
| **装后可编辑** | `edit` 改端口 / SNI / 节点名，重置 UUID / 密码 / reality 密钥，全程不用重装 |
| **状态一眼看清** | `info` 直接列出已装协议、端口、**实际监听状态**、服务状态、sing-box 版本 |
| **命令自装** | 装完把脚本自身装成 `sbctl`，以后直接 `sbctl info` / `sbctl edit`，不用再记脚本放哪 |
| **零依赖** | Alpine 裸机直接跑，脚本自动装 curl / openssl / tar |
| **端口必填** | 不设默认端口，避免和别人撞车 |
| **隔离共存** | 服务名 `sb-onekey`、目录 `/etc/sb-onekey`、二进制 `/usr/local/bin/sb-onekey`，不碰任何第三方安装 |
| **自动校验** | 生成配置后跑 `sing-box check`，校验不过直接退出，不会留半残配置 |

---

## 快速开始

### 方式 1：全交互（推荐首次使用）

```sh
wget -qO- https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh | sh
```

会依次问：**协议类型 → 端口 → SNI 域名 → 节点名称**。

### 方式 2：只装一种协议

```sh
# 只装 vless-reality
PROTOCOLS=vless VLESS_PORT=65005 sh sing-box-onekey.sh

# 只装 hysteria2
PROTOCOLS=hy2 HY2_PORT=65006 sh sing-box-onekey.sh
```

### 方式 3：全参数非交互（适合批量部署）

```sh
PROTOCOLS=vless,hy2 \
VLESS_PORT=65005 HY2_PORT=65006 \
SNI=www.icloud.com NODE_NAME=hk-node-1 \
sh sing-box-onekey.sh
```

---

## 子命令

安装时会把脚本自身装成命令 **`sbctl`**（`/usr/local/bin/sbctl`），所以装完之后：

```sh
sbctl info        # 查看已装协议 / 端口 / 监听状态 / 服务状态 / 分享链接
sbctl status      # 同 info
sbctl edit        # 交互式编辑(推荐)
sbctl edit SNI=www.nvidia.com VLESS_PORT=65010   # 非交互编辑
sbctl help        # 帮助
sbctl uninstall   # 彻底卸载(只清自己)
```

没装之前（或 `curl | sh` 中途失败）仍可用脚本原名：

```sh
sh sing-box-onekey.sh              # 安装(默认)
sh sing-box-onekey.sh info         # 查看
sh sing-box-onekey.sh edit         # 编辑
sh sing-box-onekey.sh uninstall    # 卸载
```

> ⚠️ `/usr/local/bin/sb-onekey` 是 **sing-box 二进制**，不是本脚本；脚本的入口是 `sbctl`。两者刻意分开，避免把二进制覆盖掉。

---

## 查看当前状态：`info`

```sh
sbctl info
```

```
========== 当前状态 ==========
  服务状态  : 运行中
  sing-box  : v1.14.3
  服务器 IP : 203.0.113.10
  节点名称  : hk-node-1
  SNI       : www.icloud.com
  配置文件  : /etc/sb-onekey/config.json

  已装协议  : vless-reality + hysteria2
    vless   : 端口 65005/TCP  监听中
    hy2     : 端口 65006/UDP  监听中
==============================

========== 分享链接 ==========
vless://<UUID>@203.0.113.10:65005?...#hk-node-1%20reality

hysteria2://<PASS>@203.0.113.10:65006?...#hk-node-1%20hy2
==============================
```

**监听状态**是直接读内核 `/proc/net/{tcp,tcp6,udp,udp6}` 得出的，不依赖 `ss`/`netstat`（Alpine 最小安装里可能都没有）。

- `监听中` = 端口真的在内核里等着连接
- `未监听` = 服务起来了但端口没开（配置/权限问题）
- `无法判断` = 读不到 `/proc/net/*`（极少见）

> 看到「服务运行中」但端口「未监听」，说明进程活着但 inbound 没绑上，先看 `/var/log/sb-onekey.log`。

---

## 协议选择

安装时会问：

```
请选择要安装的协议:
  1) 仅 vless-reality
  2) 仅 hysteria2
  3) 两个都装
请选择 [1/2/3, 回车默认 3]:
```

也可用环境变量 `PROTOCOLS` 直接指定：

| 写法 | 效果 |
|---|---|
| `PROTOCOLS=vless` | 仅 vless-reality |
| `PROTOCOLS=hy2` | 仅 hysteria2 |
| `PROTOCOLS=vless,hy2` | 两个都装 |

> 非交互环境（无 TTY）下不指定 `PROTOCOLS` 时，默认装两个，并打印提示。

---

## 装完再改：`edit`

```sh
sbctl edit
```

```
========== 当前配置 ==========
  协议      : vless-reality hysteria2
  节点名称  : hk-node-1
  SNI       : www.icloud.com
  vless 端口: 65005
  hy2 端口  : 65006
==============================

修改项:
  1) 节点名称
  2) SNI 域名(会重签 hy2 证书)
  3) vless 端口
  4) hy2 端口
  5) 重置 vless UUID
  6) 重置 hy2 密码
  7) 重置 reality 密钥对
  8) 启用/禁用协议
  9) 只看分享链接
  0) 退出
请选择:
```

每次修改都会：**写回参数 → 重建配置 → `sing-box check` → 重启服务 → 打印新链接**。

### 非交互编辑

```sh
sbctl edit NODE_NAME=hk-node-2
sbctl edit SNI=www.nvidia.com
sbctl edit VLESS_PORT=65010
sbctl edit ENABLE_HY2=1 HY2_PORT=65011   # 补装 hy2
sbctl edit ENABLE_VLESS=0                # 停用 vless,只留 hy2
```

支持的字段：

| 字段 | 说明 |
|---|---|
| `NODE_NAME` | 节点名称（分享链接里的备注） |
| `SNI` | 伪装域名，改后会自动重签 hy2 证书 |
| `VLESS_PORT` / `HY2_PORT` | 端口，会自动检查占用 |
| `UUID` / `HY2_PASS` / `SHORT_ID` | 手动指定凭据 |
| `ENABLE_VLESS` / `ENABLE_HY2` | `1` 启用 / `0` 停用 |

### 几个细节

- **改端口**：旧端口自动释放，新端口先查占用，被占就拒绝
- **改 SNI**：hy2 证书自动重签（`pinSHA256` 会变，**旧链接立即失效，要重新复制**）
- **启用 hy2**：如果证书不存在会自动生成
- **禁用某协议**：配置文件里对应 inbound 直接移除，端口释放

---

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PROTOCOLS` | 交互询问 | `vless` / `hy2` / `vless,hy2` |
| `VLESS_PORT` | 必填 | vless-reality 监听端口 |
| `HY2_PORT` | 必填 | hysteria2 监听端口 |
| `SNI` | `www.icloud.com` | 伪装域名（reality 握手目标 / hy2 证书 CN） |
| `NODE_NAME` | 主机名 | 节点名称 |
| `SB_VERSION` | 自动查最新 | 指定 sing-box 版本，如 `1.14.3` |

---

## 与第三方脚本共存

本脚本用**独立命名空间**，不会碰别人的东西：

| 资源 | 本脚本 | fscarmen 脚本 |
|---|---|---|
| 服务名 | `sb-onekey` | `sing-box` |
| 配置目录 | `/etc/sb-onekey` | `/etc/sing-box` |
| 二进制 | `/usr/local/bin/sb-onekey` | `/etc/sing-box/sing-box` |
| 日志 | `/var/log/sb-onekey.log` | 各自的 |
| 命令入口 | `/usr/local/bin/sbctl` | 各自的 |

所以同一台机器上可以两套并存，互不干扰。`uninstall` 也只删自己的。

---

## 常见问题

**Q：支持 Debian / Ubuntu 吗？**
A：不支持。本脚本专为 Alpine + OpenRC 设计（用 `rc-service` / `rc-update` / `apk`）。Debian 系请用 fscarmen 等脚本。

**Q：端口要填多少？**
A：**必须是你云厂商安全组已放行的端口**。脚本会检查本机端口占用，但检查不了云厂商安全组——放行是另一回事。

**Q：改了 SNI 之后节点连不上？**
A：hy2 的 `pinSHA256` 证书指纹变了。重新跑 `sbctl info` 复制新链接，旧链接里的指纹已失效。

**Q：提示 `sbctl: not found`？**
A：v1.3 及更早版本装的没有这个命令。**不用卸载重装**——随便跑一次 `sh sing-box-onekey.sh info`（或 `edit`），脚本会自动把自己补装成 `sbctl`。

**Q：`/usr/local/bin/sb-onekey` 和 `sbctl` 有什么区别？**
A：前者是 **sing-box 二进制**（服务实际跑的程序），后者是**本脚本**的入口。两者故意分开命名，避免脚本把二进制覆盖掉。

**Q：`info` 显示「服务运行中」但端口「未监听」？**
A：进程活着但 inbound 没绑上。先看 `tail -30 /var/log/sb-onekey.log`，常见原因是端口被别的进程抢了，或配置里 listen 地址不对。改端口用 `sbctl edit VLESS_PORT=xxxxx`。

**Q：能装两个实例吗？**
A：不能。本脚本是单实例设计（固定目录 + 固定服务名）。要多个节点请用不同机器，或用 fscarmen 那种多配置方案。

**Q：`edit` 之后要手动重启服务吗？**
A：不用，脚本会自动重启并校验状态。如果重启失败会报错并提示看 `/var/log/sb-onekey.log`。

---

## 输出示例

```
========== 分享链接 ==========
vless://<UUID>@<IP>:65005?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.icloud.com&fp=chrome&pbk=<PUBKEY>&sid=<SID>&type=tcp&headerType=none#<节点名>%20reality

hysteria2://<PASS>@<IP>:65006?sni=www.icloud.com&insecure=1&pinSHA256=<指纹>#<节点名>%20hy2
==============================
```

---

## 卸载

```sh
sbctl uninstall
```

会删除：服务、`/etc/sb-onekey`、`/usr/local/bin/sb-onekey`、`/usr/local/bin/sbctl`、日志。**不影响**其他 sing-box 安装。

---

## 免责声明

仅供个人学习与自建服务使用。请遵守所在地区的法律法规。

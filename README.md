# sing-box-onekey

**Alpine 裸机一键搭建 sing-box 节点** — 支持 **vless-reality** / **hysteria2**，协议可自选，装完敲 `sb` 出菜单随时改。

> 专为 Alpine + OpenRC 设计，与 fscarmen 等第三方脚本**完全隔离共存**（独立服务名、独立目录、独立二进制）。

---

## 特性

| 特性 | 说明 |
|---|---|
| **敲 `sb` 出菜单** | 装完直接敲 `sb`，数字选功能，不用记参数 |
| **协议自选** | 只装 vless、只装 hy2、或两个都装；装完还能随时启用/禁用 |
| **装后可编辑** | 改端口 / SNI / 节点名，重置 UUID / 密码 / reality 密钥，全程不用重装 |
| **状态一眼看清** | 菜单顶部直接显示系统、IP 归属地、服务状态、协议、端口**实时监听状态** |
| **一键 BBR** | 菜单第 6 项，写 `sysctl.d` 持久化，重启仍生效 |
| **依赖自动装** | 裸机 Alpine 直接跑，自动补 curl / openssl / tar，缺什么装什么 |
| **隔离共存** | 服务名 `sb-onekey`、目录 `/etc/sb-onekey`、二进制 `/usr/local/bin/sb-onekey`，不碰任何第三方安装 |
| **自动校验** | 生成配置后跑 `sing-box check`，校验不过直接退出，不会留半残配置 |

---

## 快速开始

```sh
curl -fsSL https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh | sh
```

首次运行会依次问：**协议类型 → 端口 → SNI 域名 → 节点名称**，装完打印分享链接。

装好之后，**直接敲 `sb`** 就能调出菜单。

> 用 `curl -fsSL` 而不是 `wget -qO-`：`wget` 失败时会把错误页灌给 `sh`，看到一堆 `syntax error`；`curl -f` 失败直接不输出。
>
> **裸机没装 curl 也能跑**：`wget -qO- <url> | sh`（wget 是 busybox 自带的），脚本会自己 `apk add curl`。

---

## 交互菜单

```sh
sb
```

```
================================================================
 sing-box-onekey  v1.7
 系统: Alpine 3.23.6 / 内核 6.18.57-0-virt / x86_64
 IP  : 203.0.113.10 (香港)
 服务: 运行中   协议: vless-reality + hysteria2
 端口: 65005/TCP(监听中)  65006/UDP(监听中)
================================================================

 1 . 查看节点信息 / 分享链接       (sb -n)
 2 . 修改节点配置                 (sb -e)
 3 . 增加 / 删除协议              (sb -p)
 4 . 重启服务                     (sb -s)
 5 . 升级 sing-box                (sb -v)
 6 . 开启 BBR 加速                (sb -b)
 7 . 删除节点(保留 sb 命令)       (sb -r)
 8 . 彻底卸载(连 sb 一起删)       (sb -u)
 0 . 退出

请选择:
```

没装节点时菜单只有三项：`1 安装 / 2 帮助 / 0 退出`。

---

## 快捷参数

不想进菜单就敲参数，效果一样：

| 命令 | 作用 |
|---|---|
| `sb` | 交互菜单 |
| `sb -n` | 查看节点信息（协议/端口/监听/服务/链接） |
| `sb -e` | 交互式修改配置 |
| `sb -e SNI=www.nvidia.com VLESS_PORT=65010` | 非交互修改 |
| `sb -p` | 增加 / 删除协议（仅 vless / 仅 hy2 / 两个都开） |
| `sb -s` | 重启服务 |
| `sb -v` | 检查并升级 sing-box |
| `sb -b` | 开启 BBR 加速 |
| `sb -i` | 安装节点（已装会拒绝，需先 `sb -r`） |
| `sb -r` | 删除节点，**保留 `sb` 命令**，以后可再 `sb -i` |
| `sb -u` | 彻底卸载（节点 + `sb` 命令一起删） |
| `sb -h` | 帮助 |

长参数同样可用：`--info` / `--edit` / `--protocol` / `--restart` / `--upgrade` / `--bbr` / `--install` / `--remove` / `--uninstall` / `--help`。

> `/usr/local/bin/sb-onekey` 是 **sing-box 二进制**，不是本脚本；脚本入口是 `/usr/local/bin/sb`（另建 `sbctl` 软链兼容旧名）。两者刻意分开，避免把二进制覆盖掉。

---

## 查看当前状态：`sb -n`

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

非交互示例：

```sh
PROTOCOLS=both VLESS_PORT=65005 HY2_PORT=65006 NODE_NAME=hk-node-1 sb -i
```

---

## 装完再改：`sb -e`

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
sb -e NODE_NAME=hk-node-2
sb -e SNI=www.nvidia.com
sb -e VLESS_PORT=65010
sb -e ENABLE_HY2=1 HY2_PORT=65011   # 补装 hy2
sb -e ENABLE_VLESS=0                # 停用 vless,只留 hy2
```

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

## 一键 BBR：`sb -b`

```sh
sb -b
```

```
[INFO] 当前: 拥塞控制=cubic  队列调度=fq
[OK] BBR 已开启: 拥塞控制=bbr  队列调度=fq
[INFO] 已写入 /etc/sysctl.d/99-bbr.conf,重启后自动生效
```

做的事：

1. 读当前拥塞控制算法，**已经是 `bbr` 就直接返回**，不重复折腾
2. `modprobe tcp_bbr`，并检查内核是否真的支持（不支持会报出可用算法列表）
3. 写 `/etc/sysctl.d/99-bbr.conf`：
   ```
   net.core.default_qdisc=fq
   net.ipv4.tcp_congestion_control=bbr
   ```
4. `sysctl -p` 立即生效
5. `rc-update add sysctl boot`，保证重启后自动加载

> 只改拥塞控制算法和队列调度，不动节点配置，随时可回退（`sysctl -w net.ipv4.tcp_congestion_control=cubic`）。

---

## 依赖说明

脚本只依赖三样，缺了会**自动 `apk add`**：

| 依赖 | 用途 | 说明 |
|---|---|---|
| `curl` | 下载 sing-box / 查 IP | 裸机没有时脚本自己装 |
| `openssl` | 生成 hy2 自签证书、算 pinSHA256 | |
| `tar` | 解压 sing-box 发布包 | |

已存在则跳过安装，不会每次 `apk update` 折腾。

`apk add` 失败时会打印排查指引（源 / 网络 / 磁盘），而不是丢一句「安装失败」：

```
[错误] 依赖安装失败。请依次检查:
  1) Alpine 源是否可用: cat /etc/apk/repositories
  2) 网络/DNS 是否通:   ping -c2 dl-cdn.alpinelinux.org
  3) 磁盘是否满:        df -h /
  手动补装: apk add curl openssl tar
```

> **必须能访问 Alpine 官方源**。如果机器源被换成了内网/失效镜像，`apk add` 会失败 —— 脚本不会自动改你的 `repositories`。

---

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PROTOCOLS` | 交互询问 | `vless` / `hy2` / `vless,hy2` / `both` |
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
| 命令入口 | `/usr/local/bin/sb` | `sb` |
| 日志 | `/var/log/sb-onekey.log` | 各自的 |

服务、目录、二进制完全隔离，`sb -u` 也只删自己的。

> ⚠️ **命令名 `sb` 与 fscarmen 脚本相同**。同机装两套会互相覆盖 `sb` —— 后装的占 `sb`。本脚本另建了 `sbctl` 软链，被覆盖时仍可用 `sbctl` 调本脚本。

---

## 删除节点 / 卸载

**只删节点，保留命令**（换端口重装前用这个）：

```sh
sb -r
```

删除：服务、`/etc/sb-onekey`、`/usr/local/bin/sb-onekey`、`/etc/init.d/sb-onekey`、日志。
保留：`/usr/local/bin/sb`，所以随时 `sb -i` 重装。

**彻底卸载**（连命令一起清掉）：

```sh
sb -u
```

删除：上面全部 + `/usr/local/bin/sb` + `sbctl` 软链。删完 `sb` 就 not found 了。

> 两者都**不影响** fscarmen 等其他 sing-box 安装。
>
> 如果 `sb` 已经没了又想装回来（不装节点），跑：
>
> ```sh
> curl -fsSL https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh | sh -s -- -h
> ```
>
> `-h` 只装命令、不装节点。

---

## 常见问题

**Q：支持 Debian / Ubuntu 吗？**
A：不支持。本脚本专为 Alpine + OpenRC 设计（用 `rc-service` / `rc-update` / `apk`）。Debian 系请用 fscarmen 等脚本。

**Q：端口要填多少？**
A：**必须是你云厂商安全组已放行的端口**。脚本会检查本机端口占用，但检查不了云厂商安全组——放行是另一回事。

**Q：改了 SNI 之后节点连不上？**
A：hy2 的 `pinSHA256` 证书指纹变了。重新跑 `sb -n` 复制新链接，旧链接里的指纹已失效。

**Q：提示 `sb: not found`？**
A：说明 `sb` 命令被删了（用了 `sb -u` 或从来没装）。**不用重装节点**——跑一次 `curl -fsSL ... | sh -s -- -h` 就能把命令装回来。

**Q：`/usr/local/bin/sb-onekey` 和 `sb` 有什么区别？**
A：前者是 **sing-box 二进制**（服务实际跑的程序），后者是**本脚本**的菜单入口。两者故意分开命名。

**Q：`sb -n` 显示「服务运行中」但端口「未监听」？**
A：进程活着但 inbound 没绑上。先看 `tail -30 /var/log/sb-onekey.log`，常见原因是端口被别的进程抢了，或配置里 listen 地址不对。改端口用 `sb -e`。

**Q：能装两个实例吗？**
A：不能。本脚本是单实例设计（固定目录 + 固定服务名）。要多个节点请用不同机器。

---

## 免责声明

仅供个人学习与自建服务使用。请遵守所在地区的法律法规。

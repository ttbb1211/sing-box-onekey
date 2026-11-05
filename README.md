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
| **删错不了** | 删节点 / 彻底卸载都先列清单再二次确认；只删一个协议走 `3`，不动另一个 |
| **依赖自动装** | 裸机 Alpine 直接跑，自动补 curl / openssl / tar / **gcompat**，缺什么装什么 |
| **隔离共存** | 服务名 `sb-onekey`、目录 `/etc/sb-onekey`、二进制 `/usr/local/bin/sb-onekey`，不碰任何第三方安装 |
| **自动校验** | 生成配置后跑 `sing-box check`，校验不过直接退出，不会留半残配置 |
| **凭据不外泄** | `config.json` / `params.env` / `hy2.key` 一律 600、目录 700，本机其它用户读不到私钥和密码 |
| **两种伪装模式** | `steal`（借用大厂，默认）/ `own`（自建伪装站点：自有域名 + LE 真证书 + 本机回落站），`sb domain` 一键切换 |
| **自带体检** | `sb doctor` 八项：服务、端口归属、handshake、证书签发者、DNS、回落站、错 SNI 拒绝 |
| **改前先备份** | 每次写配置自动备份，`sb rollback` 一条命令回到上一版，留最近 5 份 |
| **内置伪装站点模板** | `sb site --theme=tech\|poetry`，两套主题离线可用，覆盖前自动备份 |

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
 sing-box-onekey  v1.10
 系统: Alpine 3.23.6 / 内核 6.18.57-0-virt / x86_64
 IP  : 203.0.113.10 (香港)
 服务: 运行中   协议: vless-reality + hysteria2
 端口: 65005/TCP(监听中)  65006/UDP(监听中)
================================================================

 1 . 查看节点信息 / 分享链接       (sb -n)
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

请选择:
```

没装节点时菜单是五项：`1 安装 / 2 帮助 / 3 彻底卸载 / 4 检查脚本更新 / 0 退出`。

> **3 和 7 别混**：`3` 只动**协议**（删一个，另一个继续用），`7` 删**整个节点**（服务+配置+证书全清）。两个都有二次确认，看清再按 `y`。

---

## 快捷参数

不想进菜单就敲参数，效果一样：

| 命令 | 作用 |
|---|---|
| `sb` | 交互菜单 |
| `sb -n` | 查看节点信息（协议/端口/监听/服务/链接） |
| `sb -e` | 交互式修改配置 |
| `sb -e SNI=www.nvidia.com VLESS_PORT=65010` | 非交互修改 |
| `sb -p` | 启用 / 停用单个协议（菜单跟着当前状态变，启用时可改端口） |
| `sb -s` | 重启服务 |
| `sb -v` | 检查并升级 sing-box |
| `sb -b` | 开启 BBR 加速 |
| `sb -i` | 安装节点（已装会拒绝，需先 `sb -r`） |
| `sb -r` | 删除整个节点（**会二次确认**），**保留 `sb` 命令**，以后可再 `sb -i` |
| `sb -u` | 彻底卸载（节点 + `sb` 命令一起删，**会二次确认**） |
| `sb -U` | **检查脚本自身更新**（对比远端版本，有新版可一键升级，不动节点） |
| `sb domain` | **一键「自建伪装站点」**：签 LE 证书 + 装 nginx 回落站 + 改配置 + 出链接 |
| `sb domain --adopt` | 只把现有手工配置反填进 `params.env`，**不重建任何东西** |
| `sb doctor` | 体检 8 项：服务 / 端口归属 / handshake / 证书 / DNS / 回落站 / 错 SNI |
| `sb backup` / `sb rollback` | 备份 / 回滚配置（改动前自动备份，留最近 5 份） |
| `sb site --theme=poetry` | 铺内置伪装站点模板（`tech` 技术博客 / `poetry` 古诗词） |
| `sb reload-cert` | 给 acme.sh 当 `--reloadcmd`，别手工调 |
| `sb -h` | 帮助 |

长参数同样可用：`--info` / `--edit` / `--protocol` / `--restart` / `--upgrade` / `--bbr` / `--install` / `--remove` / `--uninstall` / `--update` / `--domain` / `--doctor` / `--backup` / `--rollback` / `--site` / `--reload-cert` / `--help`。

> `/usr/local/bin/sb-onekey` 是 **sing-box 二进制**，不是本脚本；脚本入口是 `/usr/local/bin/sb`（另建 `sbctl` 软链兼容旧名）。两者刻意分开，避免把二进制覆盖掉。

---

## 查看当前状态：`sb -n`

```
========== 当前状态 ==========
  服务状态  : 运行中
  sing-box  : v1.14.3
  服务器 IP : 203.0.113.10
  节点名称  : hk-node-1
  SNI       : www.broadcom.com
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

## 启用 / 停用协议：`sb -p`

```
当前状态:
  vless-reality : 启用中 (443/TCP)
  hysteria2     : 已停用

不会重置 UUID / 密码 / 证书,已有链接继续有效。

请选择:
  1) 停用 vless-reality  (释放 443/TCP)
  2) 启用 hysteria2      (端口 50010/UDP)
  0) 取消
  （要删整个节点:先按 0 退出本菜单,再在主菜单按 7）
请选择 [0-2]:
```

- 菜单**跟着当前状态变**：开着的显示「停用」，停着的显示「启用」，不会给你一个点了没用的选项
- 启用时会确认端口：`hy2 端口 [回车沿用 50010]:` —— 回车沿用原值，输入新值就换
- 关掉再开回来，凭据（UUID / 密码 / 证书）都还在，**链接不变**
- 至少保留一个协议，两个都停会被拦住

### `sb -p` 和 `sb -r` 到底差在哪

| | `sb -p` 启停协议 | `7` / `sb -r` 删节点 |
|---|---|---|
| 动什么 | 只动**单个协议**的启停 | 服务 + 配置 + 证书 + 二进制 + 日志，**全清** |
| 另一个协议 | 继续正常工作 | 一起没了 |
| 凭据（UUID/密码/证书） | **保留**，开回来链接不变 | **全部丢失**，重装后链接会变 |
| 服务状态 | 重启后继续运行 | 停止 + 取消开机自启 |
| `sb` 命令 | 保留 | 保留 |
| 适用场景 | 想临时只留一个、端口冲突要腾地方 | 彻底不要这个节点了、换机器、重装 |

> 一句话：**只想动一个协议 → `sb -p`；节点整个不要了 → `7`。** 两个操作都有二次确认，选错了按 `n` 就什么都没删。

---

## 装完再改：`sb -e`

```
========== 当前配置 ==========
  协议      : vless-reality hysteria2
  节点名称  : hk-node-1
  SNI       : www.broadcom.com
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
- **`8) 启用/禁用协议` 和主菜单 `3` / `sb -p` 是同一个函数**（`toggle_protocols`），效果完全一致，只是执行完回到 `sb -e` 的修改菜单。留这个入口是因为 `3) 4)` 改端口时会提示「请先用 8) 启用」，没有 8) 就是死胡同
- **每个选项选完立刻生效并重启**，没有「攒着最后一起提交」

### ⚠️ `own` 模式别用 `sb -e` 改 SNI

`own`（自建伪装站点）模式下，**改域名只能走 `sb domain`，不能用 `sb -e` 的 `2) SNI 域名`**。

原因是 `sb -e` 只改 `SNI`，不动 `CERT_DIR` 和 nginx 回落站的 `server_name`，结果是：

| 组件 | 改完的状态 |
|---|---|
| `config.json` 的 `server_name` | 新域名 |
| hy2 证书（`CERT_DIR/fullchain.pem`） | **还是旧域名的** → 客户端校验必失败 |
| nginx 回落站 `server_name` | **还是旧域名** → Reality 回落被 `ssl_reject_handshake` 拒掉 |

而 `sb doctor` 只查签发者是不是 ACME，**查不出证书 CN 与 SNI 不匹配**，会误报全绿。

`steal` 模式没有这个问题——那边本来就是自签证书，`apply_edit 1` 会重签。

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

1. 读当前拥塞控制算法和队列调度
2. **已经是 `bbr` + `fq` 也要检查持久化**（v1.11 起）：`99-bbr.conf`、`/etc/modules` 里的 `tcp_bbr`、`sysctl`/`modules` 服务开机启用，缺哪样补哪样
3. 没开则 `modprobe tcp_bbr`，并检查内核是否真的支持（不支持会报出可用算法列表）
4. 写 `/etc/sysctl.d/99-bbr.conf`：
   ```
   net.core.default_qdisc=fq
   net.ipv4.tcp_congestion_control=bbr
   ```
5. `sysctl -p` 立即生效
6. `rc-update add sysctl boot` / `rc-update add modules boot`

输出会区分两种情况：

```
[OK] BBR 已开启且持久化完整: 拥塞控制=bbr  队列调度=fq
[OK] BBR 已开启: 拥塞控制=bbr  队列调度=fq
[INFO] 已补齐持久化(99-bbr.conf + /etc/modules),重启后自动生效
```

> 只改拥塞控制算法和队列调度，不动节点配置，随时可回退（`sysctl -w net.ipv4.tcp_congestion_control=cubic`）。
> 幂等：重复执行第二次不会改动任何东西。

---

## 检查脚本更新：`sb -U`

不知道自己跑的是不是最新版？两种方式：

**① 敲 `sb` 进菜单就知道了** —— 远端有新版时，菜单上方会自己冒一行黄色提示：

```
[有新版本] 脚本 v1.11 → v1.12,敲菜单里的「检查脚本更新」或 sb -U 升级
```

（每次会话只查一次、超时 6 秒就静默放弃，不拖慢菜单、查不到就当没这回事）

**② 主动比对**：

```sh
sb -U
```

```
[INFO] 当前脚本版本: v1.10
[INFO] 正在检查远端最新版...
[INFO] 发现新版本: v1.10 → v1.12
升级到 v1.12? [y/N]: y
[OK] 脚本已升级: v1.10 → v1.12
[INFO] 重新敲 sb 生效(当前这次运行的还是旧版)
```

- 只换 `/usr/local/bin/sb` 这个命令文件，**不动节点、配置、证书、端口**
- 已是最新会直接说 `已是最新版 vX.Y,无需更新`
- 本地版本比远端还新（自己改过）→ 不覆盖，提示 `本地 vX 比远端 vY 还新`
- 下载内容必须**语法校验通过**才覆盖，防止把 404 页面写进 `sb`
- 菜单第 9 项就是它（没装节点时是第 4 项）

> 当前版本号在 `sb` 横幅第一行就能看到，`sb -h` 也会显示。

### 老版本（≤ v1.11）怎么升上来

v1.11 及更早的 `sb` **不认识 `-U`**，先手工换一次命令文件，之后就都能自举了：

```sh
curl -fsSL https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh -o /usr/local/bin/sb && chmod +x /usr/local/bin/sb
sb -U
```

这一步只换 `sb` 命令，节点照常跑、不掉线。

---

## 两种伪装模式：借用大厂 vs 自建伪装站点

v2.0 把「伪装」抽成一个维度，装完随时可切换。

| | `steal`（默认，借用大厂） | `own`（自建伪装站点） |
|---|---|---|
| SNI | 别人的站，如 `www.broadcom.com` | **自己的域名**，如 `node.example.com` |
| Reality 回落 | `$SNI:443`（别人的服务器） | `127.0.0.1:8001`（本机 nginx） |
| hy2 证书 | 自签 | **Let's Encrypt 真证书** |
| hy2 链接 | 必须带 `insecure=1&pinSHA256=...` | 只带 `sni` |
| 前置条件 | 无 | 域名 A 记录指到本机（**灰云**）、80 端口放行 |

**为什么值得换**：借用大厂的 SNI 全是被重点关照的对象，且「SNI 指向 A 站、证书却是 B 站」这件事本身就自相矛盾；自建伪装站点后，SNI、DNS、IP、证书四者完全一致，主动探测看到的就是一个正常的小站。

### 一键切换

```sh
sb domain
```

依次做五件事：**建 80 站（ACME 验证）→ 签证书 → 铺伪装站点 → 建 `127.0.0.1:8001` 回落站 → 改节点配置并重启**。

非交互用法：

```sh
DOMAIN=node.example.com sb domain
DOMAIN=node.example.com SITE_THEME=poetry sb domain   # 顺便铺古诗词主题
```

### 已经手工配好的机器：`--adopt`

```sh
sb domain --adopt
```

只做一件事：探测现有 `config.json` 的 `handshake`、`/etc/nginx/certs/<域名>/`、nginx 配置，把 `TLS_MODE=own` / `DOMAIN` / `CERT_DIR` 反填进 `params.env`。**不重建、不重启、不动证书**。

这一步很关键：不做的话，`params.env` 里没有 `TLS_MODE`，下次 `sb -e` 会按 `steal` 模式重写配置，把 `handshake` 改回 `$SNI:443` —— 服务当场起不来。

### 体检：`sb doctor`

```sh
sb doctor
```

```
========== 体检 (own 模式) ==========
  [OK] 服务         运行中
  [OK] vless 443      监听中 (9834:sb-onekey)
  [OK] hy2 50010      UDP 监听中
  [OK] handshake      "handshake": { "server": "127.0.0.1", "server_port": 8001 },
  [OK] hy2证书      node.example.com / E5
  [OK] DNS node.example.com 203.0.113.10
  [OK] 回落站      本机 node.example.com:8001 -> 200
  [OK] 错SNI         已拒绝(ssl_reject_handshake 生效)
===================================
[OK] 全部通过
```

端口那行会带上**归属进程**——这是为了防一个坑：nginx 占着 443 时，光看「监听中」会以为 Reality 活着，实际 sing-box 已经崩了。

### 伪装站点模板：`sb site`

```sh
sb site --theme=tech      # 技术博客（林深见鹿）
sb site --theme=poetry    # 古诗词（拾萤集）
sb site --theme=poetry --dir=/var/www/other
```

两套模板内嵌在脚本里（tar.gz + base64），**离线可用**。覆盖非空目录前会先备份成 `<目录>.bak-<时间戳>`。

> 多台机器建议用不同主题：两个 IP 挂一模一样的站，比对一下就知道是同一批。

### 三个必须知道的坑

1. **443 只能有一个主人**。`sb domain` 会在 `$NGX_DIR/sb-onekey.conf` 里写 nginx 配置，只监听 `80` 和 `127.0.0.1:8001`，**绝不 listen 443**。如果别的配置里有 `listen 443`，Reality 会 `bind: address already in use` 直接崩，`sb doctor` 会指出占用进程。
2. **`sb -e` 会重写配置**。v2.0 起 `apply_edit` 先 `backup` 再 `preflight`，失败可 `sb rollback`。但 `params.env` 里 `TLS_MODE` 不对时仍会按错模式写——所以手工改过配置的机器务必先 `sb domain --adopt`。
3. **证书续期钩子只调 `sb reload-cert`**。它做 `nginx -s reload` + 重启服务，证书路径怎么变都不用改钩子。手动改 `--reloadcmd` 成别的长命令，以后必然对不上。

---

## 依赖说明

脚本依赖四样，缺了会**自动 `apk add`**：

| 依赖 | 用途 | 说明 |
|---|---|---|
| `curl` | 下载 sing-box / 查 IP | 裸机没有时脚本自己装 |
| `openssl` | 生成 hy2 自签证书、算 pinSHA256 | |
| `tar` | 解压 sing-box 发布包 | |
| **`gcompat`** | **让 sing-box 官方二进制能在 musl 上跑** | **必须**，见下方说明 |

已存在则跳过安装，不会每次 `apk update` 折腾。

### 为什么需要 gcompat（v1.10 修复）

sing-box 官方发布的 `linux-amd64` / `linux-arm64` 二进制是 **glibc 动态链接**的，而 Alpine 用的是 musl。缺 `gcompat` 时执行它只会得到一句：

```
sh: /usr/local/bin/sb-onekey: not found
```

**文件明明在，却报 not found** —— 这是「动态链接器找不到」的典型症状，不是文件没装上，极容易误判。v1.9 及更早版本只装 curl/openssl/tar，在全新的 Alpine 上会卡在这里（表现为「reality 密钥对生成失败」）。

v1.10 起：装依赖时自动补 `gcompat`，并且**装完 sing-box 立刻试跑一次**，跑不起来会明确报错而不是假装成功。

手动补装：

```sh
apk add --no-cache gcompat
/usr/local/bin/sb-onekey version    # 能打印版本就说明好了
```

`apk add` 失败时会打印排查指引（源 / 网络 / 磁盘），而不是丢一句「安装失败」：

```
[错误] 依赖安装失败。请依次检查:
  1) Alpine 源是否可用: cat /etc/apk/repositories
  2) 网络/DNS 是否通:   ping -c2 dl-cdn.alpinelinux.org
  3) 磁盘是否满:        df -h /
  手动补装: apk add curl openssl tar gcompat
```

> **必须能访问 Alpine 官方源**。如果机器源被换成了内网/失效镜像，`apk add` 会失败 —— 脚本不会自动改你的 `repositories`。

---

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `PROTOCOLS` | 交互询问 | `vless` / `hy2` / `vless,hy2` / `both` |
| `VLESS_PORT` | 必填 | vless-reality 监听端口 |
| `HY2_PORT` | 必填 | hysteria2 监听端口 |
| `SNI` | `www.broadcom.com` | 伪装域名（reality 握手目标 / hy2 证书 CN） |
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

执行前会先把要删的东西列清楚，再问一次：

```
========== 删除节点确认 ==========
  节点名称  : hk-node-1
  已装协议  : vless-reality(65005/TCP) + hysteria2(65006/UDP)

  将会删除:
    · 服务 sb-onekey(停止 + 取消开机自启)
    · /etc/sb-onekey(配置 / 参数 / 证书)
    · /usr/local/bin/sb-onekey(sing-box 二进制)
    · /var/log/sb-onekey.log

  后果: UUID / 密码 / 证书全部丢失,重装后分享链接会变
  只想删一个协议? 取消后改用 3 / sb -p —— 另一个协议继续工作、凭据保留
==================================
确认删除节点? [y/N]:
```

删除：服务、`/etc/sb-onekey`、`/usr/local/bin/sb-onekey`、`/etc/init.d/sb-onekey`、日志。
保留：`/usr/local/bin/sb`，所以随时 `sb -i` 重装。

- 输 `y` 才删，直接回车或 `n` = 取消，**什么都没动**
- 非交互环境（脚本里调用、没有终端）会跳过确认直接执行，方便自动化

**彻底卸载**（连命令一起清掉）：

```sh
sb -u
```

同样先出确认页（删节点 + `sb`/`sbctl`），输 `y` 才执行。删完 `sb` 就 not found 了。

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

## 更新日志

### v2.2（2026-10-31）— 术语统一 + 菜单对齐

- 「偷大厂」→「**借用大厂**」、「偷自己」→「**自建伪装站点**」、「假站」→「**伪装站点**」
- 菜单 10 改「自建伪装站点」、菜单 13 改「伪装站点模板」
- 13 个菜单项对齐到同一**显示列**（旧版按字符数对齐，中文是双宽字符，实际终端里参差不齐）
- `sb -h` 帮助表、安装完成提示语、脚本注释同步

### v2.1（2026-10-31）— `sb -p` 菜单重做

只改一处交互，其余不动（保持简单）：

- 菜单**跟着状态变**：开着的协议显示「停用」，停着的显示「启用」。旧版是「1 删 hy2 / 2 删 vless / 3 两个都启用」，动作方向不一致，只有一个协议在跑时另一个选项还是无效动作
- 启用时确认端口：`hy2 端口 [回车沿用 50010]:` —— 回车沿用，输入新值就换（旧版端口有值就静默沿用，想换容易忘）
- 去掉误导的 `请选 7 / sb -r`（在本菜单里按 7 是无效选择），改成「先按 0 退出本菜单，再在主菜单按 7」
- 明确提示「不会重置 UUID / 密码 / 证书，已有链接继续有效」

### v2.0（2026-10-31）— 伪装模式 + 体检 + 备份

**新增「自建伪装站点」模式**（`TLS_MODE=own`），三处原来写死的地方改为按模式分支：

| 位置 | v1.x | v2.0 `own` |
|---|---|---|
| Reality `handshake` | 永远 `$SNI:443` | `127.0.0.1:8001`（本机 nginx 回落） |
| hy2 证书 | 永远自签 `hy2.crt` | `$CERT_DIR/fullchain.pem`（ACME） |
| hy2 链接 | 永远带 `insecure` + `pinSHA256` | 只带 `sni` |

**新命令**：`sb domain` / `sb domain --adopt` / `sb doctor` / `sb backup` / `sb rollback` / `sb site` / `sb reload-cert`。

**健壮性**：

- `apply_edit` 先备份再落盘，`preflight` 拦截 443 被占用、A 记录指错、磁盘不足
- 端口状态显示**归属进程**（`/proc` 反查），不再出现「nginx 占着 443 却显示 vless 监听中」
- `sb -u` 卸载后提示残留的 nginx 回落站配置，不擅自删

**踩过的坑（都写进注释了）**：nginx 占 443 导致 sing-box `bind: address already in use`；`sb -e` 重写 `handshake` 指向自己；`sb -e` 后 hy2 证书退回自签；Alpine 上 sing-box 的 `comm` 被截成 `ld-musl-x86_64.`，按进程名认不出是谁。

### v1.14（2026-10-22）— 修 `sb -U` 拉不到新版

v1.12 给拉取地址加的 `?t=时间戳`（本意是绕开 `raw.githubusercontent.com` 的 CDN 缓存）**方向反了**：

实测同一时刻、同一台机器，

- 不带 query → 拿到 v1.13（新）
- 带 `?t=时间戳` → 拿到 v1.12（旧）

原因是 raw 的 CDN 对带随机 query 的 URL 走的是另一条缓存路径，边缘节点上的旧对象反而更容易命中。结果是 `sb -U` 和菜单里的版本提示**长期显示「已是最新版」**，怎么点都升不上去。

**修法**：两个地址都拉，按 `SCRIPT_VER` 取版本号更高的那份 —— 任一通道拿到新版都能升上去。

> ⚠️ 已经卡在 v1.12 的机器，`sb -U` 本身也是坏的，需要先手工换一次：
>
> ```sh
> curl -fsSL https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh -o /usr/local/bin/sb && chmod +x /usr/local/bin/sb
> ```

### v1.13（2026-10-22）— 安全与健壮性

一轮代码审查后的修复，**不改变任何使用方式**，老机器 `sb -U` 直接升即可。

| 改动 | 说明 |
|---|---|
| **凭据文件收紧到 600** | `config.json` 内含 reality 私钥 / hy2 密码 / UUID，原来受 umask 影响落成 **644（本机任何用户可读）**。现 `config.json` / `hy2.key` / `params.env` 一律 600，`/etc/sb-onekey` 目录 700 |
| **临时文件改用 `mktemp`** | 原来三处用 `/tmp/.xxx.$$`，PID 可预测，理论上可被本地低权限用户预建符号链接劫持（root 的 `cp` / `curl -o` 会写到链接目标）。现全部 `mktemp`（`O_EXCL` 创建，天然免疫） |
| **SNI 改成白名单校验** | 原来只拒空格。`/` `"` `\` `,` `=` 会破坏证书 DN 或 JSON，但报错只显示「配置校验失败」，很难定位。现只允许**字母 / 数字 / 点 / 连字符**，安装和编辑两条路径都拦 |
| **失败不再留半残状态** | `params.env` 改为**配置校验通过之后才落盘**。以前 `sing-box check` 失败时参数已经写进去了，下次 `sb -i` 会判定「已安装」拒绝重装，被迫先 `sb -r` 清干净 |
| **解压失败不再误报缺 gcompat** | `tar` / `install` 补了显式错误判断。包损坏或磁盘满时直接报「解压失败」，不会再一路走到「二进制无法执行 → 尝试补装 gcompat」那条误导分支 |
| **参数文件损坏也能删节点** | `sb -r` 读 `params.env` 前先关掉 `set -u`。文件里有未定义变量时不再直接退出（原来注释承诺了「参数坏了也能删」，实际做不到） |
| **启动判定改成轮询** | 固定 `sleep 1` 改成最多等 5 秒。低配机器加载 REALITY 密钥 + 绑端口偶尔超过 1 秒，以前会误报「启动失败」 |
| **端口占用检查换实现** | 改用脚本内已有的纯 `/proc` 探测（`port_listen`），少一层对 `netstat` 的依赖，也和菜单里显示的判定口径统一 |

### v1.12（2026-10-21）— 脚本自身可升级

- 新增 `sb -U`：检查并升级脚本自身（不动节点 / 配置 / 证书）
- 进菜单静默比对版本，有新版在菜单上方打黄色提示
- 拉远端脚本加 `?t=时间戳`，绕开 `raw.githubusercontent.com` 的 CDN 缓存

### v1.11（2026-10-21）

- BBR 已开启时也补齐持久化（`99-bbr.conf` + `/etc/modules`），不再只是「检测到已开就跳过」

### v1.10（2026-10-20）

- 自动补装 `gcompat`：sing-box 官方二进制是 glibc 动态链接，Alpine（musl）缺它时报的是 `not found` 而不是 `cannot execute`，极易误判成「文件没装上」

---

## 免责声明

仅供个人学习与自建服务使用。请遵守所在地区的法律法规。

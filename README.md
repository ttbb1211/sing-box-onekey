# sing-box-onekey

**Alpine 专用**裸机一键搭建 sing-box 节点（vless-reality + hysteria2 双协议）。自动安装缺失依赖，全新机器一条命令跑通。

> 设计原则：不走第三方安装脚本，全部手工部署逻辑固化；**与 fscarmen/sing-box 等第三方安装完全隔离共存**（独立服务名/目录/二进制），装、卸都不动第三方的东西。

## 一键安装

```bash
wget -qO- https://raw.githubusercontent.com/ttbb1211/sing-box-onekey/main/sing-box-onekey.sh | sh
```

安装过程会依次要求输入（管道执行时自动从终端读取）：

| 项 | 说明 | 默认 |
|---|---|---|
| vless-reality 端口 | 1-65535，**必填** | 无（必须输入） |
| hysteria2 端口 | 1-65535，**必填**，不能与上面相同，被占用会拒绝 | 无（必须输入） |
| SNI 域名 | reality 握手目标，自动预检可达性 | `www.icloud.com` |
| 节点名称 | 出现在分享链接里，**不自动加国旗** | 主机名 |

装完直接打印两条分享链接（vless:// 和 hysteria2://，链接自带证书指纹 pinSHA256），导入 v2rayN / v2rayNG / sing-box 客户端即可。

## 免交互（自动化场景）

任何一项都可用环境变量跳过交互：

```bash
VLESS_PORT=6501 HY2_PORT=6502 SNI=www.nvidia.com NODE_NAME=圣何塞-1 sh sing-box-onekey.sh
```

> 端口没有默认值：非交互环境又没给环境变量时会直接报错退出，避免装出一台端口未知的机器。

## 子命令

```bash
sh sing-box-onekey.sh install    # 安装（默认，可省略）
sh sing-box-onekey.sh info       # 查看参数与分享链接（重装系统后找回链接也用它）
sh sing-box-onekey.sh uninstall  # 彻底卸载（只清 sb-onekey 自己的）
```

## 与 fscarmen 等第三方脚本共存

| | 本脚本 | fscarmen/sing-box |
|---|---|---|
| 服务名 | `sb-onekey` | `sing-box` |
| 目录 | `/etc/sb-onekey` | `/etc/sing-box` |
| 二进制 | `/usr/local/bin/sb-onekey` | `/etc/sing-box/sing-box` |

互不覆盖、互不干扰，可同机共存。唯一要避开的是**端口冲突**——安装时会预检端口占用，被占用的端口直接拒绝。

## 自定义 sing-box 版本

默认安装 GitHub 最新稳定版（API 不可用时兜底 v1.14.3）：

```bash
SB_VERSION=1.12.14 sh sing-box-onekey.sh
```

## 安装了什么

| 路径 | 内容 |
|---|---|
| `/usr/local/bin/sb-onekey` | sing-box 二进制副本（GitHub Releases 原版） |
| `/etc/sb-onekey/config.json` | 配置（vless-reality + hysteria2 双入站） |
| `/etc/sb-onekey/params.env` | 全部生成参数（权限 600，`info` 命令读它） |
| `/etc/sb-onekey/hy2.crt` `.key` | hysteria2 自签证书（10 年，CN=SNI 域名） |
| `/etc/init.d/sb-onekey` | OpenRC 服务，开机自启 |

## 注意事项

- **仅支持 Alpine**（OpenRC）；Debian/Ubuntu 机器请勿使用
- **端口放行**：安装完记得在云厂商安全组放行 `TCP <vless端口>` + `UDP <hy2端口>`，脚本不管这一步
- **hy2 证书**：自签，链接已带 `pinSHA256`；换证书后链接里的指纹要同步更新（`info` 会输出当前指纹对应的最新链接）
- **reality 握手目标**：选大厂稳定域名（icloud / nvidia 等），脚本会预检，预检不通建议换
- hysteria2 未声明上下行限速，走 BBR 拥塞控制按线路自适应

## 扩展新协议

`config.json` 的生成按协议块函数拆分（`gen_inbound_vless` / `gen_inbound_hy2`），后续加新协议只需新增一个 `gen_inbound_xxx` 函数并在 `write_config` 里挂载，欢迎 PR。

## 卸载

```bash
sh sing-box-onekey.sh uninstall
```

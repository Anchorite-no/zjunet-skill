# 从仓库链接复刻到新机器

## 1. 先做只读盘点

运行 `scripts/Get-NetworkInventory.ps1` 和 `bootstrap.ps1 plan`。确认目标机器已有的 FlClash、Clash Verge Rev、Mihomo、ZJU Connect、Tailscale，以及 7890/1053/1054/11080 等本地监听器。

如果有可用代理客户端和订阅，直接复用。不要读取、导出或重新编码订阅。

## 2. 本地补充信息

复制 `config/topology.example.json` 到 `local/topology.local.json`。只在本机填写：

- 物理 DNS 与精确 LAN CIDR；
- 校园 DNS、校园 CIDR、校园后缀；
- ZJU 用户名和一个用于验证的校园页面；
- 可选的 Tailnet CIDR 与 MagicDNS。

ZJU 密码不要写入 JSON。应通过官方客户端、本机隐藏输入、Windows Credential Manager 或当前用户 DPAPI 保存。

## 3. 软件策略

优先使用已安装的软件：

- [FlClash](https://github.com/chen08209/FlClash)
- [Clash Verge Rev](https://github.com/clash-verge-rev/clash-verge-rev)
- [ZJU Connect](https://github.com/Mythologyli/zju-connect)
- [Tailscale](https://tailscale.com/download/windows)

缺失时只从官方发布页安装。安装计划必须写明版本和校验方式。发现已有 Core 时不得用安装脚本覆盖它；如确需更换，必须让用户针对这次操作明确确认。

## 4. 构建本机文件

运行：

```powershell
pwsh -NoProfile -File .\bootstrap.ps1 build -ConfigPath .\local\topology.local.json
```

检查 `out/replication-plan.json`，再把 `out/managed-overlay.js` 挂到所选客户端：

- FlClash 使用当前 profile 的脚本覆写机制；
- Clash Verge Rev 使用全局扩展脚本；
- 其他 Mihomo 前端只有在确认支持同一种 JavaScript `main(config)` 接口时才可使用，不能把它当作普通 Mihomo Core 原生能力。

## 5. 收敛的应用设置

目标值：

| 设置 | 目标 |
|---|---|
| mixed-port | 本地配置，默认 7890 |
| TUN | 开启，stack=mixed |
| auto-route | true |
| strict-route | false |
| dns-hijack | UDP/TCP 53 |
| IPv6 | 默认关闭，除非目标机器明确需要 |
| system proxy | 关闭，避免与 TUN 重叠 |
| append system DNS | 关闭 |
| auto start | 开启客户端自身启动项 |
| ZJU Connect TUN/add-route/dns-hijack | 全部关闭 |

第一次安装或更换 TUN 驱动属于单独的高风险操作，不能由普通 `-Yes` 或后台修复隐式批准。

## 6. 条件 DNS

`out/conditional-dns.json` 描述了接口合同。实现必须同时支持 UDP 和原始 TCP DNS，并遵守：

1. 并发询问至少两个公共 TCP DNS。
2. 任一公共上游给出正答案就立即返回。
3. 只有所有公共上游都给出确定的 NXDOMAIN/NODATA，才通过校园 SOCKS 查询校园 DNS。
4. timeout、transport error、SERVFAIL 和 REFUSED 不得触发校园 fallback。
5. 响应必须匹配 transaction ID 和完整 question。

## 7. 验证

至少分别验证：

- VPN bootstrap 经物理 DNS；
- mixed proxy 与代理 DNS；
- 条件 DNS 的 UDP/TCP；
- 校园 SOCKS 握手；
- 校园 DNS；
- 校园 HTTP 分别经 SOCKS、mixed 和正常 TUN；
- LAN/Tailnet 绕过；
- 公网页面的 HTML、API、静态文件、图片和媒体资源。

最后运行 `bootstrap.ps1 smoke` 检查本地监听器，再完成上面的端到端矩阵。`smoke` 或 `doctor` 的本地端口通过不能解释成完整成功。

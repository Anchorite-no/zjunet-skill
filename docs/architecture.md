# 网络与 DNS 架构

## 两阶段决策

DNS 负责确定目标属于哪个命名空间；得到地址以后，Mihomo 规则再决定业务流量走哪条链路。不要把校园 DNS、公共 DNS 和代理 DoH 混成无序 fallback 池。

```mermaid
flowchart TD
    Q["域名查询"] --> CLASSIFY{"已知命名空间？"}
    CLASSIFY -->|"VPN 启动域名 / LAN"| PHY["物理 DNS，DIRECT"]
    CLASSIFY -->|"Tailnet"| MAGIC["MagicDNS，DIRECT"]
    CLASSIFY -->|"已知校园后缀"| CAMPUS["校园 DNS，经 CAMPUS SOCKS"]
    CLASSIFY -->|"代理策略域名"| DOH["现有代理策略下的 DoH"]
    CLASSIFY -->|"普通或未知"| CONDITIONAL["条件 DNS"]
    CONDITIONAL --> PUBLIC["并发公共 TCP DNS，经 mixed-port"]
    PUBLIC --> DECIDE{"公共结果"}
    DECIDE -->|"任一正答案"| IP["返回地址"]
    DECIDE -->|"全部 NXDOMAIN / NODATA"| CAMPUS
    DECIDE -->|"超时 / SERVFAIL / REFUSED"| FAIL["安全失败，不泄漏给校园 DNS"]
    PHY --> IP
    MAGIC --> IP
    CAMPUS --> IP
    DOH --> IP
```

## 业务流量

```mermaid
flowchart LR
    IP["解析后的目标"] --> RULES{"Mihomo 规则"}
    RULES -->|"物理 LAN / VPN bootstrap / Tailnet"| DIRECT
    RULES -->|"校园后缀或校园 CIDR"| SOCKS["ZJU Connect SOCKS"]
    RULES -->|"现有订阅规则"| PROXY["本地 mixed-port 对应的代理出口"]
    RULES -->|"普通直连"| DIRECT["物理互联网"]
```

## 防回环边界

- `zju-connect.exe` 和条件 DNS 进程本身必须 DIRECT。
- VPN 服务端的启动域名必须使用物理 DNS，在 VPN 建立前可解析。
- 物理 LAN 和 Tailnet 使用更具体的 DIRECT/route-exclude 规则。
- ZJU Connect 只提供 SOCKS，关闭它自己的 TUN、add-route 和 dns-hijack。
- 条件 DNS 到公共解析器的连接进入本机 mixed-port；到校园解析器的连接进入校园 SOCKS。

## 独立故障域

```mermaid
flowchart LR
    UNDERLAY["物理网络"] --> CORE["代理 Core + TUN"]
    UNDERLAY --> ZJU["ZJU Connect"]
    CORE --> COND["条件 DNS"]
    ZJU --> COND
    CORE --> PUBLIC["公网"]
    ZJU --> INTERNAL["校园服务"]
    SUP["doctor / supervisor"] -. "分别恢复" .-> CORE
    SUP -. "分别恢复" .-> ZJU
    SUP -. "分别恢复" .-> COND
```

校园客户端崩溃时只恢复校园客户端；条件 DNS 崩溃时只恢复条件 DNS。不要因为一个校园探针失败就替换或重启代理 Core。

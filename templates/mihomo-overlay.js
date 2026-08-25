// Generated values are injected as JSON by bootstrap.ps1.
const T = __TOPOLOGY_JSON__;

function withoutName(items, name) {
  return (Array.isArray(items) ? items : []).filter((item) => !item || item.name !== name);
}

function main(config) {
  config = config || {};
  config["mixed-port"] = T.proxy.mixed_port;
  config["allow-lan"] = T.proxy.allow_lan;
  config["bind-address"] = T.proxy.allow_lan ? "*" : "127.0.0.1";
  config.ipv6 = false;
  config["find-process-mode"] = "always";

  config.proxies = withoutName(config.proxies, T.campus.proxy_name);
  config.proxies.push({
    name: T.campus.proxy_name,
    type: "socks5",
    server: "127.0.0.1",
    port: T.campus.socks_port,
    udp: true
  });

  config["proxy-groups"] = withoutName(config["proxy-groups"], T.campus.group_name);
  config["proxy-groups"].push({
    name: T.campus.group_name,
    type: "select",
    proxies: [T.campus.proxy_name]
  });

  config.tun = Object.assign({}, config.tun || {}, {
    enable: true,
    stack: "mixed",
    "auto-route": true,
    "strict-route": false,
    "dns-hijack": ["any:53", "tcp://any:53"],
    "route-exclude-address": T.routing.exclude_cidrs.slice()
  });

  const conditional = "tcp://127.0.0.1:" + T.conditional_dns.listen_port + "#DIRECT";
  const physical = T.conditional_dns.physical_dns.map((ip) => "udp://" + ip + ":53#DIRECT");
  const campus = T.conditional_dns.campus_servers.map((server) => "tcp://" + server + "#" + T.campus.group_name);
  const policy = { "+.lan": physical, "+.arpa": physical };
  for (const name of T.conditional_dns.vpn_bootstrap_names) policy[name] = physical;
  for (const suffix of T.conditional_dns.campus_suffixes) policy[suffix] = campus;
  if (T.routing.tailnet_dns) policy["+.ts.net"] = ["udp://" + T.routing.tailnet_dns + "#DIRECT"];

  config.dns = Object.assign({}, config.dns || {}, {
    enable: true,
    listen: "127.0.0.1:" + T.proxy.dns_port,
    ipv6: false,
    "respect-rules": true,
    "enhanced-mode": "redir-host",
    nameserver: [conditional],
    "direct-nameserver": [conditional],
    fallback: [],
    "nameserver-policy": policy
  });

  const rules = [];
  rules.push("PROCESS-NAME,zju-connect.exe,DIRECT");
  rules.push("PROCESS-NAME,conditional-dns.exe,DIRECT");
  for (const cidr of T.routing.exclude_cidrs) rules.push("IP-CIDR," + cidr + ",DIRECT,no-resolve");
  for (const suffix of T.conditional_dns.campus_suffixes) rules.push("DOMAIN-SUFFIX," + suffix.replace(/^\+\./, "") + "," + T.campus.group_name);
  for (const cidr of T.routing.campus_cidrs) rules.push("IP-CIDR," + cidr + "," + T.campus.group_name + ",no-resolve");
  config.rules = rules.concat(Array.isArray(config.rules) ? config.rules : []);
  return config;
}

#!/bin/bash
set -e

# 生成随机串
gen_rand() {
  tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "${1:-32}"
}

# 证书
if [ -f /opt/certs/server-cert.pem ]; then
  echo "[INFO] Certificates already exist. Skipping generation."
else
  CA_CN=${CA_CN:-$(gen_rand 32)}
  CA_ORG=${CA_ORG:-$(gen_rand 32)}
  SERV_DOMAIN=${SERV_DOMAIN:-$(gen_rand 12)}
  SERV_ORG=${SERV_ORG:-$(gen_rand 32)}
  USER_ID=${USER_ID:-$(gen_rand 10)}
  CERT_P12_PASS=${CERT_P12_PASS:-616}

  echo "CA_CN=${CA_CN}"
  echo "CA_ORG=${CA_ORG}"
  echo "SERV_DOMAIN=${SERV_DOMAIN}"
  echo "SERV_ORG=${SERV_ORG}"
  echo "USER_ID=${USER_ID}"
  echo "CERT_P12_PASS=${CERT_P12_PASS}"

  # 更安全的分隔符，避免变量包含 '/'
  sed -i "s|Your desired authority name|${CA_CN}|g"      /opt/certs/ca-tmp
  sed -i "s|Your desired orgnization name|${CA_ORG}|g"   /opt/certs/ca-tmp
  sed -i "s|yourdomainname|${SERV_DOMAIN}|g"             /opt/certs/serv-tmp
  sed -i "s|Your desired orgnization name|${SERV_ORG}|g" /opt/certs/serv-tmp
  sed -i "s|user|${USER_ID}|g"                           /opt/certs/user-tmp

  certtool --generate-privkey --outfile /opt/certs/ca-key.pem >/dev/null 2>&1
  certtool --generate-self-signed \
    --load-privkey /opt/certs/ca-key.pem \
    --template /opt/certs/ca-tmp \
    --outfile /opt/certs/ca-cert.pem >/dev/null 2>&1

  certtool --generate-privkey --outfile /opt/certs/server-key.pem >/dev/null 2>&1
  certtool --generate-certificate \
    --load-privkey /opt/certs/server-key.pem \
    --load-ca-certificate /opt/certs/ca-cert.pem \
    --load-ca-privkey /opt/certs/ca-key.pem \
    --template /opt/certs/serv-tmp \
    --outfile /opt/certs/server-cert.pem >/dev/null 2>&1

  certtool --generate-privkey --outfile /opt/certs/user-key.pem >/dev/null 2>&1
  certtool --generate-certificate \
    --load-privkey /opt/certs/user-key.pem \
    --load-ca-certificate /opt/certs/ca-cert.pem \
    --load-ca-privkey /opt/certs/ca-key.pem \
    --template /opt/certs/user-tmp \
    --outfile /opt/certs/user-cert.pem >/dev/null 2>&1

  openssl pkcs12 -export \
    -inkey /opt/certs/user-key.pem \
    -in /opt/certs/user-cert.pem \
    -certfile /opt/certs/ca-cert.pem \
    -out /opt/certs/user.p12 \
    -passout pass:${CERT_P12_PASS} >/dev/null 2>&1
fi

# dnsmasq（可选）
if command -v dnsmasq >/dev/null 2>&1; then
  echo "[INFO] dnsmasq found. Starting dnsmasq..."
  dnsmasq -C /usr/local/etc/dnsmasq.conf
else
  echo "[INFO] dnsmasq not found. Skipping dnsmasq start."
fi

# IPv4 转发
echo "[INFO] Enabling IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
echo "[INFO] net.ipv4.ip_forward=$(sysctl -n net.ipv4.ip_forward)"

# /dev/net/tun
if [ ! -e /dev/net/tun ]; then
  echo "[INFO] Creating /dev/net/tun..."
  mkdir -p /dev/net
  mknod /dev/net/tun c 10 200
  chmod 600 /dev/net/tun
fi

# 从 ocserv.conf 提取 VPN_CIDR：兼容三种写法
extract_vpn_cidr() {
  awk '
    BEGIN{ip=""; mask=""; prefix=""}
    $1=="ipv4-network"{ # 形如 ipv4-network = 10.7.7.0 或 10.7.7.0/24
      split($0,a,"=");
      gsub(/ /,"",a[2])
      if (index(a[2],"/")>0){ print a[2]; exit } else { ip=a[2] }
    }
    $1=="ipv4-netmask"{
      split($0,a,"="); gsub(/ /,"",a[2]); mask=a[2]
    }
    $1=="ipv4-prefix"{
      split($0,a,"="); gsub(/ /,"",a[2]); prefix=a[2]
    }
    END{
      if(ip!="" && prefix!=""){ print ip"/"prefix; exit }
      if(ip!="" && mask!=""){
        split(mask,o,"."); c=0;
        for(i=1;i<=4;i++){ n=o[i]+0; while(n){ c+=n%2; n=int(n/2) } }
        print ip"/"c; exit
      }
    }' /etc/ocserv/ocserv.conf 2>/dev/null
}

VPN_CIDR="${VPN_CIDR:-$(extract_vpn_cidr || true)}"
if [ -n "${VPN_CIDR:-}" ]; then
  echo "[INFO] VPN_CIDR detected: ${VPN_CIDR}"
else
  echo "[WARN] Could not detect VPN_CIDR from ocserv.conf; you may export VPN_CIDR env."
fi

#清空 iptables 规则
echo "[INFO] Clearing all iptables rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# 路由模式：由 ROUTE_CIDRS 是否为空决定
ROUTE_CIDRS="${ROUTE_CIDRS:-}"

# 先做路由模式的 NAT 豁免（RETURN 插到最前），再兜底 MASQUERADE
if [ -n "${ROUTE_CIDRS}" ] && [ -n "${VPN_CIDR:-}" ]; then
  echo "[MODE] Route mode: add NAT exemption (RETURN) for ${VPN_CIDR} -> ${ROUTE_CIDRS}"
  for ROUTE_CIDR in ${ROUTE_CIDRS}; do
    if iptables -t nat -C POSTROUTING -s "${VPN_CIDR}" -d "${ROUTE_CIDR}" -j RETURN 2>/dev/null; then
      echo "[INFO] RETURN exists: ${VPN_CIDR} -> ${ROUTE_CIDR}"
    else
      iptables -t nat -I POSTROUTING 1 -s "${VPN_CIDR}" -d "${ROUTE_CIDR}" -j RETURN || \
        echo "[WARN] Failed to insert RETURN for ${ROUTE_CIDR}"
    fi
  done
else
  echo "[MODE] Non-route mode: skip NAT exemption"
fi

# 兜底 MASQUERADE（若路由模式生效，RETURN 在前会挡住它）
if [ -n "${VPN_CIDR:-}" ]; then
  iptables -t nat -C POSTROUTING -s "${VPN_CIDR}" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "${VPN_CIDR}" -j MASQUERADE
else
  iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -j MASQUERADE
fi

# 放通 FORWARD（幂等）+ MSS 钳制（避免大包碎片/卡顿）
if [ -n "${VPN_CIDR:-}" ] && [ -n "${ROUTE_CIDRS:-}" ]; then
  for ROUTE_CIDR in ${ROUTE_CIDRS}; do
    iptables -C FORWARD -s "${VPN_CIDR}" -d "${ROUTE_CIDR}" -j ACCEPT 2>/dev/null || \
      iptables -I FORWARD 1 -s "${VPN_CIDR}" -d "${ROUTE_CIDR}" -j ACCEPT
    iptables -C FORWARD -s "${ROUTE_CIDR}" -d "${VPN_CIDR}" -j ACCEPT 2>/dev/null || \
      iptables -I FORWARD 1 -s "${ROUTE_CIDR}" -d "${VPN_CIDR}" -j ACCEPT
  done
fi
iptables -t mangle -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || \
  iptables -t mangle -I FORWARD 1 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

# LDAP 软链/服务
if [ -f /etc/ocserv/ldap.conf ]; then
  echo "[INFO] ldap config(/etc/ocserv/ldap.conf) exist. link to /etc."
  ln -sf /etc/ocserv/ldap.conf /etc/ldap.conf
fi
if [ -f /etc/ocserv/nslcd.conf ]; then
  echo "[INFO] ldap config(/etc/ocserv/nslcd.conf) exist. link to /etc."
  ln -sf /etc/ocserv/nslcd.conf /etc/nslcd.conf
  if ! service nslcd start; then
      echo "[WARN] nslcd start failed"
  fi
fi

echo "[INFO] Starting OpenConnect server..."
exec ocserv -c /etc/ocserv/ocserv.conf -f "$@"

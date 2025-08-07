#!/bin/bash
set -e

# 默认值（如未设置则生成随机字符串）
gen_rand() {
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1
}

if [ -f /opt/certs/server-cert.pem ]; then
  echo "[INFO] Certificates already exist. Skipping generation."
else
  # 执行替换 + 生成逻辑（包裹成一个函数）
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
  # 替换模板内容
  sed -i "s/Your desired authority name/${CA_CN}/g" /opt/certs/ca-tmp
  sed -i "s/Your desired orgnization name/${CA_ORG}/g" /opt/certs/ca-tmp
  sed -i "s/yourdomainname/${SERV_DOMAIN}/g" /opt/certs/serv-tmp
  sed -i "s/Your desired orgnization name/${SERV_ORG}/g" /opt/certs/serv-tmp
  sed -i "s/user/${USER_ID}/g" /opt/certs/user-tmp

  # 生成证书
  certtool --generate-privkey --outfile /opt/certs/ca-key.pem
  certtool --generate-self-signed \
    --load-privkey /opt/certs/ca-key.pem \
    --template /opt/certs/ca-tmp \
    --outfile /opt/certs/ca-cert.pem

  certtool --generate-privkey --outfile /opt/certs/server-key.pem
  certtool --generate-certificate \
    --load-privkey /opt/certs/server-key.pem \
    --load-ca-certificate /opt/certs/ca-cert.pem \
    --load-ca-privkey /opt/certs/ca-key.pem \
    --template /opt/certs/serv-tmp \
    --outfile /opt/certs/server-cert.pem

  certtool --generate-privkey --outfile /opt/certs/user-key.pem
  certtool --generate-certificate \
    --load-privkey /opt/certs/user-key.pem \
    --load-ca-certificate /opt/certs/ca-cert.pem \
    --load-ca-privkey /opt/certs/ca-key.pem \
    --template /opt/certs/user-tmp \
    --outfile /opt/certs/user-cert.pem

  # 导出 .p12 格式用户证书
  openssl pkcs12 -export \
    -inkey /opt/certs/user-key.pem \
    -in /opt/certs/user-cert.pem \
    -certfile /opt/certs/ca-cert.pem \
    -out /opt/certs/user.p12 \
    -passout pass:${CERT_P12_PASS}
fi

# 如果 dnsmasq 存在则启动
if command -v dnsmasq >/dev/null 2>&1; then
    echo "[INFO] dnsmasq found. Starting dnsmasq..."
    dnsmasq -C /usr/local/etc/dnsmasq.conf
else
    echo "[INFO] dnsmasq not found. Skipping dnsmasq start."
fi

# 开启 IPv4 转发
echo "[INFO] Enabling IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1

# 检查 /dev/net/tun 是否存在
if [ ! -e /dev/net/tun ]; then
    echo "[INFO] Creating /dev/net/tun..."
    mkdir -p /dev/net
    mknod /dev/net/tun c 10 200
    chmod 600 /dev/net/tun
fi

# 设置 iptables NAT
echo "[INFO] Configuring iptables for NAT..."
iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -j MASQUERADE
iptables -C FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || iptables -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

if [ -f /etc/ocserv/ldap.conf ]; then
  echo "[INFO] ldap config(/etc/ocserv/ldap.conf) exist. link to /etc."
  rm /etc/ldap.conf
  ln -s /etc/ocserv/ldap.conf /etc/ldap.conf
  sed -i 's/^passwd:.*/passwd:\tfiles ldap/' /etc/nsswitch.conf
  sed -i 's/^group:.*/group:\tfiles ldap/' /etc/nsswitch.conf
  sed -i 's/^shadow:.*/shadow:\tfiles ldap/' /etc/nsswitch.conf
fi

# 启动 ocserv
echo "[INFO] Starting OpenConnect server..."
exec ocserv -c /etc/ocserv/ocserv.conf -f "$@"

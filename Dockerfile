FROM ubuntu:trusty
MAINTAINER ly Wu <wuluoyong7@gmail.com>

ADD ./certs /opt/certs
ADD ./bin /usr/local/bin
ADD dnsmasq.conf /usr/local/etc/dnsmasq.conf
RUN chmod a+x /usr/local/bin/*
WORKDIR /etc/ocserv

# china timezone
RUN echo "Asia/Shanghai" > /etc/timezone

# install compiler, dependencies, tools , dnsmasq
RUN apt-get update && apt-get install -y \
    build-essential wget xz-utils libgnutls28-dev \
    libev-dev libwrap0-dev libpam0g-dev libseccomp-dev libreadline-dev \
    libnl-route-3-dev libkrb5-dev liboath-dev libtalloc-dev \
    libhttp-parser-dev libpcl1-dev libopts25-dev autogen pkg-config nettle-dev \
    gnutls-bin gperf liblockfile-bin nuttcp lcov iptables unzip dnsmasq \
    && rm -rf /var/lib/apt/lists/*

# configuration dnsmasq
RUN mkdir -p /temp && cd /temp \
    && wget https://github.com/felixonmars/dnsmasq-china-list/archive/master.zip \
    && unzip master.zip \
    && cd dnsmasq-china-list-master \
    && cp *.conf /etc/dnsmasq.d/ \
    && cd / && rm -rf /temp

# configuration lz4
RUN mkdir -p /temp && cd /temp \
    && wget https://github.com/lz4/lz4/releases/latest -O lz4.html \
    && export LZ4_VERSION=$(cat lz4.html | grep -m 1 -o 'v[0-9]\.[0-9]\.[0-9]') \
    && export LZ4_SUFFIX=$(cat lz4.html | grep -m 1 -o '[0-9]\.[0-9]\.[0-9]') \
    && wget https://github.com/lz4/lz4/archive/{$LZ4_VERSION}.tar.gz \
    && tar xvf {$LZ4_VERSION}.tar.gz \
    && cd lz4-{$LZ4_SUFFIX} \
    && make install \
    && ln -sf /usr/local/lib/liblz4.* /usr/lib/ \
    && cd / && rm -rf /temp

# configuration ocserv
RUN mkdir -p /temp && cd /temp \
    && wget https://ocserv.gitlab.io/www/download.html \
    && export OCSERV_VERSION=$(cat download.html | grep -o '[0-9]*\.[0-9]*\.[0-9]*') \
    && wget ftp://ftp.infradead.org/pub/ocserv/ocserv-{$OCSERV_VERSION}.tar.xz \
    && tar xvf ocserv-{$OCSERV_VERSION}.tar.xz \
    && cd ocserv-{$OCSERV_VERSION} \
    && ./configure --prefix=/usr --sysconfdir=/etc --with-local-talloc \
    && make && make install \
    && cd / && rm -rf /temp

# generate sll keys
RUN cd /opt/certs && ls \
    && CA_CN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1) && bash -c "sed -i 's/Your desired authority name/$CA_CN/g' /opt/certs/ca-tmp" \
    && CA_ORG=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1) && bash -c "sed -i 's/Your desired orgnization name/$CA_ORG/g' /opt/certs/ca-tmp" \
    && SERV_DOMAIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-12} | head -n 1) && bash -c -i "sed -i 's/yourdomainname/$SERV_DOMAIN/g' /opt/certs/serv-tmp" \
    && SERV_ORG=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1) && bash -c "sed -i 's/Your desired orgnization name/$SERV_ORG/g' /opt/certs/serv-tmp" \
    && USER_ID=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-10} | head -n 1) && bash -c "sed -i 's/user/$USER_ID/g' /opt/certs/user-tmp"

# generate [ca-key.pem] -> ca-cert.pem [ca-key]
RUN certtool --generate-privkey --outfile /opt/certs/ca-key.pem && certtool --generate-self-signed --load-privkey /opt/certs/ca-key.pem --template /opt/certs/ca-tmp --outfile /opt/certs/ca-cert.pem
# generate [server-key.pem] -> server-cert.pem [ca-key, server-key] 
RUN certtool --generate-privkey --outfile /opt/certs/server-key.pem && certtool --generate-certificate --load-privkey /opt/certs/server-key.pem --load-ca-certificate /opt/certs/ca-cert.pem --load-ca-privkey /opt/certs/ca-key.pem --template /opt/certs/serv-tmp --outfile /opt/certs/server-cert.pem
# generate [user-key.pem] -> user-cert.pem [ca-key, user-key]
RUN certtool --generate-privkey --outfile /opt/certs/user-key.pem && certtool --generate-certificate --load-privkey /opt/certs/user-key.pem --load-ca-certificate /opt/certs/ca-cert.pem --load-ca-privkey /opt/certs/ca-key.pem --template /opt/certs/user-tmp --outfile /opt/certs/user-cert.pem
# generate user.p12 [user-key, user-cert, ca-cert]
RUN openssl pkcs12 -export -inkey /opt/certs/user-key.pem -in /opt/certs/user-cert.pem -certfile /opt/certs/ca-cert.pem -out /opt/certs/user.p12 -passout pass:616

CMD ["vpn_run"]

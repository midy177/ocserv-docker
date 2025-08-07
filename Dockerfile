FROM ubuntu:24.04
LABEL maintainer="ly Wu <wuluoyong7@gmail.com>"

ADD ./certs /opt/certs
ADD ./bin /usr/local/bin
RUN chmod a+x /usr/local/bin/*
WORKDIR /etc/ocserv

# 设置时区为中国
RUN echo "Asia/Shanghai" > /etc/timezone && \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    DEBIAN_FRONTEND=noninteractive dpkg-reconfigure tzdata

# 安装编译器、依赖、工具
RUN apt-get update && apt-get install -y \
    # 编译工具
    build-essential autogen pkg-config gperf lcov \
    # 下载/网络工具
    wget curl unzip iptables ipcalc nuttcp \
    # 必需库
    libgnutls28-dev nettle-dev libev-dev libwrap0-dev \
    libpam0g-dev libseccomp-dev libreadline-dev \
    libnl-route-3-dev libkrb5-dev liboath-dev libtalloc-dev \
    libhttp-parser-dev libopts25-dev liblockfile-bin \
    # LDAP 支持
    libpam-ldapd libnss-ldapd \
    # 时区/其他
    xz-utils gnutls-bin \
    && rm -rf /var/lib/apt/lists/*


# 安装 lz4
RUN set -eux; \
    mkdir -p /temp && cd /temp \
    && LZ4_VERSION=$(curl -sSL -o /dev/null -w '%{url_effective}' https://github.com/lz4/lz4/releases/latest | awk -F/ '{print $NF}') \
    && LZ4_SUFFIX=${LZ4_VERSION#v} \
    && wget -q https://github.com/lz4/lz4/archive/${LZ4_VERSION}.tar.gz \
    && tar xzf ${LZ4_VERSION}.tar.gz \
    && cd lz4-${LZ4_SUFFIX} \
    && make && make install \
    && ln -sf /usr/local/lib/liblz4.* /usr/lib/ \
    && cd / && rm -rf /temp

# 下载并安装 ocserv 最新版本
RUN set -eux; \
    mkdir -p /temp && cd /temp; \
    OCSERV_VERSION=$(curl -sSL https://ocserv.openconnect-vpn.net/download.html | grep 'Latest version is '| grep -o '[0-9]*\.[0-9]*\.[0-9]*'); \
    wget https://www.infradead.org/ocserv/download/ocserv-${OCSERV_VERSION}.tar.xz; \
    tar -xf ocserv-${OCSERV_VERSION}.tar.xz; \
    cd ocserv-${OCSERV_VERSION#v}; \
    ./configure --prefix=/usr --sysconfdir=/etc --with-local-talloc --enable-ldap; \
    make -j"$(nproc)"; \
    make install; \
    cd /; rm -rf /temp

RUN sed -i 's/^passwd:.*/passwd:\tfiles ldap/' /etc/nsswitch.conf \
    && sed -i 's/^group:.*/group:\tfiles ldap/' /etc/nsswitch.conf \
    && sed -i 's/^shadow:.*/shadow:\tfiles ldap/' /etc/nsswitch.conf


# 写入 pam.d/ocserv
RUN echo "auth    sufficient  pam_ldap.so"  >  /etc/pam.d/ocserv && \
    echo "auth    required    pam_unix.so"   >> /etc/pam.d/ocserv && \
    echo "account sufficient  pam_ldap.so"  >> /etc/pam.d/ocserv && \
    echo "account required    pam_unix.so"  >> /etc/pam.d/ocserv && \
    echo "password required   pam_ldap.so"  >> /etc/pam.d/ocserv && \
    echo "session  required   pam_ldap.so"  >> /etc/pam.d/ocserv



CMD ["entrypoint.sh"]

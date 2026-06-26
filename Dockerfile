FROM debian:bookworm-slim AS builder

WORKDIR /build

ARG OPENSSL_VERSION
ARG NGINX_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends git curl wget perl build-essential ca-certificates libpcre2-dev zlib1g-dev libzstd-dev \
    && rm -rf /var/lib/apt/lists/*

RUN echo "Building OpenSSL ${OPENSSL_VERSION}" \
    && curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" | tar xz -C /tmp \
    && cd "/tmp/openssl-${OPENSSL_VERSION}" \
    && ./config --prefix=/usr/local --openssldir=/usr/local/etc/ssl --libdir=lib no-tests shared enable-ktls zlib enable-zstd \
    && make -j"$(nproc)" \
    && make install_sw install_ssldirs \
    && rm -rf /tmp/openssl-*

RUN git clone --depth=1 https://github.com/tokers/zstd-nginx-module.git /build/zstd-nginx-module

RUN echo "Building Nginx ${NGINX_VERSION}" \
    && curl -fsSL "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" | tar xz -C /tmp \
    && cd "/tmp/nginx-${NGINX_VERSION}" \
    && ./configure \
        --prefix=/etc/nginx \
        --sbin-path=/usr/sbin/nginx \
        --conf-path=/etc/nginx/nginx.conf \
        --http-log-path=/var/log/nginx/access.log \
        --error-log-path=/var/log/nginx/error.log \
        --pid-path=/run/nginx.pid \
        --user=nginx \
        --group=nginx \
        --with-cc-opt="-I/usr/local/include -O2" \
        --with-ld-opt="-L/usr/local/lib -Wl,-rpath,/usr/local/lib" \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-http_realip_module \
        --with-http_gzip_static_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-pcre \
        --with-pcre-jit \
        --add-module=/build/zstd-nginx-module \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/nginx-*

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends libpcre2-8-0 libzstd1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nginx && useradd -r -g nginx -s /sbin/nologin -d /nonexistent nginx

COPY --from=builder /usr/sbin/nginx           /usr/sbin/nginx
COPY --from=builder /etc/nginx/mime.types     /etc/nginx/mime.types
COPY --from=builder /usr/local/lib/libssl.so.3    /usr/local/lib/libssl.so.3
COPY --from=builder /usr/local/lib/libcrypto.so.3 /usr/local/lib/libcrypto.so.3

RUN ldconfig

RUN mkdir -p /etc/nginx/conf.d /etc/nginx/stream.d /etc/nginx/snippets /var/log/nginx /run/website \
    && chown nginx:nginx /var/log/nginx

EXPOSE 80 443/tcp 443/udp

STOPSIGNAL SIGQUIT

CMD ["/usr/sbin/nginx", "-g", "daemon off;"]

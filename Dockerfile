FROM debian:bookworm-slim AS openssl-builder

WORKDIR /build

ARG PACKAGES_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends curl perl build-essential ca-certificates zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ARG OPENSSL_VERSION

RUN echo "Building OpenSSL ${OPENSSL_VERSION}" \
    && curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" | tar xz -C /tmp \
    && cd "/tmp/openssl-${OPENSSL_VERSION}" \
    && ./config --prefix=/usr/local --openssldir=/usr/local/etc/ssl --libdir=lib no-tests shared enable-ktls zlib \
    && make -j"$(nproc)" \
    && make install_sw install_ssldirs \
    && rm -rf /tmp/openssl-*

RUN echo "/usr/local/lib" > /etc/ld.so.conf.d/openssl.conf && ldconfig

FROM debian:bookworm-slim AS nginx-builder

WORKDIR /build

ARG PACKAGES_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends curl perl build-essential ca-certificates libpcre2-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=openssl-builder /usr/local/ /usr/local/

ARG NGINX_VERSION

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
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-pcre \
        --with-pcre-jit \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/nginx-* \
    && ldd /usr/sbin/nginx \
        | awk 'NF==4 && $3~/^\// && $3!~/^\/usr\/local\// && $3!~/ld-linux/ && $3!~/libc\.so/ && $3!~/libdl\.so/ && $3!~/libpthread\.so/ && $3!~/libm\.so/ {print $3}' \
        | xargs -I{} cp {} /usr/local/lib/

FROM gcr.io/distroless/base-debian12 AS distroless

FROM debian:bookworm-slim AS setup

COPY --from=distroless /etc/passwd /etc/passwd
COPY --from=distroless /etc/group  /etc/group

ARG PACKAGES_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends libpcre2-8-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nginx && useradd -r -g nginx -s /sbin/nologin -d /nonexistent nginx

RUN ldconfig

RUN mkdir -p /etc/nginx/conf.d /etc/nginx/stream.d /etc/nginx/snippets /var/log/nginx /run/website \
    && chown nginx:nginx /var/log/nginx

FROM gcr.io/distroless/base-debian12

COPY --from=setup /etc/passwd    /etc/passwd
COPY --from=setup /etc/group     /etc/group
COPY --from=setup /etc/nginx     /etc/nginx
COPY --from=setup /var/log/nginx /var/log/nginx
COPY --from=setup /run/website   /run/website

COPY --from=nginx-builder /usr/local/lib/       /usr/local/lib/
COPY --from=nginx-builder /usr/sbin/nginx       /usr/sbin/nginx
COPY --from=nginx-builder /etc/nginx/mime.types /etc/nginx/mime.types

EXPOSE 80 443/tcp 443/udp

STOPSIGNAL SIGQUIT

CMD ["/usr/sbin/nginx", "-g", "daemon off;"]

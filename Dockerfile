FROM debian:bookworm-slim AS builder

WORKDIR /build

ARG DEBIAN_PACKAGES_HASH

RUN apt-get update && apt-get install -y --no-install-recommends git curl wget perl build-essential ca-certificates cmake libpcre2-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

ARG OPENSSL_VERSION

RUN echo "Building OpenSSL ${OPENSSL_VERSION}" \
    && curl -fsSL "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz" | tar xz -C /tmp \
    && cd "/tmp/openssl-${OPENSSL_VERSION}" \
    && ./config --prefix=/usr/local --openssldir=/usr/local/etc/ssl --libdir=lib no-tests shared enable-ktls zlib \
    && make -j"$(nproc)" \
    && make install_sw install_ssldirs \
    && rm -rf /tmp/openssl-*

ARG NGX_BROTLI_COMMIT

RUN git clone --depth=1 --recurse-submodules https://github.com/google/ngx_brotli.git /build/ngx_brotli \
    && cmake -S /build/ngx_brotli/deps/brotli -B /build/ngx_brotli/deps/brotli/out -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    && cmake --build /build/ngx_brotli/deps/brotli/out --config Release --target brotlienc brotlicommon -j"$(nproc)"

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
        --with-http_gzip_static_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-pcre \
        --with-pcre-jit \
        --add-module=/build/ngx_brotli \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/nginx-* \
    && ldd /usr/sbin/nginx \
        | awk 'NF==4 && $3~/^\// && $3!~/^\/usr\/local\// && $3!~/ld-linux/ && $3!~/libc\.so/ && $3!~/libdl\.so/ && $3!~/libpthread\.so/ && $3!~/libm\.so/ {print $3}' \
        | xargs -I{} cp {} /usr/local/lib/

FROM gcr.io/distroless/base-debian12 AS distroless

FROM debian:bookworm-slim AS setup

ARG DEBIAN_PACKAGES_HASH

COPY --from=distroless /etc/passwd /etc/passwd
COPY --from=distroless /etc/group  /etc/group

RUN apt-get update && apt-get install -y --no-install-recommends libpcre2-8-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd -r nginx && useradd -r -g nginx -s /sbin/nologin -d /nonexistent nginx

RUN ldconfig

RUN mkdir -p /etc/nginx/conf.d /etc/nginx/stream.d /etc/nginx/snippets /var/log/nginx /run/website \
    && chown nginx:nginx /var/log/nginx

FROM gcr.io/distroless/base-debian12

COPY --from=setup   /etc/passwd           /etc/passwd
COPY --from=setup   /etc/group            /etc/group
COPY --from=setup   /etc/nginx            /etc/nginx
COPY --from=setup   /var/log/nginx        /var/log/nginx
COPY --from=setup   /run/website          /run/website
COPY --from=builder /usr/sbin/nginx       /usr/sbin/nginx
COPY --from=builder /etc/nginx/mime.types /etc/nginx/mime.types
COPY --from=builder /usr/local/lib/       /usr/local/lib/

EXPOSE 80 443/tcp 443/udp

STOPSIGNAL SIGQUIT

CMD ["/usr/sbin/nginx", "-g", "daemon off;"]

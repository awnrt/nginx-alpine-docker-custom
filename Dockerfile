FROM alpine:3.24 AS builder

RUN apk add --no-cache \
    bash \
    curl \
    git \
    gnupg \
    build-base \
    linux-headers \
    cmake \
    perl \
    openssl-dev \
    pcre2-dev \
    zlib-dev \
    libmaxminddb-dev \
    tar

WORKDIR /build

COPY build.sh .

RUN chmod +x build.sh \
    && ./build.sh

FROM alpine:3.24

RUN apk add --no-cache \
    ca-certificates \
    libmaxminddb

RUN addgroup -S nginx \
    && adduser -S -D -H -s /sbin/nologin -G nginx nginx

# Copy nginx install tree from builder
COPY --from=builder /build/output/ /

RUN mkdir -p \
        /var/log/nginx \
        /var/lib/nginx/body \
        /var/lib/nginx/proxy \
        /run \
    && chown -R nginx:nginx \
        /var/log/nginx \
        /var/lib/nginx

# Docker logging
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

EXPOSE 80 443

STOPSIGNAL SIGQUIT

CMD ["nginx", "-g", "daemon off;"]

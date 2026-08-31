#!/usr/bin/env bash
set -euo pipefail

nginx_version="1.31.4"
openssl_version="4.0.2"
zlib_version="1.3.2"
pcre2_version="10.48"
geoip2_version="3.4"
brotli_commit="a71f9312c2deb28875acc7bacfdd5695a111aa53"

user=nginx
group=nginx
maintainer="awy <awy@awy.one>"
ARCH=amd64

run_step() {
    local name="$1"
    shift
    echo "  -> Running: $name"
    if ! "$@"; then
        echo "Error: $name failed"
        exit 1
    fi
}

mkdir -p src output
cd src

echo ">>> [1/6] Downloading sources..."

# Nginx
curl -sSLf https://nginx.org/download/nginx-${nginx_version}.tar.gz -o nginx-${nginx_version}.tar.gz
curl -sSLf https://nginx.org/download/nginx-${nginx_version}.tar.gz.asc -o nginx-${nginx_version}.tar.gz.asc
curl -sSLf https://nginx.org/keys/nginx_signing.key | gpg --import -q
curl -sSLf https://nginx.org/keys/arut.key | gpg --import -q
curl -sSLf https://nginx.org/keys/pluknet.key | gpg --import -q
curl -sSLf https://nginx.org/keys/sb.key | gpg --import -q
curl -sSLf https://nginx.org/keys/thresh.key | gpg --import -q
gpg --verify --trust-model always nginx-${nginx_version}.tar.gz.asc nginx-${nginx_version}.tar.gz || { echo "GPG verification failed for nginx"; exit 1; }
tar -xf nginx-${nginx_version}.tar.gz

# OpenSSL
curl -sSLf https://github.com/openssl/openssl/releases/download/openssl-${openssl_version}/openssl-${openssl_version}.tar.gz -o openssl-${openssl_version}.tar.gz
curl -sSLf https://github.com/openssl/openssl/releases/download/openssl-${openssl_version}/openssl-${openssl_version}.tar.gz.asc -o openssl-${openssl_version}.tar.gz.asc
curl -sSLf https://github.com/openssl/openssl/releases/download/openssl-${openssl_version}/openssl-${openssl_version}.tar.gz.sha256 -o openssl-${openssl_version}.tar.gz.sha256
curl -sSLf https://openssl-library.org/source/pubkeys.asc | gpg --import -q
gpg --verify --trust-model always openssl-${openssl_version}.tar.gz.asc openssl-${openssl_version}.tar.gz || { echo "GPG verification failed for OpenSSL"; exit 1; }

LOCAL_HASH=$(sha256sum openssl-${openssl_version}.tar.gz | awk '{print $1}')
REMOTE_HASH=$(awk '{print $1}' openssl-${openssl_version}.tar.gz.sha256)
if [ "$LOCAL_HASH" != "$REMOTE_HASH" ]; then
    echo "OpenSSL hash mismatch"
    exit 1
fi
tar -xf openssl-${openssl_version}.tar.gz

# PCRE2
curl -sSLf https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${pcre2_version}/pcre2-${pcre2_version}.tar.gz -o pcre2-${pcre2_version}.tar.gz
curl -sSLf https://github.com/PCRE2Project/pcre2/releases/download/pcre2-${pcre2_version}/pcre2-${pcre2_version}.tar.gz.sig -o pcre2-${pcre2_version}.tar.gz.sig
gpg --keyserver hkps://keys.openpgp.org --recv-keys BACF71F10404D5761C09D392021DE40BFB63B406
gpg --verify --trust-model always pcre2-${pcre2_version}.tar.gz.sig pcre2-${pcre2_version}.tar.gz || { echo "GPG verification failed for PCRE2"; exit 1; }
tar -xf pcre2-${pcre2_version}.tar.gz

# Zlib
curl -sSLf https://www.zlib.net/zlib-${zlib_version}.tar.gz -o zlib-${zlib_version}.tar.gz
curl -sSLf https://www.zlib.net/zlib-${zlib_version}.tar.gz.asc -o zlib-${zlib_version}.tar.gz.asc
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 5ED46A6721D365587791E2AA783FCD8E58BCAFBA
gpg --verify --trust-model always zlib-${zlib_version}.tar.gz.asc zlib-${zlib_version}.tar.gz || { echo "GPG verification failed for zlib"; exit 1; }
tar -xf zlib-${zlib_version}.tar.gz

echo "  -> Pre-building Zlib for OpenSSL..."
(cd zlib-${zlib_version} && ./configure --static && make -j"$(nproc)")

# GeoIP2
curl -sSLf https://github.com/leev/ngx_http_geoip2_module/archive/refs/tags/${geoip2_version}.tar.gz -o ngx_http_geoip2_module-${geoip2_version}.tar.gz
tar -xf ngx_http_geoip2_module-${geoip2_version}.tar.gz

# ngx_brotli (no tagged releases; pinned by commit)
git clone --recursive https://github.com/google/ngx_brotli.git
(cd ngx_brotli && git checkout -q ${brotli_commit} && git submodule update --init --recursive)

echo "  -> Pre-building Brotli static libs..."
(
    cd ngx_brotli/deps/brotli
    mkdir -p out
    cd out
    cmake -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_SHARED_LIBS=OFF \
          -DCMAKE_C_FLAGS="-O2 -march=x86-64-v4 -fPIC" \
          ..
    cmake --build . --config Release -j"$(nproc)" --target brotlienc brotlicommon brotlidec
)

echo ">>> [2/6] Configuring Nginx (will compile OpenSSL, PCRE2, Zlib)..."
cd nginx-${nginx_version}

run_step "nginx configure" ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --pid-path=/run/nginx.pid \
    --user=${user} \
    --group=${group} \
    \
    --lock-path=/run/nginx.lock \
    --http-log-path=/var/log/nginx/access.log \
    --http-client-body-temp-path=/var/lib/nginx/body \
    --http-proxy-temp-path=/var/lib/nginx/proxy \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_gunzip_module \
    --with-cc-opt='-O2 -march=x86-64-v4 -DTCP_FASTOPEN=23 -fstack-protector-strong -Wformat -Werror=format-security -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -fPIC' \
    --with-ld-opt='-Wl,-z,relro -Wl,-z,now' \
    \
    --with-zlib=../zlib-${zlib_version} \
    --with-pcre=../pcre2-${pcre2_version} \
    --with-openssl=../openssl-${openssl_version} \
    --with-openssl-opt="zlib --with-zlib-include=$(pwd)/../zlib-${zlib_version} --with-zlib-lib=$(pwd)/../zlib-${zlib_version} no-shared enable-ec_nistp_64_gcc_128 -DOPENSSL_TLS_SECURITY_LEVEL=2 -O2 -march=x86-64-v4" \
    \
    --add-module=../ngx_http_geoip2_module-${geoip2_version} \
    --add-module=../ngx_brotli \
    --with-stream \
    --with-stream_ssl_module \
    \
    --without-poll_module \
    --without-http_charset_module \
    --without-http_ssi_module \
    --without-http_userid_module \
    --without-http_mirror_module \
    --without-http_split_clients_module \
    --without-http_referer_module \
    --without-http_fastcgi_module \
    --without-http_uwsgi_module \
    --without-http_scgi_module \
    --without-http_memcached_module \
    --without-http_limit_conn_module \
    --without-http_empty_gif_module \
    --without-http_browser_module \
    --without-http_upstream_hash_module \
    --without-http_upstream_ip_hash_module \
    --without-http_upstream_least_conn_module \
    --without-http_upstream_random_module \
    --without-mail_pop3_module \
    --without-mail_imap_module \
    --without-mail_smtp_module \
    --without-stream_split_clients_module \
    --without-stream_return_module \
    --without-stream_set_module \
    --without-stream_upstream_hash_module \
    --without-stream_upstream_least_conn_module \
    --without-stream_upstream_random_module \
    --without-stream_upstream_zone_module

echo ">>> [3/6] Compiling Nginx..."

run_step "nginx make" make -j"$(nproc)"

if [ ! -f objs/nginx ]; then
    echo "Error: nginx binary not found after build"
    exit 1
fi

strip objs/nginx

echo ">>> [4/6] Installing & Cleanup..."

mkdir -p ../pkg
run_step "nginx install" make install DESTDIR="$(pwd)"/../pkg

rm -rf ../pkg/etc/nginx/html
rm -f ../pkg/etc/nginx/*.default
rm -f ../pkg/etc/nginx/koi-*
rm -f ../pkg/etc/nginx/win-*
rm -f ../pkg/etc/nginx/fastcgi.conf
rm -f ../pkg/etc/nginx/fastcgi_params
rm -f ../pkg/etc/nginx/scgi_params
rm -f ../pkg/etc/nginx/uwsgi_params

mkdir -p ../pkg/etc/nginx/conf.d
mkdir -p ../pkg/etc/nginx/snippets

cd ..

echo ">>> [5/6] Preparing runtime filesystem..."

# Runtime directories
mkdir -p pkg/var/log/nginx
mkdir -p pkg/var/lib/nginx/body
mkdir -p pkg/var/lib/nginx/proxy
mkdir -p pkg/run

# Remove unnecessary default files
rm -rf pkg/etc/nginx/html
rm -f pkg/etc/nginx/*.default
rm -f pkg/etc/nginx/koi-*
rm -f pkg/etc/nginx/win-*
rm -f pkg/etc/nginx/fastcgi.conf
rm -f pkg/etc/nginx/fastcgi_params
rm -f pkg/etc/nginx/scgi_params
rm -f pkg/etc/nginx/uwsgi_params

# Keep these directories available
mkdir -p pkg/etc/nginx/conf.d
mkdir -p pkg/etc/nginx/snippets

echo ">>> [6/6] Build output ready..."

if [ ! -f pkg/usr/sbin/nginx ]; then
    echo "Error: nginx binary not found"
    exit 1
fi

echo "Runtime files:"
ls -lh pkg/usr/sbin/nginx

rm -rf ../output
mkdir -p ../output
cp -a pkg/. ../output/

echo "Success!"

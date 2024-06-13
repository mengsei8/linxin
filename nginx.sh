#!/bin/bash

set -e  # 如果遇到错误就退出脚本
set -u  # 使用未初始化的变量就退出脚本

NGINX_VERSION="nginx-1.22.1"
DEPENDENCIES=("openssl-1.1.1t" "pcre-8.45" "zlib-1.2.13")
TOOL_DIR="/tmp/tools"
SRC_DIR="/usr/local/src"
NGINX_PREFIX="/opt/${NGINX_VERSION}"
NGINX_SBIN="${NGINX_PREFIX}/sbin/nginx"
BIN_DIR="/opt/bin"
LOG_FILE="/var/log/nginx_install.log"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

check_dependencies() {
    for cmd in wget tar make gcc; do
        if ! command -v $cmd &> /dev/null; then
            log "依赖 $cmd 不存在，请安装后再运行此脚本。"
            exit 1
        fi
    done
}

init() {
    log "初始化工具目录和下载依赖包..."
    mkdir -p ${TOOL_DIR}
    cd ${TOOL_DIR}
    for dep in "${DEPENDENCIES[@]}"; do
        wget https://d.frps.cn/file/tools/nginx/${dep}.tar.gz
    done
    wget https://d.frps.cn/file/tools/nginx/${NGINX_VERSION}.tar.gz
    for dep in "${DEPENDENCIES[@]}"; do
        tar zxvf ${dep}.tar.gz -C ${SRC_DIR}
    done
}

create_user_and_scripts() {
    log "创建 nginx 用户和管理脚本..."
    useradd nginx -s /sbin/nologin -M || true
    mkdir -p ${BIN_DIR}
    echo "${NGINX_SBIN} -s reload" >${BIN_DIR}/nginx_reload.sh
    echo "${NGINX_SBIN} -c ${NGINX_PREFIX}/conf/nginx.conf" >${BIN_DIR}/nginx_start.sh
    echo "killall -9 nginx" >${BIN_DIR}/nginx_stop.sh
    chmod 755 ${BIN_DIR}/nginx_*.sh
}

install_nginx() {
    log "编译和安装 Nginx..."
    cd ${TOOL_DIR} && tar xf ${NGINX_VERSION}.tar.gz && cd ${NGINX_VERSION}
    ./configure --prefix=${NGINX_PREFIX} \
                --with-openssl=${SRC_DIR}/openssl-1.1.1t \
                --with-pcre=${SRC_DIR}/pcre-8.45 \
                --with-zlib=${SRC_DIR}/zlib-1.2.13 \
                --with-http_ssl_module \
                --with-http_stub_status_module \
                --with-stream \
                --with-http_gzip_static_module
    make && make install
}

init_nginx_conf() {
    log "初始化 Nginx 配置文件..."
    if [ -d "${NGINX_PREFIX}" ]; then
        mv ${NGINX_PREFIX}/conf/nginx.conf ${NGINX_PREFIX}/conf/nginx.conf.bak
        mkdir -p ${NGINX_PREFIX}/conf/conf.d
        cat > ${NGINX_PREFIX}/conf/nginx.conf <<-EOF
user nginx;
error_log  logs/nginx_error.log;
worker_processes  1;
events {
    worker_connections  4096;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    log_format  main  '\$remote_addr | \$remote_user | \$time_local | \$request | \$http_host |'
                      '\$status | \$upstream_status | \$body_bytes_sent | \$http_referer '
                      '\$http_user_agent | \$upstream_addr | \$request_time | \$upstream_response_time';
    sendfile        on;
    charset utf-8;
    keepalive_timeout  65;
    large_client_header_buffers 8 128k;
    server_tokens off;
    proxy_buffering on;
    proxy_hide_header X-Powered-By;
    proxy_hide_header Server;
    proxy_buffer_size 1024k;
    proxy_buffers 32 1024k;
    proxy_busy_buffers_size 2048k;
    proxy_temp_file_write_size 2048k;
    proxy_connect_timeout 300s;
    proxy_read_timeout 300s;
    proxy_send_timeout 300s;
    proxy_ignore_headers Set-Cookie;
    client_header_timeout 120s;
    client_max_body_size 100M;
    client_body_buffer_size 100M;
    client_header_buffer_size 128k;
    fastcgi_connect_timeout 600;
    fastcgi_send_timeout 600;
    fastcgi_read_timeout 600;
    fastcgi_buffer_size 128k;
    fastcgi_buffers 4 128k;
    fastcgi_busy_buffers_size 256k;
    fastcgi_temp_file_write_size 256k;
    gzip on;
    gzip_min_length 1000;
    gzip_buffers 16 8k;
    gzip_comp_level 8;
    gzip_proxied any;
    gzip_disable "MSIE [1-6]\.";
    gzip_types  text/plain text/css application/javascript application/x-javascript text/xml application/json application/xml application/xml+rss text/javascript image/jpg image/jpeg image/png image/gif;
    tcp_nopush on;
    tcp_nodelay on;
    server_names_hash_bucket_size 128;
    add_header Nginx-Server "\$hostname";
    max_ranges 1;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;

    include ${NGINX_PREFIX}/conf/conf.d/*.conf;
}
EOF
    else
        log "Nginx 目录 ${NGINX_PREFIX} 不存在，初始化配置失败。"
        exit 3
    fi

    if [ -d "${NGINX_PREFIX}/conf/conf.d" ]; then
        cat > ${NGINX_PREFIX}/conf/conf.d/nginx.conf <<-EOF
server {
  listen       80;
  server_name  localhost;
  location / {
    root   html;
    index  index.html index.htm;
  }
  error_page   500 502 503 504  /50x.html;
  location = /50x.html {
    root   html;
  }
}
EOF
    else
        log "Nginx 配置目录 ${NGINX_PREFIX}/conf/conf.d 不存在，初始化服务器配置失败。"
        exit 4
    fi

    if [ -d "${NGINX_PREFIX}/conf" ]; then
        ${BIN_DIR}/nginx_start.sh
    else
        log "Nginx 配置目录 ${NGINX_PREFIX}/conf 不存在，启动失败。"
        exit 5
    fi
}

help() {
    log "提供帮助信息..."
    echo "######################"
    echo "修改配置文件路径"
    echo "/opt/${NGINX_VERSION}/conf/conf.d/nginx.conf"
    echo "启动停止"
    echo "systemctl start nginx"
    echo "systemctl stop nginx"
    echo "启动停止"
    echo "/opt/bin/nginx_start.sh"
    echo "/opt/bin/nginx_stop.sh"
    echo "重载配置"
    echo "/opt/bin/nginx_reload.sh"
    echo "######################"
}

main() {
    check_dependencies
    init
    create_user_and_scripts
    install_nginx
    init_nginx_conf
    help
}

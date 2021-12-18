# Based on https://github.com/curiefense/curiefense/blob/9e5aca0f6d8f7604a6f652274adfa58d48f39522/curiefense/images/curiefense-nginx-ingress/Dockerfile

ARG RUSTBIN_TAG=main

FROM curiefense/curiefense-rustbuild-bionic:${RUSTBIN_TAG} AS rustbin

FROM docker.io/nginx/nginx-ingress:2.0.3 as nginx-ingress

FROM ubuntu:21.10 AS curiefense-source

RUN set -x \
    && apt-get update \
    && apt-get install -y git

WORKDIR /usr/local/src/

RUN set -x \
    && git clone https://github.com/curiefense/curiefense.git \
    && cd curiefense \
    && git checkout 9e5aca0f6d8f7604a6f652274adfa58d48f39522

FROM docker.io/openresty/openresty:1.19.9.1-4-bionic as openresty

USER root

# Create nginx user/group first, to be consistent throughout docker variants
# From: https://github.com/nginxinc/docker-nginx/blob/ef8e9912a2de9b51ce9d1f79a5c047eb48b05fc1/mainline/debian/Dockerfile#L14-L17
RUN set -x \
    && addgroup --system --gid 101 nginx \
    && adduser --system --disabled-login --ingroup nginx --no-create-home --home /nonexistent --gecos "nginx user" --shell /bin/false --uid 101 nginx

# Install dependencies
RUN set -x \
    && apt-get update \
    && apt-get install -y \
        libcap2-bin \
        libhyperscan4 \
        rsyslog \
    && rm -rf /var/lib/apt/lists/*


COPY --from=nginx-ingress /nginx* /

RUN set -x \
    && mkdir -p /var/lib/nginx /etc/nginx/secrets /etc/nginx/stream-conf.d /var/cache/nginx \
    && mkdir -p /var/lib/openresty /var/run/openresty /var/cache/openresty \
    && ln -sf /usr/local/openresty/nginx/sbin/nginx /usr/sbin/nginx \
    && ln -sf /usr/local/openresty/nginx/conf/* /etc/nginx/ \
  	&& chown -R nginx:0 /etc/nginx /etc/nginx/secrets /var/cache/nginx /var/lib/nginx /nginx* \
    && chown -R nginx:0 /var/lib/openresty /var/run/openresty /var/cache/openresty /usr/local/openresty \
	  && setcap 'cap_net_bind_service=+ep' /usr/local/openresty/nginx/sbin/nginx \
  	&& setcap -v 'cap_net_bind_service=+ep' /usr/local/openresty/nginx/sbin/nginx  \
  	&& rm -f /etc/nginx/conf.d/* \
    && mkdir -p /var/lib/syslog \
    && touch /var/log/syslog \
	  && setcap 'cap_net_bind_service=+ep' /usr/sbin/rsyslogd  \
  	&& setcap -v 'cap_net_bind_service=+ep' /usr/sbin/rsyslogd  \
    && chown -R nginx:0 /var/lib/syslog /var/log/syslog

RUN set -x \
    && sed -i "/^http {/a log_format curiefenselog escape=none '\$request_map';" /nginx.tmpl \
    && sed -i "/^http {/a map \$status \$request_map { default '-'; }" /nginx.tmpl \
    && sed -i "/^http {/a lua_package_path '/lua/?.lua;;';" /nginx.tmpl


COPY --from=curiefense-source /usr/local/src/curiefense/curiefense/curieproxy/lua/shared-objects/*.so /usr/local/lib/lua/5.1/
COPY --from=rustbin /root/curiefense.so /usr/local/lib/lua/5.1/

COPY --from=curiefense-source /usr/local/src/curiefense/curiefense/curieproxy/config /bootstrap-config/config
COPY --from=curiefense-source /usr/local/src/curiefense/curiefense/curieproxy/lua /lua
RUN rm -f /lua/session.lua && ln -s /lua/session_nginx.lua /lua/session.lua

# Initial configuration (will be overwritten by empty dir)
RUN set -x \
    && mkdir -p /config \
    && chmod a+rwxt /config \
    && cp -va /bootstrap-config /config/bootstrap \
    && ln -s /config/bootstrap /config/current

ENTRYPOINT ["/curiefense-nginx.sh"]

COPY curiefense-nginx.sh /curiefense-nginx.sh
COPY rsyslog.conf /etc/rsyslog.conf
COPY nginx.ingress.tmpl /

#!/bin/bash

rsyslogd -n -iNONE &

/nginx-ingress "$@"

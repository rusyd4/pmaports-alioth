#!/bin/sh
export LD_LIBRARY_PATH=/usr/local/lib/tqftpserv:${LD_LIBRARY_PATH:-}
exec /usr/local/lib/tqftpserv/ld-musl-aarch64.so.1 --library-path /usr/local/lib/tqftpserv /usr/local/bin/tqftpserv -d

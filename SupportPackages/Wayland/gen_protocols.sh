#!/bin/sh

PROTOCOL_DIR=`pkg-config wayland-protocols --variable=pkgdatadir`

wayland-scanner private-code ${PROTOCOL_DIR}/stable/xdg-shell/xdg-shell.xml Sources/protocols/xdg-shell-private.c
wayland-scanner client-header ${PROTOCOL_DIR}/stable/xdg-shell/xdg-shell.xml Sources/protocols/xdg-shell-client.h

wayland-scanner private-code ${PROTOCOL_DIR}/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml Sources/protocols/xdg-decoration-private.c
wayland-scanner client-header ${PROTOCOL_DIR}/unstable/xdg-decoration/xdg-decoration-unstable-v1.xml Sources/protocols/xdg-decoration-client.h

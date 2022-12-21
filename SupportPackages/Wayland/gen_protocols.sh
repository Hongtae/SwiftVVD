#!/bin/sh

PROTOCOL_DIR=`pkg-config wayland-protocols --variable=pkgdatadir`

wayland-scanner private-code ${PROTOCOL_DIR}/stable/xdg-shell/xdg-shell.xml Sources/xdg-shell-protocol.c
wayland-scanner client-header ${PROTOCOL_DIR}/stable/xdg-shell/xdg-shell.xml Sources/xdg-shell-client-protocol.h

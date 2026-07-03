#!/bin/bash

set -e

# Create bin directory
mkdir -p "$PREFIX/bin"

# Replace shebang and install tkload script
sed "1s|^#!/usr/bin/env wish|#!$PREFIX/bin/wish|" tkload.tcl > "$PREFIX/bin/tkload"
chmod 755 "$PREFIX/bin/tkload"

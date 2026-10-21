#!/bin/sh
# Build the AudioReach topology of the tapas sound card (topology/*.m4) with
# the macros of linux-msm/audioreach-topology. Needs git, m4 and alsatplg
# (alsa-utils).
#   mktplg.sh <repo>/topology <firmware dir>   -> <fw>/qcom/sm4250/SM6225-Tapas-tplg.bin
set -e
SRC=$1 FW=$2
REV=d6bb205aca5f4b8fa6b2f44cf8b5f6a081cbf037
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
git -C "$T" init -q ar
git -C "$T/ar" fetch -q --depth 1 https://github.com/linux-msm/audioreach-topology "$REV"
git -C "$T/ar" checkout -q FETCH_HEAD
mkdir -p "$FW/qcom/sm4250"
# The card's driver name (qcom,qrb4210-rb2-sndcard) and model
(cd "$T/ar" && m4 -I . "$SRC/SM6225-Tapas.m4") >"$T/SM6225-Tapas.conf"
# "undefined sink/source widget" for the codec DMA ports is expected: the
# kernel's q6apm-lpass-dais provide those streams
alsatplg -c "$T/SM6225-Tapas.conf" -o "$FW/qcom/sm4250/SM6225-Tapas-tplg.bin"

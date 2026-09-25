#!/bin/bash
# Collect ImageBuilder output into the official ImmortalWrt armsr-armv8 artifact set:
#   *-squashfs-combined-efi.img.gz
#   *-squashfs-combined-efi.qcow2
#   *-squashfs-combined-efi.vmdk
#   *-ext4-combined-efi.qcow2.gz
#   *-ext4-combined-efi.vmdk.gz
#
# OpenWrt only gzip-compresses ext4 VM disks (see include/image.mk GZ_SUFFIX).
# Squashfs qcow2/vmdk stay uncompressed. This script also gunzips/gzips or
# converts from combined-efi.img.gz when ImageBuilder omitted a format.
set -euo pipefail

SRC="${1:?usage: prepare-qemu-images.sh <imagebuilder-bin-dir> <dest-dir>}"
DST="${2:?usage: prepare-qemu-images.sh <imagebuilder-bin-dir> <dest-dir>}"

mkdir -p "$DST"
shopt -s nullglob

latest() {
  local files=() f
  for f in "$@"; do
    [[ -f "$f" ]] && files+=("$f")
  done
  if ((${#files[@]} == 0)); then
    return 1
  fi
  ls -1t "${files[@]}" | head -n1
}

copy_as() {
  local src="$1" dest="$2"
  cp -f "$src" "$dest"
  echo "copied $(basename "$src") -> $(basename "$dest")"
}

ensure_qemu_img() {
  if command -v qemu-img >/dev/null 2>&1; then
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y qemu-utils
  fi
  command -v qemu-img >/dev/null 2>&1
}

convert_from_raw_gz() {
  local img_gz="$1" out="$2" fmt="$3"
  if ! ensure_qemu_img; then
    echo "error: qemu-img is required to convert $(basename "$img_gz") -> $(basename "$out")" >&2
    return 1
  fi
  local tmp
  tmp="$(mktemp --suffix=.img)"
  gzip -dc "$img_gz" > "$tmp"
  qemu-img convert -f raw -O "$fmt" "$tmp" "$out"
  rm -f "$tmp"
  echo "converted $(basename "$img_gz") -> $(basename "$out") ($fmt)"
}

echo "ImageBuilder artifacts in $SRC:"
ls -lh "$SRC" || true

sq_img="$(latest "$SRC"/*-squashfs-combined-efi.img.gz || true)"
if [[ -z "${sq_img}" ]]; then
  echo "error: missing *-squashfs-combined-efi.img.gz" >&2
  exit 1
fi
copy_as "$sq_img" "$DST/$(basename "$sq_img")"

prepare_uncompressed() {
  local fs="$1" ext="$2" img_gz="$3"
  local plain gz dest
  plain="$(latest "$SRC"/*-"${fs}"-combined-efi."${ext}" || true)"
  gz="$(latest "$SRC"/*-"${fs}"-combined-efi."${ext}".gz || true)"
  if [[ -n "$plain" ]]; then
    dest="$DST/$(basename "$plain")"
    copy_as "$plain" "$dest"
    return 0
  fi
  if [[ -n "$gz" ]]; then
    dest="$DST/$(basename "$gz" .gz)"
    gzip -dc "$gz" > "$dest"
    echo "gunzipped $(basename "$gz") -> $(basename "$dest")"
    return 0
  fi
  if [[ -n "$img_gz" ]]; then
    dest="$DST/$(basename "$img_gz" .img.gz).${ext}"
    convert_from_raw_gz "$img_gz" "$dest" "$ext"
    return 0
  fi
  echo "error: cannot produce ${fs} ${ext}" >&2
  return 1
}

prepare_gzipped() {
  local fs="$1" ext="$2" img_gz="$3"
  local gz plain dest tmp
  gz="$(latest "$SRC"/*-"${fs}"-combined-efi."${ext}".gz || true)"
  plain="$(latest "$SRC"/*-"${fs}"-combined-efi."${ext}" || true)"
  if [[ -n "$gz" ]]; then
    dest="$DST/$(basename "$gz")"
    copy_as "$gz" "$dest"
    return 0
  fi
  if [[ -n "$plain" ]]; then
    dest="$DST/$(basename "$plain").gz"
    gzip -c -9n "$plain" > "$dest"
    echo "gzipped $(basename "$plain") -> $(basename "$dest")"
    return 0
  fi
  if [[ -n "$img_gz" ]]; then
    tmp="$(mktemp --suffix=".${ext}")"
    convert_from_raw_gz "$img_gz" "$tmp" "$ext"
    dest="$DST/$(basename "$img_gz" .img.gz).${ext}.gz"
    gzip -c -9n "$tmp" > "$dest"
    rm -f "$tmp"
    echo "gzipped converted ${ext} -> $(basename "$dest")"
    return 0
  fi
  echo "error: cannot produce ${fs} ${ext}.gz" >&2
  return 1
}

prepare_uncompressed squashfs qcow2 "$sq_img"
prepare_uncompressed squashfs vmdk "$sq_img"

ext_img="$(latest "$SRC"/*-ext4-combined-efi.img.gz || true)"
prepare_gzipped ext4 qcow2 "${ext_img}"
prepare_gzipped ext4 vmdk "${ext_img}"

echo "Release artifacts in $DST:"
ls -lh "$DST"

missing=0
for pattern in \
  "*-squashfs-combined-efi.img.gz" \
  "*-squashfs-combined-efi.qcow2" \
  "*-squashfs-combined-efi.vmdk" \
  "*-ext4-combined-efi.qcow2.gz" \
  "*-ext4-combined-efi.vmdk.gz"
do
  if ! latest "$DST"/$pattern >/dev/null; then
    echo "error: missing required artifact $pattern" >&2
    missing=1
  fi
done
# Reject squashfs VM disks that were left gzipped.
if latest "$DST"/*-squashfs-combined-efi.qcow2.gz >/dev/null 2>&1; then
  echo "error: squashfs qcow2 must be uncompressed (not .qcow2.gz)" >&2
  missing=1
fi
if latest "$DST"/*-squashfs-combined-efi.vmdk.gz >/dev/null 2>&1; then
  echo "error: squashfs vmdk must be uncompressed (not .vmdk.gz)" >&2
  missing=1
fi
exit "$missing"

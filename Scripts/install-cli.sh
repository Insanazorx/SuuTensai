#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
rigor_prefix="${RIGOR_PREFIX:-$HOME/.local}"
rigor_configuration=release
rigor_build_only=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) rigor_prefix="${2:?--prefix bir dizin gerektirir}"; shift 2 ;;
        --configuration) rigor_configuration="${2:?--configuration debug veya release gerektirir}"; shift 2 ;;
        --build-only) rigor_build_only=true; shift ;;
        -h|--help)
            printf 'Kullanım: ./install.sh cli [--prefix DİZİN] [--configuration debug|release] [--build-only]\n'
            exit 0 ;;
        *) printf 'Bilinmeyen seçenek: %s\n' "$1" >&2; exit 2 ;;
    esac
done
[[ "$rigor_configuration" == debug || "$rigor_configuration" == release ]] || { printf 'Geçersiz derleme yapılandırması.\n' >&2; exit 2; }
rigor_require swift
bash "$rigor_root/Scripts/build.sh" "$rigor_configuration"
rigor_binary="$rigor_root/.build/$rigor_configuration/SuuTensai"
[[ -x "$rigor_binary" ]] || { printf 'CLI build çıktısı bulunamadı.\n' >&2; exit 1; }
rigor_artifact="$rigor_root/.build/artifacts/cli"
mkdir -p "$rigor_artifact"
install -m 755 "$rigor_binary" "$rigor_artifact/rigor"
if [[ "$rigor_build_only" == true ]]; then
    printf 'CLI build: %s\n' "$rigor_artifact/rigor"
    exit 0
fi
mkdir -p "$rigor_prefix/bin"
install -m 755 "$rigor_artifact/rigor" "$rigor_prefix/bin/rigor"
printf 'Kuruldu: %s\nÖrnek: rigor --check Examples/kernel.rigor\n' "$rigor_prefix/bin/rigor"
case ":$PATH:" in
    *":$rigor_prefix/bin:"*) ;;
    *) printf 'Komutun her terminalde çalışması için bu dizini PATH içine ekle: %s\n' "$rigor_prefix/bin" ;;
esac

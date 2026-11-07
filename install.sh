#!/usr/bin/env bash
set -euo pipefail
rigor_root="$(cd "$(dirname "$0")" && pwd)"
case "${1:---help}" in
    cli|vscode|ios)
        rigor_target="$1"
        shift
        exec bash "$rigor_root/Scripts/install-$rigor_target.sh" "$@"
        ;;
    -h|--help)
        cat <<'HELP'
SuuTensai / Rigor kurulumu

  ./install.sh cli                   Release CLI'yi ~/.local/bin/rigor olarak kur
  ./install.sh vscode                Checker'ı derle ve VS Code eklentisini kur
  ./install.sh ios                   İmzasız iPhone simülatör build'i hazırla
  ./install.sh ios --device auto --install --run
                                    Bağlı iPhone'a imzalı build kur ve aç

Her hedefin seçenekleri: ./install.sh <hedef> --help
HELP
        ;;
    *) printf 'Bilinmeyen hedef: %s\n' "$1" >&2; exit 2 ;;
esac

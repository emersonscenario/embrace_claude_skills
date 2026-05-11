#!/bin/bash
# analisa-coredump.sh — Abre core dump Embrace2 com o GDB da toolchain Buildroot
#
# Uso interativo:
#   ./analisa-coredump.sh <core-dump> <diretorio-debug>
#
# Uso com exportação (batch, para enviar a uma IA):
#   ./analisa-coredump.sh <core-dump> <diretorio-debug> --export [arquivo.txt]
#   Se o arquivo não for especificado, salva em <nome-do-core>.gdb.txt no dir atual.
#
# Exemplos:
#   ./analisa-coredump.sh ~/analise/core.Embrace2Application.1234.11.1700000000 \
#                         ~/Embrace2_debug/Aplicacao/v1.2.0/ARM
#
#   ./analisa-coredump.sh ~/analise/core.Dispatcher.612.11.1777915081 \
#                         ~/Embrace2_debug/Aplicacao/v2.0.0.11/ARM --export

set -euo pipefail

CORE="${1:?Uso: $0 <core-dump> <diretorio-debug> [--export [arquivo.txt]]}"
DEBUG_DIR="${2:?Uso: $0 <core-dump> <diretorio-debug> [--export [arquivo.txt]]}"

# Parse --export flag e arquivo de saída opcional
EXPORT_MODE=false
EXPORT_FILE=""
for arg in "${@:3}"; do
    if [ "$arg" = "--export" ]; then
        EXPORT_MODE=true
    elif [ "$EXPORT_MODE" = true ] && [ -z "$EXPORT_FILE" ] && [[ "$arg" != --* ]]; then
        EXPORT_FILE="$arg"
    fi
done

if [ "$EXPORT_MODE" = true ] && [ -z "$EXPORT_FILE" ]; then
    EXPORT_FILE="$(basename "$CORE").gdb.txt"
fi

if [ ! -f "$CORE" ]; then
    echo "ERRO: core dump não encontrado: $CORE"
    exit 1
fi
if [ ! -d "$DEBUG_DIR" ]; then
    echo "ERRO: diretório de debug não encontrado: $DEBUG_DIR"
    exit 1
fi

# ── Detectar arquitetura pelo core dump ──────────────────────────────────────
ARCH_INFO=$(file "$CORE")
if echo "$ARCH_INFO" | grep -qi "ARM"; then
    GDB="/opt/output-arm/host/bin/arm-buildroot-linux-gnueabihf-gdb"
    SYSROOT="/opt/output-arm/host/arm-buildroot-linux-gnueabihf/sysroot"
    ARCH_LABEL="ARM"
elif echo "$ARCH_INFO" | grep -qi "x86-64"; then
    GDB="/opt/output-x86/host/bin/x86_64-buildroot-linux-gnu-gdb"
    SYSROOT="/opt/output-x86-full/host/x86_64-buildroot-linux-gnu/sysroot"
    ARCH_LABEL="x86-64"
elif echo "$ARCH_INFO" | grep -qi "Intel 80386"; then
    GDB="/opt/output-x86/host/bin/x86_64-buildroot-linux-gnu-gdb"
    SYSROOT="/opt/output-x86-full/host/x86_64-buildroot-linux-gnu/sysroot"
    ARCH_LABEL="x86-32"
else
    echo "ERRO: arquitetura não reconhecida no core dump."
    echo "  $ARCH_INFO"
    exit 1
fi

if [ ! -x "$GDB" ]; then
    echo "ERRO: GDB da toolchain não encontrado: $GDB"
    echo "  Verifique se o output Buildroot está em /opt/output-arm/ ou /opt/output-x86/"
    exit 1
fi

# ── Localizar o executável principal ─────────────────────────────────────────
# Tenta extrair o nome do executável do próprio core dump
EXE_NAME=$(file "$CORE" 2>/dev/null | grep -oP "execfn: '[^']+'" | cut -d"'" -f2 | xargs -I{} basename {} 2>/dev/null || true)

# Fallback: nome do arquivo core → core.<exe>.<pid>.<sig>.<ts>
if [ -z "$EXE_NAME" ]; then
    EXE_NAME=$(basename "$CORE" | cut -d. -f2)
fi

# Buscar o executável no diretório de debug (sem extensão .debug)
EXE_PATH=$(find "$DEBUG_DIR" -name "$EXE_NAME" ! -name "*.debug" -type f 2>/dev/null | head -1)

if [ -z "$EXE_PATH" ]; then
    echo "⚠️  Executável '$EXE_NAME' não encontrado em: $DEBUG_DIR"
    echo ""
    echo "   Binários ELF disponíveis:"
    find "$DEBUG_DIR" -type f ! -name "*.debug" -print0 \
        | xargs -0 file 2>/dev/null | grep -E ":\s+ELF" | sed -E "s|${DEBUG_DIR}/||; s|:[[:space:]]+ELF.*||"
    echo ""
    read -rp "   Digite o caminho completo do executável: " EXE_PATH
    if [ ! -f "$EXE_PATH" ]; then
        echo "ERRO: arquivo não encontrado: $EXE_PATH"
        exit 1
    fi
fi

# ── Construir solib-search-path com todos os subdirs ─────────────────────────
# GDB não faz busca recursiva — enumeramos todos os diretórios manualmente.
# Inclui o sysroot da toolchain para resolver libs do sistema (libc, libstdc++, etc).
SOLIB_PATH=$(find "$DEBUG_DIR" -type d | tr '\n' ':')
if [ -d "$SYSROOT/lib" ];    then SOLIB_PATH="${SOLIB_PATH}${SYSROOT}/lib:"; fi
if [ -d "$SYSROOT/usr/lib" ]; then SOLIB_PATH="${SOLIB_PATH}${SYSROOT}/usr/lib:"; fi
SOLIB_PATH="${SOLIB_PATH%:}"  # remove trailing colon

# ── Resumo antes de abrir ────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Core dump:  $CORE"
echo "  Executável: $EXE_PATH"
echo "  Debug dir:  $DEBUG_DIR"
echo "  GDB:        $GDB  ($ARCH_LABEL)"
echo "  Sysroot:    $SYSROOT"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Comandos úteis dentro do GDB:"
echo "    bt                        → stack trace do crash"
echo "    thread apply all bt full  → stack de todas as threads"
echo "    frame N                   → ir para frame N"
echo "    info locals               → variáveis locais do frame atual"
echo "    list                      → código-fonte ao redor do crash"
echo "    info registers            → registradores no momento do crash"
echo "    q                         → sair"
echo ""

# ── Abrir GDB ────────────────────────────────────────────────────────────────
if [ "$EXPORT_MODE" = true ]; then
    echo "📄 Exportando análise para: $EXPORT_FILE"
    echo ""

    "$GDB" \
        -batch \
        -ex "set sysroot ${SYSROOT}" \
        -ex "set solib-search-path ${SOLIB_PATH}" \
        -ex "set print pretty on" \
        -ex "set pagination off" \
        -ex "info sharedlibrary" \
        -ex "info threads" \
        -ex "thread apply all bt full" \
        -ex "info registers" \
        "$EXE_PATH" "$CORE" 2>&1 | tee "$EXPORT_FILE"

    echo ""
    echo "✅ Salvo em: $(realpath "$EXPORT_FILE")"
else
    "$GDB" \
        -ex "set sysroot ${SYSROOT}" \
        -ex "set solib-search-path ${SOLIB_PATH}" \
        -ex "set print pretty on" \
        -ex "set pagination off" \
        "$EXE_PATH" "$CORE"
fi

# Guia: Analisando Core Dumps do Embrace2

## Visão Geral

Quando o Monitor ou o Firmware crasha, o kernel grava um core dump em `/data/coredumps/`
no dispositivo. Os arquivos `.debug` correspondentes ficam no runner CI em `~/Embrace2_debug/`.

---

## Onde ficam os arquivos

### No dispositivo (após crash)
```
/data/coredumps/core.<exe>.<pid>.<sinal>.<timestamp>
```
Exemplo: `core.Embrace2Application.1234.11.1700000000`

### No runner CI (`~/Embrace2_debug/`)
```
Embrace2_debug/
  Aplicacao/
    v<VERSAO>/
      ARM/                    ← binários stripped + .debug (firmware ARM)
        Embrace2Application
        Embrace2Application.debug
        lib/libCore.so
        lib/libCore.so.debug
        ...
      x86/                    ← idem para x86
  Monitor/
    v<VERSAO>/ARM|x86/        ← monitor release
    os-v<VERSAO>/ARM|x86/     ← monitor via buildroot CI
  releases/
    Aplicacao/<branch>/ARM|x86/   ← branch-release
    Monitor/<branch>/ARM|x86/     ← branch-release
```

---

## GDB da Toolchain

Use o **GDB da toolchain Buildroot** — ele foi compilado exatamente para a distro alvo:

| Alvo | GDB |
|------|-----|
| ARM (BananaPi) | `/opt/output-arm/host/bin/arm-buildroot-linux-gnueabihf-gdb` |
| x86 | `/opt/output-x86/host/bin/x86_64-buildroot-linux-gnu-gdb` |

> **Não use** o `gdb` ou `gdb-multiarch` do sistema — ele desconhece a libc e as bibliotecas
> específicas da sua distro Buildroot.

---

## Passo a Passo

### 1. Obter o core dump do dispositivo
```bash
scp root@<ip-dispositivo>:/data/coredumps/core.Embrace2Application.* ~/analise/
```

### 2. Identificar a versão que estava rodando
```bash
# O timestamp no nome do core (último campo) → converter para data:
date -d @1700000000

# Cruzar com os logs do dispositivo:
scp root@<ip>:/LOGS/firmware_embrace.log ~/analise/
```

### 3. Localizar o diretório de debug correto
```bash
# Para firmware ARM — release:
ls ~/Embrace2_debug/Aplicacao/

# Para firmware ARM — branch-release:
ls ~/Embrace2_debug/releases/Aplicacao/
```

### 4. Usar o script de análise
```bash
./analisa-coredump.sh ~/analise/core.Embrace2Application.1234.11.1700000000 \
                      ~/Embrace2_debug/Aplicacao/v1.2.0/ARM
```
O script detecta automaticamente a arquitetura, localiza o executável e configura
o `solib-search-path` para todos os `.so` e seus `.debug` correspondentes.

---

## Comandos GDB Úteis

```gdb
# Stack trace do crash
(gdb) bt

# Stack de todas as threads
(gdb) thread apply all bt full

# Navegar para um frame específico e ver variáveis locais
(gdb) frame 3
(gdb) info locals
(gdb) info args

# Ver código-fonte ao redor do crash (requer .debug com DWARF)
(gdb) list

# Ver registradores no momento do crash
(gdb) info registers

# Ver o sinal que causou o crash
(gdb) info signals

# Inspecionar memória
(gdb) x/10x $sp          # 10 words na stack pointer
(gdb) x/s 0xABCD1234     # string em endereço
```

---

## Como o GDB localiza os .debug

Cada binário stripped contém uma seção `.gnu_debuglink` com o **basename** do arquivo
`.debug`. O GDB procura automaticamente:
1. Mesmo diretório do binário → `libCore.so.debug` ✓
2. Subdiretório `.debug/` → `libCore.so/.debug/libCore.so.debug`

Por isso o script coloca tudo (stripped + .debug) no **mesmo diretório** e o GDB
resolve os símbolos de cada `.so` automaticamente sem configuração extra.

---

## Sinal de Crash → Causa Provável

| Sinal | Causa |
|-------|-------|
| SIGSEGV (11) | Acesso a memória inválida (null ptr, buffer overflow) |
| SIGABRT (6) | `assert()` falhou, `std::terminate()`, `abort()` |
| SIGFPE (8) | Divisão por zero, overflow de ponto flutuante |
| SIGBUS (7) | Acesso a memória desalinhada |
| SIGILL (4) | Instrução inválida (corrupção de código/stack) |
| SIGKILL (9) | OOM killer — sem core dump gerado |

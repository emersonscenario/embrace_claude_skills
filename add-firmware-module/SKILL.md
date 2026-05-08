---
name: add-firmware-module
description: Use when adding a new firmware module (or library under Bibliotecas/) to ~/Projects/aplicacao_ac/. Covers picking the right category (project module vs firmware/driver module vs library), file scaffold (Module.h/.cpp, ModuleVersion.h, DAOModule.h/.cpp, GeradorHandlersModule.h, UtilsModule.h with IDs enum), CMake registration with add_library + install destination, the per-module triplet (connectors, timers, modular payload), Logs i18n keys, deploy.sh push, test scaffold, and AC3_Docs entry.
---

# add-firmware-module

## Overview

Every firmware module in `aplicacao_ac` is a **shared library** declared in the root `CMakeLists.txt` and dropped onto the device under `/data/Firmware/.../<Module>/<Module>.so` (debug push) or the active `FirmwareA|B/` slot (release). The module class inherits from `ModuloInterpretador` and registers a chain of payload handlers built by a `GeradorHandlers<Module>` helper. Each module declares its own **connectors** (the static hooks `GerenciadorLinks` will wire up at runtime), any **timers** it needs (allocated by `GerenciadorTimer`), and the **modular payloads** it produces / consumes through `GerenciadorComunicacaoModular`. For the runtime semantics see → `firmware-module-communication`.

## Step 1 — Pick the category

| Category | Where it lives | Install destination | Examples |
|---|---|---|---|
| **Project module** (user-instantiable in `Projeto.db`) | Root dir `<Module>/` | `${DESTINO_MODULOS_PROJETO}/<Module>/` → `/data/Firmware/Projeto/ModulosEmbrace/<Module>/` | Lampada, ArCondicionado, Cortina, EntradaDigital, ModuloAND, RoomControl |
| **Firmware module** (driver-like, infrastructure, one per system) | Root dir `<Module>/` | `${DESTINO_MODULOS_FIRMWARE}/<Module>/` → `/data/Firmware/ModulosFirmware/<Module>/` | DriverEthernet, DriverCloud, DriverGPIO, DriverSerial, EmbraceNTLBuiltin, EmbraceNTLv2, ComunicacaoMonitor |
| **Setup module** (only used during device setup flows) | Root dir `<Module>/` | `${DESTINO_MODULOS_SETUP}/<Module>/` → `/data/Firmware/ModulosSetup/ModulosEmbrace/<Module>/` | SetupDispositivos |
| **Library** (reused by ≥ 2 modules) | `Bibliotecas/<Lib>/` (subdir with own `CMakeLists.txt`) | `${DESTINO_BIBLIOTECAS}` → `/data/Firmware/lib/` | LibCargaFisica, LibKeypad485Padrao, LibCortina, LibEmbrace485, LibNTL |

Decision flow:
1. Is this code reused by 2+ modules? → **library**.
2. Is there exactly one of these at runtime (e.g., a driver bound to hardware)? → **firmware module**.
3. Does the user instantiate this in `Projeto.db` (e.g., "lamp #5", "AC #2")? → **project module**.
4. Only used during initial setup? → **setup module**.

## Step 2 — File scaffold

For a project module named `Foo` (template: copy from `EntradaDigital/` for a simple input-style module, `Lampada/` for a connector-rich module, or `ModuloAND/` for a logic module):

```
Foo/
  Foo.h                       # main class: inherits ModuloInterpretador + SenderPayload<...> mixins
  Foo.cpp                     # implementation
  FooVersion.h                # FOO_{MAJOR,MINOR,PATCH}_VERSION + FOO_MINIMUM_FIRMWARE_VERSION
  DAOFoo.h                    # inherits ModeloBaseModulos; loads from Projeto.db
  DAOFoo.cpp
  GeradorHandlersFoo.h        # static getHandlers(Self&) builds the handler chain
  UtilsFoo.h                  # IDsFoo enum (connector IDs); module-specific helpers
  # Optional, add when needed:
  SQLWarmFoo.{h,cpp}          # DB warm-up (when DAO needs custom SQL preload)
  AlteracoesFoo.h             # project-change handler (when reload needs custom logic)
  HandlersConectoresFoo.h     # split out connector handlers when many
  HandlersModularesFoo.h      # split out modular comm handlers when many
```

### Class skeleton

```cpp
// Foo.h
#ifndef FOO_H
#define FOO_H

#include "../Core/ModuloInterpretador.h"
#include "../Uteis/Interpretadores/SenderPayloadDigital.h"   // pick mixins per capability
#include "../Uteis/Interpretadores/SenderPayloadLink.h"
#include "DAOFoo.h"
#include "GeradorHandlersFoo.h"

using namespace core;
using namespace conectores;
using namespace payload;
using namespace protocoloInterno;

class Foo : public ModuloInterpretador,
            public SenderPayloadLink<Foo>,
            public SenderPayloadDigital<Foo>
{
  private:
    uint32_t m_id{0};
    // ... module state

  public:
    Foo(const DAOFoo &dao)
        : m_id(dao.getID()),
          SenderPayloadLink<Foo>(*this, dao.getLinks()),
          SenderPayloadDigital<Foo>(*this)
    {
        HandlerPayload *handler = GeradorHandlersFoo::getHandlers(*this);
        setPrimeiroHandler(handler);
    }

    void inicializarModulo() override;
    void finalizarModulo() override {}
    // ... module-specific public methods called by handlers
};

#endif
```

### Version header

```cpp
// FooVersion.h
#ifndef FOOVERSION_H
#define FOOVERSION_H

#define FOO_MAJOR_VERSION 0
#define FOO_MINOR_VERSION 1
#define FOO_PATCH_VERSION 0
#define FOO_MINIMUM_FIRMWARE_VERSION "1.52.0.0"   // minimum embrace2 version that supports this module

#include <string>
static const std::string FOO_VERSION =
    std::to_string(FOO_MAJOR_VERSION) + "." +
    std::to_string(FOO_MINOR_VERSION) + "." +
    std::to_string(FOO_PATCH_VERSION);
#endif
```

### DAO

```cpp
// DAOFoo.h
#ifndef DAOFOO_H
#define DAOFOO_H
#include "../Core/ModeloBaseModulos.h"

class DAOFoo : public ModeloBaseModulos
{
  public:
    // module-configurable fields loaded from Projeto.db
    DAOFoo(int id) : ModeloBaseModulos(id, "Foo") {}
    bool carregarDadosFoo();
};
#endif
```

### Connector IDs (`UtilsFoo.h`)

```cpp
// UtilsFoo.h
#ifndef UTILSFOO_H
#define UTILSFOO_H
namespace IDsFoo {
    constexpr int CONEXAO_FISICA = 1;        // each ID identifies a static connector
    constexpr int ACIONAR_SAIDA  = 2;
    // ... add one per connector this module exposes
}
#endif
```

### Handler chain (`GeradorHandlersFoo.h`)

Wire each connector + each modular message:

```cpp
// GeradorHandlersFoo.h
#ifndef GERADORHANDLERSFOO_H
#define GERADORHANDLERSFOO_H

#include "../Core/HandlersPayload/HandlerPayloadBuilder.h"
#include "../Core/HandlersPayload/HandlerPayloadConectorInicializacao.h"
#include "../Core/HandlersPayload/HandlerPayloadDigital.h"
#include "../Core/HandlersPayload/HandlersModulares/HandlerModularConsultaValorAnalogico.h"
#include "UtilsFoo.h"

class GeradorHandlersFoo {
    template <typename FooImpl>
    static HandlerPayload *gerarHandlerComunicacaoModular(FooImpl &foo) {
        HandlerPayloadModularBuilder mod;
        mod.addHandler(new HandlerModularConsultaValorAnalogico<FooImpl>(foo));
        return mod.build();
    }
  public:
    template <typename FooImpl>
    static HandlerPayload *getHandlers(FooImpl &foo) {
        HandlerPayloadBuilder b;
        b.addHandler(new HandlerPayloadConectorInicializacao<FooImpl>(foo));

        auto onAcionar = [&foo](payload::Remetente &r, conectores::Conector &c, bool v) {
            foo.tratarAcionamento(v);
        };
        b.addHandler(new HandlerPayloadDigital(
                FabricaValidacaoConector::obterValidacaoID1(IDsFoo::CONEXAO_FISICA),
                onAcionar));

        b.addHandler(gerarHandlerComunicacaoModular(foo));
        return b.build();
    }
};
#endif
```

This is the **per-module triplet** in code:
- **Connectors** = the `IDsFoo::*` IDs + the `HandlerPayloadDigital` (or `HandlerPayloadAnalogico` / `HandlerPayloadTexto`) chain entries.
- **Timers** = if Foo needs timed behavior, allocate via `GerenciadorTimer` in `inicializarModulo()` and add a `HandlerPayloadTimer<Self>` to the chain. (See `Lampada/` for an example.)
- **Modular payload** = the handlers added via `HandlerPayloadModularBuilder` (`HandlerModularConsultaValorAnalogico`, etc.) and any messages the module *sends* via `SenderPayloadModular<Self>` mixin.

## Step 3 — CMake registration

Add to root `CMakeLists.txt` in the alphabetically-sorted `add_library` block:

```cmake
add_library(Foo SHARED
    Foo/Foo.cpp Foo/Foo.h
    Foo/FooVersion.h
    Foo/GeradorHandlersFoo.h
    Foo/UtilsFoo.h
    Foo/DAOFoo.h Foo/DAOFoo.cpp
    # Foo/SQLWarmFoo.h Foo/SQLWarmFoo.cpp        # if used
    # Foo/AlteracoesFoo.h                         # if used
)
# If Foo uses a library:
# target_link_libraries(Foo PRIVATE LibX LibY)
```

Add the install rule near line ~1370 (project modules) or ~1360 (firmware modules):

```cmake
install(TARGETS Foo LIBRARY DESTINATION ${DESTINO_MODULOS_PROJETO}/Foo/)
# OR for a firmware/driver module:
# install(TARGETS Foo LIBRARY DESTINATION ${DESTINO_MODULOS_FIRMWARE}/Foo/)
```

## Step 4 — Logs hooks

If the module emits events worth logging:

1. **Reserve i18n keys** in `~/Projects/aplicacao_ac/docs/log_i18n_keys.md` — append to the index table (`log.foo.<event>`), then add a per-key section with the JSON `params` schema and the insertion point in the code.
2. **Smart-logs catalog** — add a row to `~/Projects/aplicacao_ac/docs/logs_inteligentes_por_modulo.md` describing what triggers what level (debug/info/warning/error).
3. Use the existing `Logger`/`LoggerFirmware` API in `Foo.cpp`. Don't roll your own logging.

## Step 5 — Build + deploy (debug)

```bash
cd ~/Projects/aplicacao_ac
ARCHITECTURE=ARM cmake -B cmake-build-debug-banana -DCMAKE_BUILD_TYPE=Debug
cmake --build cmake-build-debug-banana -j$(nproc) --target Foo

# Deploy to Banana Pi (debug-only path /data/Firmware/)
./deploy.sh
```

The deploy lands in `/data/Firmware/...` — **debug-only**. Production firmware lives in the *active* `/data/FirmwareA/` or `/data/FirmwareB/` slot (read from `/data/Configuracoes/ConfiguracoesFirmware.scj`). Smoke-test on device knowing it's the dev build.

For x86 dev (laptop or x86 Pro/Full controller):
```bash
ARCHITECTURE=X86 cmake -B build-x86 -DCMAKE_BUILD_TYPE=Debug
cmake --build build-x86 -j$(nproc) --target Foo
```

## Step 6 — Test scaffold

Create `tests/unit/Foo/` mirroring an existing module's test layout. `tests/integration/` for cross-module behavior. Reuse helpers and stubs under `tests/{helpers,stubs}/`. Build with:

```bash
cmake -B build-test -DBUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Debug
cmake --build build-test
ctest --test-dir build-test --output-on-failure
```

## Step 7 — AC3_Docs entry

Add a page describing what the module does, its connectors, and any user-visible config:

```
~/IdeaProjects/AC3_Docs/docs/Embrace2/Modulos/Foo.md
```

Then add it to `mkdocs.yml` `nav:` under the matching category in `Embrace2 → Modulos → ...`. If you'd rather batch the docs work, defer it and run → `embrace-docs` later.

## Common pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Forgot to register the install rule | `Foo.so` not in `/data/Firmware/.../Foo/` after deploy | Add `install(TARGETS Foo LIBRARY DESTINATION ...)` |
| Wrong destination (PROJETO vs FIRMWARE) | Module loads but isn't instantiable / vice versa | Re-check the category table |
| Missing connector ID in `IDsFoo` | Link from `Projeto.db` doesn't bind anywhere → silent no-op | Add the ID, register a `HandlerPayloadDigital`/`Analogico`/`Texto` handler |
| Timer allocated but no handler in chain | Timer fires, nothing happens | Add `HandlerPayloadTimer<Self>` in `GeradorHandlersFoo` |
| Modular message produced but no destination resolves | Sent message goes nowhere | Verify `GerenciadorComunicacaoModular` translation; check the `SenderPayloadModular` mixin is engaged |
| `FOO_MINIMUM_FIRMWARE_VERSION` not set or too high | Module refuses to load on the target firmware | Set to the real minimum, not the current dev version |
| `add_library` block out of alpha order | Merge conflicts grow over time | Insert in the correct alphabetical position |
| Skipping i18n / smart-logs entry | Logs render as raw keys in the UI | Add to both `log_i18n_keys.md` and `logs_inteligentes_por_modulo.md` |
| Linked against a `Bibliotecas/` lib without `target_link_libraries` | Undefined symbols at load time on device | Add the `target_link_libraries(Foo PRIVATE LibX)` line |

## Cross-references

- → `firmware-module-communication` for the runtime semantics of connectors / links / timers / modular payload — read this BEFORE implementing the handler chain.
- → `embrace-firmware` for the broader codebase context and module taxonomy.
- → `embrace-docs` for the AC3_Docs entry workflow if you defer it.
- → `embrace-buildroot` if the new module needs a kernel option, package, or rootfs overlay change.
- Template modules to copy from: `EntradaDigital/` (simple input), `Lampada/` (connector-heavy), `ModuloAND/` (logic), `EmbraceSensor/` (485 device), `Cortina/` (uses a `Lib*`).

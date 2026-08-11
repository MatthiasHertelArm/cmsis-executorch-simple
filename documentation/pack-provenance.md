# Where the ExecuTorch CMSIS pack comes from

The `PyTorch::ExecuTorch` pack used by this branch is **installed into your
CMSIS pack root**, like any other pack — but it cannot be acquired the way any
other pack is. This branch therefore carries the archive itself, one file under
`packs/`, for `cpackget` to install. This page explains why, how to build a
pack yourself, and how to move to a newer ExecuTorch version.

## Why the archive is committed

Neither normal acquisition route yields a working pack.

**It is not in the public index.** `cpackget add PyTorch::ExecuTorch@1.4.0` has
nothing to resolve — `index.pidx` carries no `PyTorch` vendor entry at all — so
`cbuild --packs` cannot fetch it either, and a build that appears to work is a
build whose pack root already had it.

**The published release asset does not compile.** The `.pdsc` declares its
download location as

```xml
<url>https://github.com/pytorch/executorch/releases/download/v1.4.0/</url>
```

and that URL does serve a pack — but the asset there was built by upstream CI
from a release branch carrying stale pack-build scripts. It ships none of the
generated FlatBuffers/schema headers: `program_generated.h` and
`scalar_type_generated.h` are absent, and so is the bundled
`include/flatbuffers/`, while ten core runtime sources include them. Its
Runtime component cannot compile, so no configuration of that pack builds.

Measured against the copy committed here (as of 2026-08-11):

| | `packs/PyTorch.ExecuTorch.1.4.0.pack` | published `v1.4.0` asset |
|---|---|---|
| sha256 | `29bee68a…` | `089ed734…` |
| size | 1,766,058 B | 1,576,905 B |
| `program_generated.h`, `scalar_type_generated.h` | present | absent |
| bundled `include/flatbuffers/` | 35 entries | none |

### Installing it

```bash
cpackget add -n --agree-embedded-license packs/PyTorch.ExecuTorch.1.4.0.pack
```

`.devcontainer/post-create.sh` runs this. `-n` (`--no-dependencies`) matters:
the pack declares `ARM::CMSIS`, resolving that needs an index a fresh pack root
has not fetched, and `cpackget` then exits 255 *after* installing our pack
correctly — which would abort the bootstrap. Those dependencies are public
packs that `cbuild --packs` installs at build time anyway.

Committing the archive rather than the unpacked pack costs one file instead of
937, and a fifth of the space. It goes away when ExecuTorch publishes a pack
that builds, and indexes it.

The version is pinned exactly, in `cmsis-executorch-simple.csolution.yml` and
`cmsis-executorch-simple.cproject.yml`:

```yaml
packs:
  - pack: PyTorch::ExecuTorch@1.4.0
```

Both must agree. The pin is exact rather than a `@^1.4.0` range because the
pack's C++ runtime and the Python exporter have to be the *same* ExecuTorch
version — see [Moving to a new ExecuTorch version](#moving-to-a-new-executorch-version).

`scripts/gen_components.py` reads the installed pack's `.pdsc` out of the pack
root (`$CMSIS_PACK_ROOT`, or cpackget's default) to find out which operator
components exist. During a build it is told which version to read: the
`convert-model` step picks the resolved version out of
`cmsis-executorch-simple.cbuild-pack.yml`, so a pack root holding several
ExecuTorch versions cannot make it read the wrong one. Run by hand it defaults
to the newest installed version, and `--pack-path` points it at an unpacked
pack directory anywhere on disk.

## What is in the pack

| Path | Contents |
|---|---|
| `PyTorch.ExecuTorch.pdsc` | Component declarations — one component per operator, plus runtime and backend |
| `src/` | ExecuTorch runtime, kernel and Ethos-U backend sources |
| `include/` | Public headers, **including the bundled `include/flatbuffers/`** |
| `armclang_shims/` | Small compatibility shims for Arm Compiler 6 |
| `Documentation/` | Pack README |
| `LICENSE` | Upstream BSD-3-Clause (the example code around it is Apache-2.0) |

It is a **source** pack: nothing is prebuilt. Every operator is a selectable
component, which is what lets `scripts/gen_components.py` narrow the link to
exactly the kernels a given `.pte` needs.

## Building a pack yourself

Worth knowing if you need a version that has no published pack yet, or want to
carry a local ExecuTorch change into the firmware. The generator lives in the
ExecuTorch tree at `backends/arm/cmsis_pack/scripts/build_pack.sh`.

```bash
git clone https://github.com/pytorch/executorch.git
cd executorch
git checkout release/1.4          # or the tag matching your target version
git submodule update --init --recursive
```

> **Run the CMake cross-compile before `build_pack.sh`.**
>
> This is the one trap worth knowing about. If `build_pack.sh` runs without the
> prior cross-compile, it completes successfully but **silently omits**:
>
> - the bundled `include/flatbuffers/` headers, and
> - the flatc-generated `program_generated.h` and `scalar_type_generated.h`.
>
> The resulting pack looks complete and fails at compile time with missing-header
> errors that point nowhere useful. Those two headers are generated with:
>
> ```bash
> flatc --cpp --cpp-std c++11 --gen-mutable --scoped-enums <schema>.fbs
> ```
>
> `flatc` ships inside the executorch wheel — after `./setup_venv.sh` it is at
> `.venv/bin/flatc`.

Then run the generator; the pack lands in `pack-output/`:

```bash
backends/arm/cmsis_pack/scripts/build_pack.sh
```

### Verifying a pack you built

Before trusting a freshly built pack, check the parts that go missing quietly:

```bash
PACK=pack-output/PyTorch.ExecuTorch.<version>

# 1. The bundled flatbuffers headers must be present.
test -d "$PACK/include/flatbuffers" || echo "MISSING: include/flatbuffers"

# 2. The flatc-generated headers must be present.
for h in program_generated.h scalar_type_generated.h; do
    find "$PACK/include" -name "$h" | grep -q . || echo "MISSING: $h"
done

# 3. The component list should still cover the operators the model uses.
grep -c '<component' "$PACK/PyTorch.ExecuTorch.pdsc"
```

A pack that passes all three is safe to install:

```bash
cpackget add pack-output/PyTorch.ExecuTorch.<version>.pack
```

## Moving to a new ExecuTorch version

The pack's C++ runtime and the Python exporter must come from the *same*
ExecuTorch version — a `.pte` produced by a different version than the runtime
that loads it will fail at load time, or worse, at inference time. Four steps,
in order:

1. **Install the new pack** — `cpackget add PyTorch::ExecuTorch@<new>`, or
   build one yourself (above) if the version is not published. On this branch,
   also replace the archive under `packs/` with the new one and update the
   filename in `.devcontainer/post-create.sh`.
2. **Update both pins** — `PyTorch::ExecuTorch@<new>` in the csolution and in
   the cproject.
3. **Update the Python pin** in `requirements-executorch.txt` to the matching
   `executorch` version, and check the new release's `install_requirements.py`
   for the `torch` and `torchao` versions it expects. Update
   `requirements.txt` (torch) accordingly. See the README's
   [Version pinning](../README.md#version-pinning) table for the current set.
4. **Rebuild the venv and the project:**

   ```bash
   ./setup_venv.sh --recreate
   ./build.sh                     # may abort once; see below
   ```

If the new version changes the operator set, the first build stops with the
"operator set changed" notice and rewrites `ai_layer/ai_layer.clayer.yml`.
That is expected — run `./build.sh` again. See
[mlops-flow.md](mlops-flow.md#why-the-clayer-cannot-update-in-place) for why.

Finally, update the version wherever it appears in prose: `README.md`
(Prerequisites, Version pinning) and this page.

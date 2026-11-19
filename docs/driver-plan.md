# Preview a driver plan without changing the loader

From this source tree, use the Python 3 standard-library CLI to answer two questions: **which module files do these requested drivers require, and how does that set differ from my current selection?** It reads local files, prints a proposal and exits. It does not load drivers, edit RR settings, change the existing module menu, download anything, or mark the loader for rebuild.

## Example

From the repository root:

```sh
files/initrd/opt/rr/rrctl plan \
  --catalog docs/modules.json --platform epyc7002-7.4-5.10.55 \
  --root virtio_scsi --root virtio_net --root i915 \
  --selected virtio_scsi --selected virtio_net --explain
```

The two `--selected` names are an example comparison baseline, **not** the complete selection for a real NAS. The proposal includes the shared dependencies of both VirtIO roots; each explanation lists which root(s) need a module and which nodes directly require it. Order and repeated arguments do not change the plan.

- `--root` is what you want to keep; give the complete set of desired roots for a meaningful comparison. **A listed removal only means “not reached from these roots”. It is not advice to remove a storage or network driver.**
- `--selected` and `--selected-file` describe current effective module keys for comparison only. They never disambiguate a dependency. A selection file contains one key per line; an empty file explicitly compares against no existing keys. Without either option, no add/remove diff is generated.
- Both RR catalog formats (`modules.json` and `modules_detailed.json`) are supported. Use the **exact target** platform/version/ABI key and catalog for your bundle. A public catalog is not evidence that an installed **custom** kernel provides those modules; supply matching metadata for a custom bundle. No hardware probe, modalias matching, firmware validation, or install-time original-driver preference is simulated.
- Explain an ambiguity by reviewing available providers, then explicitly add the intended exact provider key as a root, e.g. `--root update/example`. Base and updated modules are distinct; the planner won't silently install both. Use `--builtin NAME` only for an absent provider you have verified is built into the **target** kernel, not the host running this command.
- Add `--json` for machine-readable output. On a valid plan, exit status is 0; otherwise it is nonzero. A resolution error has a diagnostic and **no actionable diff**.

## Compare against an actual selection

On a machine with a copy of the matching catalog and *mikefarah/yq v4*, extract only the module names. Do not publish or upload your full loader configuration:

```sh
(
  set -e
  umask 077
  selected=$(mktemp)
  trap 'rm -f "$selected"' EXIT
  # Fail instead of treating a malformed/absent module map as an empty selection.
  yq -e '.modules | kind == "map"' "$RR_USER_CONFIG" >/dev/null
  yq -r '.modules | keys | .[]' "$RR_USER_CONFIG" > "$selected"
  files/initrd/opt/rr/rrctl plan --catalog "$RR_MODULE_CATALOG" \
    --platform "$RR_TARGET" --root virtio_scsi --root virtio_net \
    --selected-file "$selected" --explain
)
```

Set `RR_USER_CONFIG`, `RR_MODULE_CATALOG`, and `RR_TARGET` explicitly; replace the sample roots with your intended set. In the RR initramfs the tool is `/opt/rr/rrctl`; the documentation catalogs from the source tree are not automatically installed there.

## What changes in the existing configuration editor?

The Settings editor now validates a private draft. Canceling or making no changes leaves the active file, build flag and boot artifacts alone. Invalid YAML reopens the rejected draft for correction. A changed, valid draft is renamed into place on the same filesystem after a check that the original bytes have not changed. The normal rebuild behavior for successful edits is retained.

The check accepts one YAML map with unique top-level keys. Known mapping fields (cmdline, synoinfo, addons, modules and network) must be maps when present. Identity fields (model, productver, buildnum and sn) must be scalars when present. Unknown extension fields and legacy scalar representations are left alone. This is a structural check, not proof of model/driver compatibility. The editor's stale-file check is not a cross-process lock for unrelated writers or a guarantee against power loss on FAT.

## Regression tests

On a development machine with Bash, Python 3 and mikefarah/yq v4:

```sh
bash tests/test_edit_user_config.sh
python3 -m unittest discover -s tests -p 'test_driver_plan.py' -v
```

The tests use temporary fixtures and public catalog metadata, not production disks or guest hardware.

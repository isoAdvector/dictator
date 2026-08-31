# dictator test suite

```
./test/run_tests.sh
```

Sources `../dictator` and exercises every public entry point
(`dictator`, `getDictEntry`, `setDictEntry`, `listDictEntries`) and the
internal helpers (`_dictHelp`, `_dictator_level`, `_dictator_expand`,
`_dictator_complete`) against the fixtures in `fixtures/`. Every check
prints `ok` or `FAIL <detail>`; a summary and a non-zero exit follow any
failure.

## Why it loops over awks

`dictator` shells out to `awk`, and the dialects disagree in ways that
have already bitten it (a gawk-only line continuation; `mawk`/`busybox`
behaviour on `-v` backslash handling and `index(s, "")`). The suite
therefore runs itself once per awk it can find on the machine — the
ambient `awk`, plus `gawk`, `mawk`, `busybox awk` and `original-awk`
(BWK) when present — by putting a one-line shim on `PATH` and
re-sourcing `dictator`. A green run means all of them agree.

Restrict which are tried with `DICTATOR_TEST_AWKS`:

```
DICTATOR_TEST_AWKS="default gawk" ./test/run_tests.sh
```

## Env knobs

| var       | effect                                          |
|-----------|-------------------------------------------------|
| `QUIET=1` | hide the per-check `ok` lines; show FAIL/notes  |
| `DICTATOR_TEST_AWKS` | space-separated subset of `default gawk mawk busybox bwk` |

## Exit status

| code | meaning                                    |
|------|--------------------------------------------|
| 0    | every check passed under every awk         |
| 1    | at least one check failed                  |
| 2    | harness could not start (missing files)    |

## Fixtures

- `fixtures/system/testDict` — a torture dictionary: packed and split
  entries, list values, nested parens, empty values, a deliberately
  duplicated key, deep sub-dicts, an only-sub-dicts dict, an empty dict,
  regex/quoted solver names, a dot inside quotes, escaped parens in a
  key, line/block comments and `#include` directives.
- `fixtures/system/controlDict` — a small real `controlDict` so the
  `-help` lookup has a `FoamFile.object` scope to resolve against the
  parameter database.

The fixtures are copied to a scratch directory per run; the originals are
never modified.

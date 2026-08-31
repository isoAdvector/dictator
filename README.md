# dictator

Inspect, set and explain OpenFOAM dictionary parameters from the command line,
with tab completion at every position.

Because OpenFOAM dictionaries should be easy to boss around:


![Terminal Demo](dictator.gif)


No OpenFOAM installation is required to use it, and (in contrast to 
foamDictionary) it never reformats your files:
only the value you asked for is rewritten, so comments, layout, blank lines and
full floating point precision all survive.

## Install

```sh
git clone https://github.com/isoAdvector/dictator
echo >> ~/.bashrc && echo ". $PWD/dictator/dictator" >> ~/.bashrc
source ~/.bashrc
```

Then open a new terminal. dictator is a bash script and must be sourced from bash;
it refuses to load in other shells rather than misbehave quietly.

## Tab completion

Completion works at every argument, so you can find a parameter without knowing
where it lives:

```
dictator sys<TAB>                            -> system/
dictator system/cont<TAB>                    -> system/controlDict
dictator system/controlDict <TAB><TAB>       -> lists every parameter
dictator system/controlDict endT<TAB>        -> endTime
dictator system/controlDict endTime <TAB>    -> fills in the current value
dictator system/controlDict endTime -<TAB>   -> -help
dictator system/fvSolution 'solvers."pc<TAB> -> 'solvers."pcorr.*".
dictator $FOAM_TUT<TAB>                      -> $FOAM_TUTORIALS/
```

Paths written with OpenFOAM's environment variables complete as they would
anywhere else in bash, and keep the short `$FOAM_TUTORIALS/...` form on the
command line rather than expanding to the full path.

Sub-dictionaries keep a trailing `.` so TAB steps into them one level at a time.
Names containing `(`, `)` or `*` need quoting: open a quote and TAB as usual, and
the closing quote is added once the name is complete.

## Reading and setting

With two arguments dictator prints a value, with three it sets one:

```sh
dictator system/controlDict endTime         # 0.1
dictator system/controlDict endTime 12      # Set   endTime = 12
dictator system/controlDict banana ripe     # Added banana = ripe
```

Entries are addressed by their full path from the top of the file, with
sub-dictionaries separated by `.`:

```sh
dictator system/fvSchemes ddtSchemes.default "CrankNicolson 0.9"
dictator system/fvSolution 'solvers."alpha.water.*".nAlphaSubCycles' 4
```

A parameter that does not exist yet is added after the last entry of the
dictionary named in the path. The path is taken at face value, so it is your job
to check that a new entry landed where you meant it; the `Added` versus `Set`
message is there to make a typo obvious.

## Parameter documentation

A third argument of `-help` explains the parameter instead of setting it: its
current value, its type, whether the solver requires it, its default, the
permitted options where there are few, and what it means.

```
$ dictator system/controlDict writeControl -help
writeControl  =  adjustable
  word, optional, default timeStep   [controlDict, curated, v2506]
  What writeInterval is counted in. adjustable also nudges the time step so
  writes land on exact intervals.
  options: timeStep | runTime | adjustable | adjustableRunTime | clockTime |
  cpuTime | none
```

A parameter the OpenFOAM sources never read says so, rather than guessing:

```
$ dictator system/fvSchemes ponzi -help
ponzi
  No information. Not a keyword read anywhere in the OpenFOAM v2506 sources,
  so probably added by you, or read by a custom solver or function object.
```

The bracket names the dictionary the description was found in, where it came
from, and the OpenFOAM release it describes, so an answer taken from a different
dictionary is visible as such.

### Where the text comes from

The 5769 records in `dictatorHelp` are generated from an OpenFOAM source tree by

```sh
makeDictatorHelp [openfoamRoot] > dictatorHelp
```

which defaults to `$WM_PROJECT_DIR`. Five extractors read the tree: typed and
untyped dictionary reads give the type, the required flag and the default;
doxygen property tables and the commented templates in `etc/caseDicts/annotated`
give the prose; `Enum` tables give the option lists. Every record keeps the
extractor it came from in its last field.

The core entries of controlDict, fvSolution and fvSchemes, where the sources
state a type but never say what the parameter means, are written by hand and
marked `curated` so that distinction stays visible.

**The shipped database is built from ESI OpenFOAM v2506.** The release is read
from `META-INFO/api-info` and stamped into the file, and `dictator -help` reports
it. If you use the OpenFOAM Foundation line, or another ESI release, some
defaults will differ; regenerate the database against your own tree with
`makeDictatorHelp`.

## The underlying functions

```sh
setDictEntry     <file> <entry.path> <value>   # set one entry
getDictEntry     <file> <entry.path>           # print one entry's value
listDictEntries  <file>                        # print every entry path
```

All three share one parser, which reads the dictionary as a character stream, so
entries and sub-dictionaries may be split across lines or packed onto one,
separated by spaces, tabs or nothing at all. Entries inside `//` or `/* */`
comments are ignored, as are `#include` and other `#directive` lines.

`setDictEntry` does not add a missing entry, reporting it as an error instead;
pass `-add` for dictator's behaviour. Scripts should use `setDictEntry` so that a
mistyped name fails loudly. Removing entries is not supported.

The dictionary dialect is set by the variable `dictSyntax`. Only `openfoam` is
currently defined: entries `key value;` and sub-dictionaries `name { ... }`. The
dialect is six tokens, so another brace-and-terminator format is a one-line
addition; formats that express nesting through indentation, such as YAML, do not
fit this model.

## Tests

```sh
./test/run_tests.sh
```

Sources `dictator` and exercises every entry point and helper against a torture
fixture in `test/fixtures/`: packed and split entries, list values, nested
parentheses, empty values, duplicated keys, deep and quoted sub-dictionaries,
comments and `#include` lines, `-add` placement, formatting preservation,
error paths and exit codes, and the completion function at each argument. Each
check prints `ok` or `FAIL`, with a summary and a non-zero exit on any failure.

`dictator` shells out to `awk`, and the dialects disagree in ways that have bitten
it before, so the whole suite is re-run once per `awk` found on the machine — the
ambient one plus `gawk`, `mawk`, `busybox awk` and `original-awk` when present. A
green run means they all agree. `QUIET=1` hides the passing lines;
`DICTATOR_TEST_AWKS="default gawk"` restricts which are tried. See
[test/README.md](test/README.md).

## See also

[cfdTools](https://github.com/isoAdvector/cfdTools) — `parmScanner`, which builds
and runs a matrix of cases from a base case, using `setDictEntry` from here.

## License

Copyright (C) 2025-2026 Johan Roenby, STROMNING.

dictator is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version. It is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See [LICENSE](LICENSE), or
<https://www.gnu.org/licenses/>, for details.

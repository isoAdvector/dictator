#!/usr/bin/env bash
#
# dictator test suite
# -------------------
# Sources ../dictator and exercises every public entry point (dictator,
# getDictEntry, setDictEntry, listDictEntries) plus the internal helpers
# (_dictHelp, _dictator_level, _dictator_expand, _dictator_complete) against
# the fixtures in test/fixtures/. Each check prints "ok" or "FAIL <detail>";
# a summary and non-zero exit follow any failure.
#
# The whole suite is re-run once per awk implementation found on the machine
# (the ambient awk, plus gawk / mawk / busybox awk / original-awk if present),
# because that is where portability bugs hide. Set DICTATOR_TEST_AWKS to a
# space-separated list of labels to restrict which are tried, e.g.
#
#     DICTATOR_TEST_AWKS="default gawk" ./test/run_tests.sh
#
# Env knobs:  QUIET=1  hide the per-check "ok" lines, show only FAIL/note.
#
# Usage:  ./test/run_tests.sh
#
# Exit:   0 = every check passed under every awk;  1 = something failed;
#         2 = harness could not start (dictator or fixtures missing).

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname -- "$SCRIPT_DIR")"
DICTATOR="$ROOT/dictator"
FIX="$SCRIPT_DIR/fixtures"

[ -f "$DICTATOR" ]            || { echo "run_tests: no dictator at $DICTATOR" >&2; exit 2; }
[ -f "$FIX/system/testDict" ] || { echo "run_tests: no fixtures at $FIX" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dictator-test.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

# --------------------------------------------------------------------------
# assertion helpers  (pass / fail are counters in the enclosing scope)
# --------------------------------------------------------------------------
_ok()  { pass=$((pass + 1)); [ -n "${QUIET:-}" ] || printf '  ok    %s\n' "$1"; }
_bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; shift
         for _l in "$@"; do printf '          %s\n' "$_l"; done; }
note() { printf '  note  %s\n' "$1"; }
section() { [ -n "${QUIET:-}" ] || printf '\n-- %s\n' "$1"; }

eq()           { [ "$2" = "$3" ] && _ok "$1" || _bad "$1" "expected: [$2]" "actual:   [$3]"; }
contains()     { case "$2" in *"$3"*) _ok "$1";; *) _bad "$1" "want substring: [$3]" "in: [$2]";; esac; }
not_contains() { case "$2" in *"$3"*) _bad "$1" "unexpected substring: [$3]" "in: [$2]";; *) _ok "$1";; esac; }
rc_is()        { [ "$2" = "$3" ] && _ok "$1" || _bad "$1" "expected rc $2, got $3"; }

line_present() { printf '%s\n' "$2" | grep -qxF -- "$3" && _ok "$1" || _bad "$1" "missing exact line: [$3]"; }
line_absent()  { printf '%s\n' "$2" | grep -qxF -- "$3" && _bad "$1" "unexpected exact line: [$3]" || _ok "$1"; }
line_count()   { c=$(printf '%s\n' "$3" | grep -cxF -- "$4"); [ "$c" = "$2" ] && _ok "$1" || _bad "$1" "expected $2 lines [$4], got $c"; }

in_reply()     { for _x in "${COMPREPLY[@]}"; do [ "$_x" = "$2" ] && { _ok "$1"; return; }; done
                 _bad "$1" "COMPREPLY lacks [$2]" "got: ${COMPREPLY[*]}"; }
reply_suffix() { for _x in "${COMPREPLY[@]}"; do case "$_x" in *"$2") { _ok "$1"; return; };; esac; done
                 _bad "$1" "no COMPREPLY entry ends with [$2]" "got: ${COMPREPLY[*]}"; }
reply_min()    { [ "${#COMPREPLY[@]}" -ge "$2" ] && _ok "$1" || _bad "$1" "expected >= $2 replies, got ${#COMPREPLY[@]}"; }

# run a command, capturing stdout in OUT, stderr in ERR, status in RC
run() { OUT="$("$@" 2>"$WORK/err")"; RC=$?; ERR="$(cat "$WORK/err")"; }

# a clean copy of the fixtures; echoes the case directory
fresh() {
    rm -rf "$WORK/case"; mkdir -p "$WORK/case/system"
    cp "$FIX/system/testDict" "$FIX/system/controlDict" "$FIX/system/fvSolution" \
       "$WORK/case/system/" || exit 2
    printf '%s' "$WORK/case"
}

# drive the completion function; fills COMPREPLY
complete_at() {
    COMP_LINE="$1"; COMP_POINT="${#1}"; COMPREPLY=()
    _dictator_complete
}

# ========================================================================
# the suite proper
# ========================================================================
run_suite() {
    local C f list lvl d
    C="$(fresh)"; f="$C/system/testDict"

    section "sourcing"
    eq   "dictator() defined"        function "$(type -t dictator)"
    eq   "getDictEntry() defined"    function "$(type -t getDictEntry)"
    eq   "setDictEntry() defined"    function "$(type -t setDictEntry)"
    eq   "listDictEntries() defined" function "$(type -t listDictEntries)"
    eq   "_DICTATOR_DIR points at repo" "$ROOT" "$_DICTATOR_DIR"

    section "getDictEntry - plain values"
    run getDictEntry "$f" scalarEntry ; rc_is "scalarEntry rc" 0 "$RC"; eq "scalarEntry" 3.14159 "$OUT"
    run getDictEntry "$f" wordEntry   ; eq "wordEntry"   kOmegaSST "$OUT"
    run getDictEntry "$f" switchEntry ; eq "switchEntry" yes       "$OUT"
    run getDictEntry "$f" commentedValue ; eq "trailing // comment stripped from value" 42 "$OUT"

    section "getDictEntry - list values"
    run getDictEntry "$f" emptyList ; eq "emptyList" "( )" "$OUT"
    run getDictEntry "$f" intList   ; eq "intList"   "( 1 2 3 4 )" "$OUT"
    run getDictEntry "$f" multiLineList
    case "$OUT" in "("*) _ok "multiLineList starts with (";; *) _bad "multiLineList starts with (" "[$OUT]";; esac
    contains "multiLineList keeps interior" "$OUT" "0.2"
    run getDictEntry "$f" subDict.interp ; eq "nested parens in value" "table ( (0 1) (1 2) )" "$OUT"

    section "getDictEntry - layout quirks"
    run getDictEntry "$f" packedA ; eq "packed line, 1st" 1 "$OUT"
    run getDictEntry "$f" packedB ; eq "packed line, 2nd" 2 "$OUT"
    run getDictEntry "$f" packedC ; eq "packed line, 3rd" 3 "$OUT"
    run getDictEntry "$f" splitEntry ; eq "value on next line" splitValue "$OUT"
    run getDictEntry "$f" noValueEntry ; rc_is "empty-value entry rc" 0 "$RC"; eq "empty-value entry" "" "$OUT"

    section "getDictEntry - nested paths"
    run getDictEntry "$f" subDict.alpha             ; eq "subDict.alpha" 0.5 "$OUT"
    run getDictEntry "$f" subDict.beta              ; eq "subDict.beta"  1.5 "$OUT"
    run getDictEntry "$f" subDict.nested.gamma      ; eq "two levels deep"   2.5 "$OUT"
    run getDictEntry "$f" subDict.nested.deep.delta ; eq "three levels deep" 3.5 "$OUT"
    run getDictEntry "$f" onlySubDicts.inner.x      ; eq "inside only-subdict dict" 10 "$OUT"

    section "getDictEntry - quoted keys"
    run getDictEntry "$f" 'solvers."(U|k|epsilon)".solver'         ; eq "regex key, solver"         PBiCGStab "$OUT"
    run getDictEntry "$f" 'solvers."(U|k|epsilon)".preconditioner' ; eq "regex key, preconditioner" DILU "$OUT"
    run getDictEntry "$f" 'solvers."(U|k|epsilon)".tolerance'      ; eq "regex key, tolerance"      1e-08 "$OUT"
    run getDictEntry "$f" 'solvers."alpha.water.*".nAlphaCorr'     ; eq "dot inside quotes, 1"      2 "$OUT"
    run getDictEntry "$f" 'solvers."alpha.water.*".cAlpha'         ; eq "dot inside quotes, 2"      1 "$OUT"
    run getDictEntry "$f" solvers.p.solver                         ; eq "plain key beside quoted ones" PCG "$OUT"
    run getDictEntry "$f" solvers.p.relTol                         ; eq "solvers.p.relTol"          0.05 "$OUT"
    run getDictEntry "$f" divSchemes.default                       ; eq "divSchemes.default"        none "$OUT"
    run getDictEntry "$f" 'divSchemes."div\(phi,alpha\)"'          ; eq "escaped parens in key"     "Gauss vanLeer" "$OUT"

    section "getDictEntry - the FoamFile header"
    run getDictEntry "$f" FoamFile.object  ; eq "FoamFile.object readable by name" testDict "$OUT"
    run getDictEntry "$f" FoamFile.version ; eq "FoamFile.version readable by name" 2.0 "$OUT"

    section "getDictEntry - error paths"
    run getDictEntry "$f" noSuchKey ; rc_is "missing key rc" 1 "$RC"; contains "missing key message" "$ERR" "not found"
    contains "missing key names the file" "$ERR" "in file:"
    run getDictEntry "$f" dupKey ; rc_is "ambiguous key rc" 1 "$RC"; contains "ambiguous key message" "$ERR" "matched 2"
    run getDictEntry "$WORK/does/not/exist" anything ; rc_is "missing file rc" 1 "$RC"; contains "missing file message" "$ERR" "not found"
    run getDictEntry onlyOneArg ; rc_is "wrong arg count rc" 1 "$RC"; contains "usage on wrong arg count" "$ERR" "Usage: getDictEntry"

    section "listDictEntries"
    list="$(listDictEntries "$f")"
    line_present "lists a plain entry"        "$list" "scalarEntry"
    line_present "lists a deeply nested entry" "$list" "subDict.nested.deep.delta"
    line_present "lists an entry beside quoted keys" "$list" "solvers.p.solver"
    line_present "lists a quoted key with a dot" "$list" 'solvers."alpha.water.*".cAlpha'
    line_present "lists an entry in an only-subdict dict" "$list" "onlySubDicts.inner.x"
    line_present "lists a quoted key with escaped parens" "$list" 'divSchemes."div\(phi,alpha\)"'
    line_absent  "does not list a bare sub-dict name" "$list" "subDict"
    line_absent  "does not list a bare quoted-dict parent" "$list" "solvers"
    line_absent  "does not list an empty dict" "$list" "emptyDict"
    line_absent  "hides FoamFile.object"  "$list" "FoamFile.object"
    line_absent  "hides FoamFile.version" "$list" "FoamFile.version"
    line_count   "duplicate key appears twice in a listing" 2 "$list" "dupKey"

    section "_dictator_level - one level at a time"
    lvl="$(_dictator_level "$f" "")"
    line_present "top level: plain entry"      "$lvl" "scalarEntry"
    line_present "top level: sub-dict keeps ." "$lvl" "subDict."
    line_present "top level: quoted-dict parent keeps ." "$lvl" "solvers."
    line_present "top level: divSchemes keeps ." "$lvl" "divSchemes."
    line_count   "top level: duplicate key collapses to one" 1 "$lvl" "dupKey"
    line_absent  "top level: does not leak a child" "$lvl" "subDict.alpha"
    line_absent  "top level: empty dict absent"     "$lvl" "emptyDict."
    lvl="$(_dictator_level "$f" "subDict.")"
    line_present "subDict/: direct child"     "$lvl" "subDict.alpha"
    line_present "subDict/: interp child"     "$lvl" "subDict.interp"
    line_present "subDict/: nested sub-dict keeps ." "$lvl" "subDict.nested."
    line_absent  "subDict/: does not leak a grandchild" "$lvl" "subDict.nested.gamma"
    lvl="$(_dictator_level "$f" "solvers.")"
    line_present "solvers/: regex sub-dict"        "$lvl" 'solvers."(U|k|epsilon)".'
    line_present "solvers/: dotted-name sub-dict"  "$lvl" 'solvers."alpha.water.*".'
    line_present "solvers/: plain sub-dict"        "$lvl" "solvers.p."
    lvl="$(_dictator_level "$f" 'solvers."alpha.water.*".')"
    line_present "quoted dict step-in: child 1" "$lvl" 'solvers."alpha.water.*".nAlphaCorr'
    line_present "quoted dict step-in: child 2" "$lvl" 'solvers."alpha.water.*".cAlpha'
    eq           "quoted dict step-in: exactly two children" 2 "$(printf '%s\n' "$lvl" | grep -c .)"

    section "setDictEntry - replace in place"
    C="$(fresh)"; f="$C/system/testDict"; cp "$f" "$WORK/orig"
    run setDictEntry "$f" scalarEntry 2.71828 ; rc_is "replace rc 0" 0 "$RC"
    run getDictEntry "$f" scalarEntry ; eq "replaced value round-trips" 2.71828 "$OUT"
    d="$(diff "$WORK/orig" "$f" | grep -c '^[<>] ')"
    eq "replace touched exactly one line pair" 2 "$d"
    contains "a nearby comment survived" "$(cat "$f")" "the answer"
    run getDictEntry "$f" wordEntry ; eq "an unrelated entry is untouched" kOmegaSST "$OUT"
    run setDictEntry "$f" switchEntry yes ; rc_is "no-op replace still rc 0" 0 "$RC"
    run getDictEntry "$f" 'solvers."alpha.water.*".cAlpha' ; c0="$OUT"
    run setDictEntry "$f" 'solvers."alpha.water.*".cAlpha' 3 ; rc_is "replace a quoted-key value rc" 0 "$RC"
    run getDictEntry "$f" 'solvers."alpha.water.*".cAlpha' ; eq "quoted-key value replaced" 3 "$OUT"

    section "setDictEntry - clearing a value"
    C="$(fresh)"; f="$C/system/testDict"
    run setDictEntry "$f" wordEntry "" ; rc_is "clear rc 0" 0 "$RC"
    run getDictEntry "$f" wordEntry ; rc_is "cleared entry still readable" 0 "$RC"; eq "cleared value is empty" "" "$OUT"
    run setDictEntry "$f" wordEntry restored ; rc_is "re-set rc 0" 0 "$RC"
    run getDictEntry "$f" wordEntry ; eq "value restored after clear" restored "$OUT"

    section "setDictEntry -add - create missing entries"
    C="$(fresh)"; f="$C/system/testDict"
    run setDictEntry -add "$f" subDict.newKey 99 ; rc_is "add into a normal sub-dict rc 2" 2 "$RC"
    run getDictEntry "$f" subDict.newKey ; eq "added entry round-trips" 99 "$OUT"
    grep -qE '^    newKey' "$f" && _ok "added entry indented to match siblings" || _bad "added entry indented to match siblings" "$(grep -n newKey "$f")"
    run getDictEntry "$f" subDict.alpha ; eq "siblings still fine after add" 0.5 "$OUT"
    run setDictEntry -add "$f" onlySubDicts.newTop 7 ; rc_is "add into an only-subdict dict rc 2" 2 "$RC"
    run getDictEntry "$f" onlySubDicts.newTop ; eq "added into only-subdict dict round-trips" 7 "$OUT"
    run setDictEntry -add "$f" ghostDict.child 1 ; rc_is "add below a missing dict rc 1" 1 "$RC"
    contains "add below a missing dict explains why" "$ERR" "no dictionary"
    run setDictEntry "$f" alsoMissing 5 ; rc_is "plain set of a missing key rc 1" 1 "$RC"
    contains "plain set of a missing key is refused" "$ERR" "not found"

    section "setDictEntry - preserves a missing final newline"
    printf 'x 1;\ny 2;' > "$WORK/nonl"
    run setDictEntry "$WORK/nonl" x 3 ; rc_is "set on newline-less file rc 0" 0 "$RC"
    run getDictEntry "$WORK/nonl" y ; eq "other entry intact after rewrite" 2 "$OUT"
    eq "file now ends with a newline" "" "$(tail -c1 "$WORK/nonl")"

    section "setDictEntry - read-only target"
    if [ "$(id -u)" = 0 ]; then
        note "skipped: running as root, file mode is not enforced"
    else
        C="$(fresh)"; f="$C/system/testDict"; chmod 0444 "$f"
        run setDictEntry "$f" scalarEntry 9 ; rc_is "read-only file rc 1" 1 "$RC"
        contains "read-only file is reported" "$ERR" "could not write"
        run getDictEntry "$f" scalarEntry ; eq "read-only file was not changed" 3.14159 "$OUT"
        chmod 0644 "$f"
    fi

    section "dictator - the wrapper"
    C="$(fresh)"; f="$C/system/testDict"
    run dictator "$f" scalarEntry ; rc_is "2 args -> get rc" 0 "$RC"; eq "2 args -> get value" 3.14159 "$OUT"
    run dictator "$f" scalarEntry 9.9 ; rc_is "3 args on existing -> set rc" 0 "$RC"; contains "3 args on existing says Set" "$OUT" "Set"
    run getDictEntry "$f" scalarEntry ; eq "wrapper set took effect" 9.9 "$OUT"
    run dictator "$f" brandNewKey ripe ; rc_is "3 args on missing -> add rc" 0 "$RC"; contains "3 args on missing says Added" "$OUT" "Added"
    run getDictEntry "$f" brandNewKey ; eq "wrapper add took effect" ripe "$OUT"
    run dictator ; rc_is "no args rc" 1 "$RC"; contains "no args prints usage" "$ERR" "Usage: dictator"
    run dictator "$f" a b c ; rc_is "too many args rc" 1 "$RC"; contains "too many args prints usage" "$ERR" "Usage: dictator"
    run dictator -help ; rc_is "-help rc" 0 "$RC"
    contains "-help shows usage"       "$OUT" "Usage: dictator <dictFile> <parameter>"
    contains "-help shows DB provenance" "$OUT" "Parameter help generated from OpenFOAM"

    section "dictator <file> <key> -help  (the parameter database)"
    C="$(fresh)"; f="$C/system/controlDict"
    run dictator "$f" adjustTimeStep -help ; rc_is "known key rc" 0 "$RC"
    contains "known key: header line"  "$OUT" "adjustTimeStep  =  yes"
    contains "known key: attributes"   "$OUT" "Switch"
    contains "known key: scope + source tag" "$OUT" "[controlDict, curated,"
    contains "known key: description"  "$OUT" "Whether the time step is adjusted"
    run dictator "$f" startFrom -help ; rc_is "key with options rc" 0 "$RC"
    contains "options are rendered" "$OUT" "options: firstTime"
    run dictator "$f" totallyMadeUpKey -help ; rc_is "unknown key rc" 0 "$RC"
    contains "unknown key: says so" "$OUT" "No information"

    section "dictator <file> <subDict> -help  (standard-key table)"
    C="$(fresh)"; f="$C/system/fvSolution"
    run dictator "$f" PIMPLE -help ; rc_is "PIMPLE -help rc" 0 "$RC"
    contains "keeps the single-entry header"  "$OUT" "dictionary, optional   [fvSolution, curated,"
    contains "PIMPLE description"             "$OUT" "Controls for the PIMPLE pressure-velocity loop"
    contains "opens the key table"            "$OUT" "standard keys:"
    contains "documented key, value from file" "$OUT" "nOuterCorrectors  =  3"
    contains "value read even when non-default" "$OUT" "momentumPredictor  =  no"
    contains "undocumented-in-file key marked" "$OUT" "turbOnFinalIterOnly   (not set)"
    contains "each key carries its meaning"    "$OUT" "Pressure-correction (PISO) solves per outer iteration."
    contains "each key carries type + default" "$OUT" "label, optional, default 1"
    contains "flags keys not in the database"  "$OUT" "also set here, not in the database: turbulentPotato"
    not_contains "residualControl is documented, not flagged as extra" "$OUT" "database: turbulentPotato, residualControl"
    run dictator "$f" PIMPLE.nCorrectors -help ; rc_is "nested key still single-entry rc" 0 "$RC"
    contains "nested key resolves to its own record" "$OUT" "PIMPLE.nCorrectors  =  2"
    not_contains "nested key does not open a table" "$OUT" "standard keys:"
    run dictator "$f" nCorrectors -help ; rc_is "bare leaf still works rc" 0 "$RC"
    not_contains "bare leaf is not treated as a sub-dict" "$OUT" "standard keys:"
    run dictator "$f" SIMPLE -help ; rc_is "SIMPLE -help rc" 0 "$RC"
    contains "SIMPLE table lists its keys" "$OUT" "consistent   (not set)"

    # TAB hands over a sub-dict with its trailing ".", so -help has to accept it
    run dictator "$f" PIMPLE -help ; bare="$OUT"
    run dictator "$f" PIMPLE. -help ; rc_is "trailing dot -help rc" 0 "$RC"
    eq "trailing dot reads as the dictionary itself" "$bare" "$OUT"
    run dictator "$f" PIMPLE.residualControl -help ; bare="$OUT"
    run dictator "$f" PIMPLE.residualControl. -help ; rc_is "nested trailing dot rc" 0 "$RC"
    eq "trailing dot works at depth" "$bare" "$OUT"

    section "dictator <file> -help  (whole-dictionary description)"
    C="$(fresh)"
    run dictator "$C/system/controlDict" -help ; rc_is "file -help rc" 0 "$RC"
    contains "names the dictionary"      "$OUT" "controlDict"
    contains "describes its purpose"     "$OUT" "Run control for a case"
    contains "shows an example"          "$OUT" "example:"
    contains "example is real content"   "$OUT" "writeControl"
    run dictator "$C/system/fvSolution" -help ; rc_is "fvSolution file -help rc" 0 "$RC"
    contains "fvSolution purpose"        "$OUT" "How the equations are solved"
    contains "fvSolution example"        "$OUT" "PIMPLE"
    run dictator "$C/system/testDict" -help ; rc_is "undocumented file -help rc" 0 "$RC"
    contains "undocumented dictionary says so" "$OUT" "No file-level description for testDict"
    complete_at "dictator $C/system/controlDict -he"
    in_reply "-he completes to -help at arg 2" "-help"

    section "help paging"
    # every -help above already runs through _dictator_page; with stdout not a
    # terminal it must pass straight through, unpaged and unchanged
    a=$(dictator "$C/system/fvSolution" PIMPLE -help); ra=$?
    b=$(DICTATOR_PAGER=cat dictator "$C/system/fvSolution" PIMPLE -help); rb=$?
    eq    "not paged when stdout is not a tty"        "$a" "$b"
    rc_is "help exit status is 0"                     0 "$ra"
    rc_is "DICTATOR_PAGER=cat exit status is 0"       0 "$rb"
    contains "DICTATOR_PAGER=cat still yields the help" "$b" "standard keys:"
    ( _DICTATOR_DIR=/dictator-no-such-dir
      DICTATOR_PAGER=cat dictator "$C/system/controlDict" adjustTimeStep -help >/dev/null 2>&1 )
    rc_is "a failing help still returns non-zero through the pager path" 1 "$?"

    section "_dictator_expand - variable and tilde expansion"
    eq "\$VAR/x"     "$HOME/x"  "$(_dictator_expand '$HOME/x')"
    eq "\${VAR}/x"   "$HOME/x"  "$(_dictator_expand '${HOME}/x')"
    eq "~/x"         "$HOME/x"  "$(_dictator_expand '~/x')"
    eq "no markers"  "a/b/c"    "$(_dictator_expand 'a/b/c')"
    eq "unset var drops to empty" "/x" "$(_dictator_expand '$DICTATOR_NOPE_UNSET/x')"

    section "_dictator_complete - argument 1, the file"
    C="$(fresh)"
    complete_at "dictator $C/system/te"
    reply_suffix "completes a partial filename" "/system/testDict"
    complete_at 'dictator $HO'
    in_reply "completes an env-var prefix" '$HOME/'
    complete_at "dictator -hel"
    in_reply "-hel completes to -help" "-help"
    eq "only -help is offered at arg 1" 1 "${#COMPREPLY[@]}"
    complete_at "dictator -"
    in_reply "a bare dash offers -help" "-help"

    section "_dictator_complete - argument 2, the parameter"
    f="$C/system/testDict"
    complete_at "dictator $f "
    in_reply "empty word offers a plain entry" "scalarEntry"
    in_reply "empty word offers a sub-dict"    "subDict."
    in_reply "empty word offers a quoted-dict parent" "solvers."
    complete_at "dictator $f sub"
    in_reply "partial word narrows to the sub-dict" "subDict."
    complete_at "dictator $f solvers."
    in_reply "stepping into a dict offers its children" "'solvers.p."
    reply_min "stepping into a dict offers several" 3

    # A partial word whose sub-tree holds a name needing quotes is completed
    # with the quote already open, so the next TAB can list those names as
    # OpenFOAM writes them instead of in backslashes.
    complete_at "dictator $f solv"
    in_reply "a quoted sub-tree opens the quote" "'solvers."
    eq "the quote replaces the escaping" 1 "${#COMPREPLY[@]}"
    complete_at "dictator $f sub"
    not_contains "a clean sub-tree stays unquoted" "${COMPREPLY[*]}" "'"
    # already on the line in the old escaped form: still rewritten to the quoted
    # one, and a sole leaf ends the word, so the closing quote goes on too
    complete_at 'dictator '"$f"' solvers.\"alpha.water.*\".nAlphaC'
    in_reply "a sole leaf below a quoted name closes the quote" "'solvers.\"alpha.water.*\".nAlphaCorr'"

    section "_dictator_complete - argument 3, value or -help"
    complete_at "dictator $f scalarEntry -h"
    in_reply "-h completes to -help" "-help"
    eq "only -help is offered" 1 "${#COMPREPLY[@]}"
    complete_at "dictator $f scalarEntry "
    in_reply "value slot seeds the current value" "3.14159"
    complete_at "dictator $f wordEntry "
    in_reply "value slot seeds a word value" "kOmegaSST"

    section "standard values - lookup"
    C="$(fresh)"; f="$C/system/controlDict"
    run _dictator_optionsOf "$f" writeControl
    line_present "a closed list is found"     "$OUT" "adjustableRunTime"
    line_absent  "a closed list has no marker" "$OUT" "..."
    run _dictator_optionsOf "$f" deltaT
    eq "a keyword with no standard set gives nothing" "" "$OUT"
    # the leaf rule reaches a key nested in sub-dicts
    run _dictator_optionsOf "$C/system/fvSolution" solvers.p_rgh.solver
    line_present "the leaf rule finds the list" "$OUT" "PBiCGStab"
    # "mode" and "type" carry a list in some unrelated dictionary; a record from
    # another scope must not be borrowed, or every "type" would draw a warning
    run _dictator_optionsOf "$f" mode
    eq "another dictionary's list is not borrowed (mode)" "" "$OUT"
    run _dictator_optionsOf "$f" type
    eq "another dictionary's list is not borrowed (type)" "" "$OUT"

    section "standard values - completion at the value slot"
    complete_at "dictator $f writeControl "
    in_reply "value slot offers a standard value" "runTime"
    in_reply "value slot offers them all" "adjustableRunTime"
    complete_at "dictator $f writeControl c"
    eq "a partial value narrows the list" 2 "${#COMPREPLY[@]}"
    in_reply "a partial value keeps the match" "clockTime"
    complete_at "dictator $f writeControl zz"
    eq "a value matching nothing offers nothing" 0 "${#COMPREPLY[@]}"
    # what the file holds is not standard just because it is there: beside a
    # closed set it would read as one of the allowed values
    run dictator "$f" writeControl blabla
    complete_at "dictator $f writeControl "
    eq "a closed set offers only itself" 7 "${#COMPREPLY[@]}"
    line_absent "the file's non-standard value is not offered" "$(printf '%s\n' "${COMPREPLY[@]}")" "blabla"
    # a sampled list settles nothing, so the value in the file still belongs
    run dictator "$C/system/fvSolution" smoother nonBlockingGaussSeidel
    complete_at "dictator $C/system/fvSolution smoother "
    in_reply "a sampled list keeps the file's value" "nonBlockingGaussSeidel"
    reply_min "a sampled list still offers the samples" 7

    section "standard values - warning on a non-standard value"
    C="$(fresh)"; f="$C/system/controlDict"
    run dictator "$f" writeControl runTme
    rc_is "a non-standard value still succeeds" 0 "$RC"
    contains "a non-standard value is still written" "$OUT" "Set   writeControl = runTme"
    contains "the warning names the value"  "$ERR" "runTme is not a standard value for writeControl"
    contains "the warning lists the set"    "$ERR" "timeStep | runTime | adjustable"
    run getDictEntry "$f" writeControl ; eq "the write went through" runTme "$OUT"
    run dictator "$f" writeControl runTime
    eq "a standard value is silent" "" "$ERR"
    run dictator "$f" deltaT 0.002
    eq "a keyword with no standard set is silent" "" "$ERR"
    # a list ending in "..." is a sample, so nothing can be judged against it
    run dictator "$C/system/fvSolution" smoother nonBlockingGaussSeidel
    eq "a sampled list warns about nothing" "" "$ERR"
}

# ========================================================================
# driver: run the suite once per awk implementation
# ========================================================================
detect_awks() {
    local want="${DICTATOR_TEST_AWKS:-}" p
    AWK_SPECS=()
    _addawk() { # label  command
        [ -z "$want" ] || case " $want " in *" $1 "*) ;; *) return;; esac
        AWK_SPECS+=("$1=$2")
    }
    _addawk default awk
    p="$(command -v gawk        2>/dev/null)" && _addawk gawk    "$p"
    p="$(command -v mawk        2>/dev/null)" && _addawk mawk    "$p"
    p="$(command -v busybox     2>/dev/null)" && _addawk busybox "$p awk"
    p="$(command -v original-awk 2>/dev/null)" && _addawk bwk    "$p"
}

main() {
    detect_awks
    [ "${#AWK_SPECS[@]}" -gt 0 ] || { echo "run_tests: no awk to test with" >&2; exit 2; }

    printf 'dictator test suite\n'
    printf '  repo:      %s\n' "$ROOT"
    printf '  scratch:   %s\n' "$WORK"
    printf '  awks:      %s\n' "$(for s in "${AWK_SPECS[@]}"; do printf '%s ' "${s%%=*}"; done)"

    local grand_pass=0 grand_fail=0 spec label cmd shim out p f
    for spec in "${AWK_SPECS[@]}"; do
        label="${spec%%=*}"; cmd="${spec#*=}"
        shim=""
        if [ "$label" != default ]; then
            shim="$WORK/shim-$label"; mkdir -p "$shim"
            printf '#!/bin/sh\nexec %s "$@"\n' "$cmd" > "$shim/awk"
            chmod +x "$shim/awk"
        fi

        printf '\n========================================================================\n'
        printf 'awk implementation: %s  (%s)\n' "$label" "$cmd"
        printf '========================================================================\n'

        out="$(
            if [ -n "$shim" ]; then PATH="$shim:$PATH"; hash -r; fi
            printf '  version:   %s\n' "$(awk --version 2>/dev/null | head -1)"
            . "$DICTATOR" >/dev/null 2>&1 || { echo "  (could not source dictator)"; exit 1; }
            pass=0; fail=0
            run_suite
            printf 'SUMMARY %d %d\n' "$pass" "$fail"
        )"

        printf '%s\n' "$out" | grep -v '^SUMMARY'
        set -- $(printf '%s\n' "$out" | sed -n 's/^SUMMARY //p')
        p="${1:-0}"; f="${2:-0}"
        printf '\n  %s: %d passed, %d failed\n' "$label" "$p" "$f"
        grand_pass=$((grand_pass + p)); grand_fail=$((grand_fail + f))
    done

    printf '\n========================================================================\n'
    printf 'TOTAL: %d passed, %d failed\n' "$grand_pass" "$grand_fail"
    printf '========================================================================\n'
    [ "$grand_fail" -eq 0 ]
}

main "$@"

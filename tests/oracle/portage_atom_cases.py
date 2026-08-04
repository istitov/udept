#!/usr/bin/env python3
"""Emit deterministic atom/candidate cases evaluated by Portage itself."""

import sys

import portage
from portage.dep import Atom, check_required_use
from portage.versions import catpkgsplit, cpv_getkey


SAMPLE_SIZE = 100


def match(db, atom, cpv):
    return cpv in {str(item) for item in db.match(atom)}


LOOKUP = "@lookup"
NONE = "-"


def emit(kind, expected, cpv, atom, slot, repo, parent=NONE):
    fields = (kind, "1" if expected else "0", cpv, atom, slot, repo, parent)
    print("\t".join(fields))


def version_cases(db, kind, cpv, slot, repo):
    """Exercise every version operator at equality and across a mutation."""
    split = catpkgsplit(cpv)
    if split is None:
        raise RuntimeError(f"cannot split oracle CPV: {cpv}")
    version = split[2]
    cp = cpv_getkey(cpv)
    base = f"{cp}-{version}"
    lower = f"{version}_alpha0"
    higher = f"{version}_p999999"
    atoms = (
        f">={cpv}", f"<={cpv}", f">{cpv}", f"<{cpv}",
        f">={cp}-{higher}", f"<{cp}-{higher}",
        f">{cp}-{lower}", f"<={cp}-{lower}",
        f"~{base}", f"={base}*",
    )
    for atom in atoms:
        emit(kind, match(db, atom, cpv), cpv, atom, slot, repo)


def conditional_cases(db, cpv, slot, repo, parent, parent_use, flag):
    """Evaluate conditional syntax with Portage, but send it raw to Bash."""
    missing = "udept_oracle_missing"
    specs = (
        f"{flag}(+)?", f"{flag}(-)?", f"{flag}(-)=", f"!{flag}(-)?",
        f"{flag}(+)=", f"!{flag}(+)=", f"-{flag}(+)",
        f"{missing}(-)?", f"!{missing}(-)?", f"{missing}(+)=",
        f"!{missing}(+)=", f"{missing}(-)=",
    )
    for spec in specs:
        atom = f"={cpv}[{spec}]"
        evaluated = Atom(atom, allow_repo=True).evaluate_conditionals(parent_use)
        emit("conditional", match(db, evaluated, cpv), cpv, atom, slot, repo, parent)


def cases(db, kind, include_use, cpvs=None, parent_rows=None):
    if cpvs is None:
        cpvs = sorted(str(cpv) for cpv in db.cpv_all())[:SAMPLE_SIZE]
    if len(cpvs) < SAMPLE_SIZE:
        raise RuntimeError(f"{kind} database has only {len(cpvs)} CPVs")
    for index, cpv in enumerate(cpvs):
        slot, repo, use, iuse, iuse_effective = db.aux_get(
            cpv, ["SLOT", "repository", "USE", "IUSE", "IUSE_EFFECTIVE"]
        )
        main_slot = slot.split("/", 1)[0]
        atom = f"={cpv}:{slot}::{repo}"
        emit(kind, match(db, atom, cpv), cpv, atom, slot, repo)

        bad_atom = f"={cpv}:__udept_missing_slot__::{repo}"
        emit(kind, match(db, bad_atom, cpv), cpv, bad_atom, slot, repo)

        bind_atom = f"={cpv}:{main_slot}=::{repo}"
        emit(kind, match(db, bind_atom, cpv), cpv, bind_atom, slot, repo)

        bad_subslot = f"={cpv}:{main_slot}/udept-missing-subslot::{repo}"
        emit(kind, match(db, bad_subslot, cpv), cpv, bad_subslot, slot, repo)

        bad_repo = f"={cpv}:{slot}::udept-missing-repo"
        emit(kind, match(db, bad_repo, cpv), cpv, bad_repo, slot, repo)

        other = next(other for other in cpvs if cpv_getkey(other) != cpv_getkey(cpv))
        cross_atom = f"={other}"
        emit(kind, match(db, cross_atom, cpv), cpv, cross_atom, slot, repo)

        version_cases(db, kind, cpv, slot, repo)

        # Force Bash through slot_for/repo_for_cpv instead of always handing
        # it the same metadata that Python used for its verdict.
        if index % 10 == 0:
            emit(kind, match(db, atom, cpv), cpv, atom, LOOKUP, LOOKUP)

        if include_use:
            active = set(use.split())
            flags = [flag.lstrip("+-") for flag in iuse.split()]
            enabled = next((flag for flag in flags if flag in active), None)
            disabled = next((flag for flag in flags if flag not in active), None)
            if enabled:
                use_atom = f"={cpv}:{main_slot}::{repo}[{enabled}]"
                emit(kind, match(db, use_atom, cpv), cpv, use_atom, slot, repo)
            if disabled:
                use_atom = f"={cpv}:{main_slot}::{repo}[-{disabled}]"
                emit(kind, match(db, use_atom, cpv), cpv, use_atom, slot, repo)

            candidate_use = set(use.split())
            candidate_iuse = set(iuse_effective.split())
            for parent, parent_use in parent_rows or ():
                flags = sorted(parent_use - candidate_iuse - candidate_use)
                if flags:
                    conditional_cases(
                        db, cpv, slot, repo, parent, parent_use, flags[0]
                    )
                    break


def main():
    eroot = portage.settings["EROOT"]
    trees = portage.db[eroot]
    vardb = trees["vartree"].dbapi
    all_installed_cpvs = sorted(str(cpv) for cpv in vardb.cpv_all())
    installed_cpvs = all_installed_cpvs[:SAMPLE_SIZE]
    parent_rows = []
    for cpv in all_installed_cpvs:
        use = vardb.aux_get(cpv, ["USE"])[0]
        parent_rows.append((cpv, set(use.split())))
    cases(vardb, "installed", True, installed_cpvs, parent_rows)
    portdb = trees["porttree"].dbapi
    visible = []
    for cp in sorted(portdb.cp_all()):
        cpv = portdb.xmatch("bestmatch-visible", cp)
        if cpv:
            visible.append(str(cpv))
        if len(visible) == SAMPLE_SIZE:
            break
    cases(portdb, "visible", False, visible)

    clauses = (
        "foo", "!foo", "|| ( foo bar )", "^^ ( foo bar )",
        "?? ( foo bar )", "foo? ( bar )", "!foo? ( bar )",
        "foo? ( || ( bar baz ) )", "^^ ( foo bar baz )",
        "?? ( foo bar baz )",
    )
    active_sets = ("", "foo", "bar", "baz", "foo bar", "foo baz", "bar baz", "foo bar baz")
    for clause in clauses:
        for active in active_sets:
            result = bool(
                check_required_use(
                    clause, set(active.split()), lambda _flag: True, eapi="8"
                )
            )
            fields = (
                "required", "1" if result else "0", clause, active or NONE,
                NONE, NONE, NONE,
            )
            print("\t".join(fields))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # Make the pipe consumer see a malformed count.
        print(f"Portage oracle failed: {error}", file=sys.stderr)
        raise

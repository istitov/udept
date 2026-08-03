#!/usr/bin/env python3
"""Emit deterministic atom/candidate cases evaluated by Portage itself."""

import sys

import portage
from portage.dep import check_required_use


SAMPLE_SIZE = 100


def match(db, atom, cpv):
    return cpv in {str(item) for item in db.match(atom)}


def emit(kind, expected, cpv, atom, slot, repo):
    print("\t".join((kind, "1" if expected else "0", cpv, atom, slot, repo)))


def cases(db, kind, include_use, cpvs=None):
    if cpvs is None:
        cpvs = sorted(str(cpv) for cpv in db.cpv_all())[:SAMPLE_SIZE]
    if len(cpvs) < SAMPLE_SIZE:
        raise RuntimeError(f"{kind} database has only {len(cpvs)} CPVs")
    for cpv in cpvs:
        slot, repo, use, iuse = db.aux_get(cpv, ["SLOT", "repository", "USE", "IUSE"])
        main_slot = slot.split("/", 1)[0]
        atom = f"={cpv}:{slot}::{repo}"
        emit(kind, match(db, atom, cpv), cpv, atom, slot, repo)

        bad_atom = f"={cpv}:__udept_missing_slot__::{repo}"
        emit(kind, match(db, bad_atom, cpv), cpv, bad_atom, slot, repo)

        bind_atom = f"={cpv}:{main_slot}=::{repo}"
        emit(kind, match(db, bind_atom, cpv), cpv, bind_atom, slot, repo)

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


def main():
    eroot = portage.settings["EROOT"]
    trees = portage.db[eroot]
    cases(trees["vartree"].dbapi, "installed", True)
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
            result = bool(check_required_use(clause, set(active.split()), lambda _flag: True, eapi="8"))
            print("\t".join(("required", "1" if result else "0", clause, active, "", "")))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # Make the pipe consumer see a malformed count.
        print(f"Portage oracle failed: {error}", file=sys.stderr)
        raise

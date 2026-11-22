#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Build proposal.html: the template with the original PNGs embedded as data URIs.

Usage: python docs/mockups/modern-icons/make_proposal.py
"""
import base64
import json
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SEARCH = [
    "legacy/mysql-query-browser/images/toolbar",
    "legacy/mysql-query-browser/images/png",
    "legacy/mysql-gui-common/images/icons/png",
    "legacy/mysql-gui-common/images/png",
]
NAMES = """query_back query_next query_refresh query_execute query_stop
script_execute script_continue script_pause script_stop script_step_into script_step_over script_step_return
script_load script_save script_undo script_redo script_search
small_query_start small_query_commit small_query_rollback small_query_explain small_query_compare
rs_edit rs_apply rs_discard rs_first rs_last rs_search
myx_schema_16x16 myx_schema_table_16x16 myx_schema_view_16x16 myx_schema_sp_16x16
column column_pk column_fk asset_index_16x16
tabsheet_icon_resultset tabsheet_icon_script perspective_browser perspective_scripts mini_add mini_del
options_querybrowser options_general options_connections options_editors
messagedlg_information messagedlg_confirmation messagedlg_warning messagedlg_error""".split()


def find(name):
    for d in SEARCH:
        p = os.path.join(ROOT, d, name + ".png")
        if os.path.exists(p):
            return p
    raise SystemExit("not found: " + name)


def main():
    orig = {}
    for n in NAMES:
        data = open(find(n), "rb").read()
        w, h = struct.unpack(">II", data[16:24])
        orig[n] = {"w": w, "h": h, "src": "data:image/png;base64," + base64.b64encode(data).decode()}
    tpl = open(os.path.join(HERE, "proposal.template.html"), encoding="utf-8").read()
    mole = open(os.path.join(ROOT, "assets", "querymole-icon.png"), "rb").read()   # ADR-0033: the mole replaces the bolt logo
    out = tpl.replace("/*ORIG*/{}", json.dumps(orig, separators=(",", ":")))
    out = out.replace('/*MOLE*/""', json.dumps("data:image/png;base64," + base64.b64encode(mole).decode()))
    with open(os.path.join(HERE, "proposal.html"), "w", encoding="utf-8") as f:
        f.write(out)
    print("proposal.html: %d originals" % len(orig))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Apply a generated Homarr board seed to Homarr's SQLite database (F7-B).

Homarr 1.x has no API for creating boards, so utils/bootstrap/homarr.sh stops
the container and hands the database to this script. Every row the seed owns
carries a deterministic id derived from the service name, which makes the
operation idempotent: the same seed produces the same rows.

    homarr_board.py [--check] <db.sqlite> <board-<env>.json>

--check exits 0 when the database already matches the seed, 1 otherwise.
Rows created by hand on other boards are never touched.
"""

import json
import sqlite3
import sys


def desired_rows(seed):
    board = seed["board"]
    layout = seed["layout"]
    section = seed["section"]

    apps = {
        app["id"]: (
            app["id"],
            app["name"],
            app.get("description"),
            app["iconUrl"],
            app.get("href"),
            app.get("pingUrl"),
        )
        for app in seed["apps"]
    }
    items = {}
    layouts = {}
    for item in seed["items"]:
        options = json.dumps(
            {"json": {"appId": item["appId"], "openInNewTab": True, "showTitle": True}},
            separators=(",", ":"),
        )
        items[item["id"]] = (item["id"], board["id"], item["kind"], options, '{"json": {}}')
        layouts[item["id"]] = (
            item["id"],
            section["id"],
            layout["id"],
            item["xOffset"],
            item["yOffset"],
            item["width"],
            item["height"],
        )
    return apps, items, layouts


def current_rows(db, seed):
    board_id = seed["board"]["id"]
    apps = {
        row[0]: tuple(row)
        for row in db.execute(
            "SELECT id, name, description, icon_url, href, ping_url FROM app"
        )
    }
    items = {
        row[0]: tuple(row)
        for row in db.execute(
            "SELECT id, board_id, kind, options, advanced_options FROM item WHERE board_id = ?",
            (board_id,),
        )
    }
    layouts = {
        row[0]: tuple(row)
        for row in db.execute(
            "SELECT item_id, section_id, layout_id, x_offset, y_offset, width, height "
            "FROM item_layout WHERE layout_id = ?",
            (seed["layout"]["id"],),
        )
    }
    return apps, items, layouts


def matches(db, seed):
    if not db.execute("SELECT 1 FROM board WHERE id = ?", (seed["board"]["id"],)).fetchone():
        return False
    want_apps, want_items, want_layouts = desired_rows(seed)
    have_apps, have_items, have_layouts = current_rows(db, seed)
    if want_items != have_items or want_layouts != have_layouts:
        return False
    return all(have_apps.get(app_id) == row for app_id, row in want_apps.items())


def apply(db, seed):
    board = seed["board"]
    layout = seed["layout"]
    section = seed["section"]
    want_apps, want_items, want_layouts = desired_rows(seed)

    db.execute(
        "INSERT INTO board (id, name, is_public, page_title) VALUES (?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET name = excluded.name, page_title = excluded.page_title",
        (board["id"], board["name"], int(board.get("isPublic", False)), board.get("pageTitle")),
    )
    db.execute(
        "INSERT INTO layout (id, name, board_id, column_count, breakpoint) VALUES (?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET column_count = excluded.column_count",
        (layout["id"], layout["name"], board["id"], layout["columnCount"], layout["breakpoint"]),
    )
    db.execute(
        "INSERT INTO section (id, board_id, kind, x_offset, y_offset) VALUES (?, ?, ?, ?, ?) "
        "ON CONFLICT(id) DO UPDATE SET kind = excluded.kind",
        (section["id"], board["id"], section["kind"], section["xOffset"], section["yOffset"]),
    )

    for row in want_apps.values():
        db.execute(
            "INSERT INTO app (id, name, description, icon_url, href, ping_url) "
            "VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET "
            "name = excluded.name, description = excluded.description, "
            "icon_url = excluded.icon_url, href = excluded.href, ping_url = excluded.ping_url",
            row,
        )
    for row in want_items.values():
        db.execute(
            "INSERT INTO item (id, board_id, kind, options, advanced_options) "
            "VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET "
            "kind = excluded.kind, options = excluded.options",
            row,
        )
    for row in want_layouts.values():
        db.execute(
            "INSERT INTO item_layout (item_id, section_id, layout_id, x_offset, y_offset, width, height) "
            "VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(item_id, section_id, layout_id) DO UPDATE SET "
            "x_offset = excluded.x_offset, y_offset = excluded.y_offset, "
            "width = excluded.width, height = excluded.height",
            row,
        )

    # Tiles dropped from config/services.yml must disappear from the board too.
    keep = list(want_items)
    placeholders = ",".join("?" * len(keep)) or "''"
    db.execute(
        f"DELETE FROM item WHERE board_id = ? AND id NOT IN ({placeholders})",
        [board["id"], *keep],
    )

    # Make the generated board the landing page for every user.
    db.execute(
        "UPDATE serverSetting SET value = ? WHERE setting_key = 'board'",
        (
            json.dumps(
                {
                    "json": {
                        "homeBoardId": board["id"],
                        "mobileHomeBoardId": board["id"],
                        "enableStatusByDefault": True,
                        "forceDisableStatus": False,
                    }
                },
                separators=(",", ":"),
            ),
        ),
    )
    db.commit()


def main(argv):
    check_only = "--check" in argv
    args = [a for a in argv[1:] if a != "--check"]
    if len(args) != 2:
        sys.exit(__doc__)
    db_path, seed_path = args
    seed = json.load(open(seed_path))
    db = sqlite3.connect(db_path)
    db.execute("PRAGMA foreign_keys = ON")
    if check_only:
        sys.exit(0 if matches(db, seed) else 1)
    apply(db, seed)


if __name__ == "__main__":
    main(sys.argv)

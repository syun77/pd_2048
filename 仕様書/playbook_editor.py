#!/usr/bin/env python3
"""Playdate 2048 PLAYBOOK editor.

Run directly with Python 3:
    python3 playbook_editor.py [playbooks.json]
"""

from __future__ import annotations

import copy
import json
import re
import struct
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, ttk


EDITOR_DIR = Path(__file__).resolve().parent
SETTINGS_PATH = EDITOR_DIR / ".playbook_editor_settings.json"
DEFAULT_SAVE_FILENAME = "playbooks.json"
WINDOW_TITLE = "2048 PLAYBOOK Editor"
FORMAT_VERSION = 1
JSON_INDENT = 2
MAX_IMAGE_WIDTH = 360
MAX_IMAGE_HEIGHT = 128
PREVIEW_MAX_WIDTH = 460
PREVIEW_MAX_HEIGHT = MAX_IMAGE_HEIGHT
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
IMAGE_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def localized(ja: str = "", en: str = "") -> dict[str, str]:
    return {"ja": ja, "en": en}


def default_page() -> dict:
    return {
        "image": "",
        "description": localized(),
    }


def default_playbook(sequence: int = 1) -> dict:
    return {
        "id": f"playbook_{sequence:03d}",
        "unlockNo": 0,
        "title": localized("新しいヒント", "NEW HINT"),
        "pages": [default_page()],
    }


def normalize_localized(value: object) -> dict[str, str]:
    if not isinstance(value, dict):
        return localized()
    return {
        "ja": str(value.get("ja", "")),
        "en": str(value.get("en", "")),
    }


def normalize_page(value: object) -> dict:
    if not isinstance(value, dict):
        return default_page()
    return {
        "image": str(value.get("image", "")),
        "description": normalize_localized(value.get("description")),
    }


def normalize_playbook(value: object, sequence: int) -> dict:
    if not isinstance(value, dict):
        raise ValueError(f"Hint {sequence} must be an object.")
    unlock_no = value.get("unlockNo", 0)
    pages_value = value.get("pages", [])
    pages = []
    if isinstance(pages_value, list):
        pages = [normalize_page(page) for page in pages_value]
    return {
        "id": str(value.get("id", "")),
        "unlockNo": unlock_no,
        "title": normalize_localized(value.get("title")),
        "pages": pages,
    }


def parse_payload(value: object) -> list[dict]:
    if not isinstance(value, dict):
        raise ValueError("JSON root must be an object.")
    version = value.get("version")
    if version != FORMAT_VERSION:
        raise ValueError(
            f"version must be {FORMAT_VERSION}; received {version!r}."
        )
    raw_playbooks = value.get("playbooks")
    if not isinstance(raw_playbooks, list):
        raise ValueError("playbooks must be an array.")
    return [
        normalize_playbook(item, index)
        for index, item in enumerate(raw_playbooks, start=1)
    ]


def read_png_size(path: Path) -> tuple[int, int]:
    """Read PNG dimensions without an external image library."""
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) < 24 or header[:8] != PNG_SIGNATURE or header[12:16] != b"IHDR":
        raise ValueError("not a valid PNG header")
    width, height = struct.unpack(">II", header[16:24])
    if width < 1 or height < 1:
        raise ValueError("PNG dimensions must be positive")
    return width, height


def validation_errors(
    playbooks: list[dict], image_directory: Path | None = None
) -> list[str]:
    errors: list[str] = []
    if not playbooks:
        return ["At least one hint is required."]

    seen_ids: set[str] = set()
    has_default_hint = False
    for hint_index, item in enumerate(playbooks, start=1):
        hint_id = str(item.get("id", "")).strip()
        location = f"Hint {hint_index} [{hint_id or 'no id'}]"
        if not ID_PATTERN.fullmatch(hint_id):
            errors.append(f"{location}: ID must match {ID_PATTERN.pattern}.")
        elif hint_id in seen_ids:
            errors.append(f"{location}: duplicate ID.")
        else:
            seen_ids.add(hint_id)

        unlock_no = item.get("unlockNo")
        if isinstance(unlock_no, bool) or not isinstance(unlock_no, int):
            errors.append(f"{location}: Unlock No must be an integer of 0 or greater.")
        elif unlock_no < 0:
            errors.append(f"{location}: Unlock No must be 0 or greater.")
        elif unlock_no == 0:
            has_default_hint = True

        title = item.get("title")
        if not isinstance(title, dict):
            errors.append(f"{location}: title must be an object.")
        else:
            title_ja = title.get("ja", "")
            title_en = title.get("en", "")
            if not isinstance(title_ja, str) or not isinstance(title_en, str):
                errors.append(f"{location}: Title JA and EN must be strings.")
            elif title_ja.strip() == "" and title_en.strip() == "":
                errors.append(f"{location}: at least one title is required.")

        pages = item.get("pages")
        if not isinstance(pages, list) or not pages:
            errors.append(f"{location}: at least one page is required.")
            continue
        for page_index, page in enumerate(pages, start=1):
            page_location = f"{location}, Page {page_index}"
            if not isinstance(page, dict):
                errors.append(f"{page_location}: page must be an object.")
                continue
            image_name = page.get("image", "")
            if not isinstance(image_name, str) or not IMAGE_PATTERN.fullmatch(image_name):
                errors.append(
                    f"{page_location}: Image must match {IMAGE_PATTERN.pattern} "
                    "without a path or extension."
                )
            elif image_directory is not None:
                image_path = image_directory / f"{image_name}.png"
                if not image_path.is_file():
                    errors.append(f"{page_location}: image not found: {image_path.name}")
                else:
                    try:
                        width, height = read_png_size(image_path)
                    except (OSError, ValueError) as exc:
                        errors.append(f"{page_location}: cannot read {image_path.name}: {exc}")
                    else:
                        if width > MAX_IMAGE_WIDTH or height > MAX_IMAGE_HEIGHT:
                            errors.append(
                                f"{page_location}: {image_path.name} is {width}x{height}; "
                                f"maximum is {MAX_IMAGE_WIDTH}x{MAX_IMAGE_HEIGHT}."
                            )

            description = page.get("description")
            if not isinstance(description, dict):
                errors.append(f"{page_location}: description must be an object.")
            else:
                description_ja = description.get("ja", "")
                description_en = description.get("en", "")
                if not isinstance(description_ja, str) or not isinstance(description_en, str):
                    errors.append(
                        f"{page_location}: Description JA and EN must be strings."
                    )
                elif description_ja.strip() == "" and description_en.strip() == "":
                    errors.append(
                        f"{page_location}: at least one description is required."
                    )

    if not has_default_hint:
        errors.append("At least one hint must have Unlock No 0.")
    return errors


def unique_id(base: str, used_ids: set[str]) -> str:
    candidate = base
    suffix = 2
    while candidate in used_ids:
        candidate = f"{base}_{suffix}"
        suffix += 1
    return candidate


class EditorMessageDialog(tk.Toplevel):
    """Tk-only modal message dialog that avoids macOS native alerts."""

    def __init__(
        self,
        parent: tk.Tk,
        title: str,
        message: str,
        buttons: tuple[tuple[str, str], ...],
        default_value: str,
        cancel_value: str | None,
    ) -> None:
        super().__init__(parent)
        self.result: str | None = None
        self.title(title)
        self.resizable(False, False)
        self.transient(parent)
        self.protocol("WM_DELETE_WINDOW", lambda: self.close(cancel_value))

        root = ttk.Frame(self, padding=14)
        root.pack(fill="both", expand=True)
        ttk.Label(
            root,
            text=message,
            justify="left",
            wraplength=520,
        ).pack(fill="x", pady=(0, 14))

        actions = ttk.Frame(root)
        actions.pack(anchor="e")
        default_button: ttk.Button | None = None
        for index, (label, value) in enumerate(buttons):
            button = ttk.Button(
                actions,
                text=label,
                command=lambda selected=value: self.close(selected),
            )
            button.grid(row=0, column=index, padx=(6 if index else 0, 0))
            if value == default_value:
                default_button = button

        self.bind("<Escape>", lambda _event: self.close(cancel_value))
        self.bind("<Return>", lambda _event: self.close(default_value))
        self.grab_set()
        if default_button is not None:
            self.after_idle(default_button.focus_set)

    def show(self) -> str | None:
        self.wait_window()
        return self.result

    def close(self, result: str | None) -> None:
        self.result = result
        try:
            self.grab_release()
        except tk.TclError:
            pass
        self.destroy()


class ValidationErrorDialog(tk.Toplevel):
    """Scrollable in-app dialog for validation failures."""

    def __init__(self, parent: tk.Tk, title: str, errors: list[str]) -> None:
        super().__init__(parent)
        self.title(title)
        self.geometry("760x360")
        self.minsize(560, 260)
        self.transient(parent)
        self.protocol("WM_DELETE_WINDOW", self.close)

        root = ttk.Frame(self, padding=10)
        root.pack(fill="both", expand=True)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(1, weight=1)

        ttk.Label(
            root,
            text=f"Validation found {len(errors)} error(s). Fix them and save again.",
        ).grid(row=0, column=0, sticky="w", pady=(0, 8))

        error_frame = ttk.Frame(root)
        error_frame.grid(row=1, column=0, sticky="nsew")
        error_frame.columnconfigure(0, weight=1)
        error_frame.rowconfigure(0, weight=1)
        error_text = tk.Text(error_frame, wrap="word", padx=8, pady=8)
        error_text.grid(row=0, column=0, sticky="nsew")
        scrollbar = ttk.Scrollbar(
            error_frame, orient="vertical", command=error_text.yview
        )
        scrollbar.grid(row=0, column=1, sticky="ns")
        error_text.configure(yscrollcommand=scrollbar.set)
        error_text.insert(
            "1.0",
            "\n\n".join(
                f"{index}. {error}" for index, error in enumerate(errors, start=1)
            ),
        )
        error_text.configure(state="disabled")

        close_button = ttk.Button(root, text="Close", command=self.close)
        close_button.grid(row=2, column=0, sticky="e", pady=(10, 0))
        close_button.focus_set()
        self.bind("<Escape>", lambda _event: self.close())
        self.grab_set()

    def close(self) -> None:
        try:
            self.grab_release()
        except tk.TclError:
            pass
        self.destroy()


class PlaybookEditor(tk.Tk):
    def __init__(self, initial_paths: tuple[str, ...] = ()) -> None:
        super().__init__()
        self.geometry("1180x720")
        self.minsize(980, 620)

        self.current_path: Path | None = None
        self.working_directory: Path | None = None
        self.playbooks: list[dict] = [default_playbook()]
        self.selected_hint_index: int | None = 0
        self.selected_page_index: int | None = 0
        self.dirty = False
        self._loading = False
        self._preview_image: tk.PhotoImage | None = None
        self._validation_dialog: ValidationErrorDialog | None = None

        self.hint_id_var = tk.StringVar()
        self.unlock_no_var = tk.StringVar()
        self.title_ja_var = tk.StringVar()
        self.title_en_var = tk.StringVar()
        self.image_var = tk.StringVar()
        self.image_status_var = tk.StringVar(value="No image selected")
        self.status_var = tk.StringVar(value="Ready")

        self._build_ui()
        self._bind_shortcuts()
        self._bind_variables()
        self._load_hint(0)
        self._refresh_hint_list()
        self.protocol("WM_DELETE_WINDOW", self._close)

        if initial_paths:
            self._open_file(Path(initial_paths[0]), confirm_discard=False)
        else:
            self._load_last_file()
        self._update_title()

    def _build_ui(self) -> None:
        menu = tk.Menu(self)
        file_menu = tk.Menu(menu, tearoff=False)
        file_menu.add_command(label="New", command=self.new_file)
        file_menu.add_command(label="Open...", command=self.open_file)
        file_menu.add_command(label="Save", command=self.save_file)
        file_menu.add_command(label="Save As...", command=self.save_as)
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self._close)
        menu.add_cascade(label="File", menu=file_menu)
        tools_menu = tk.Menu(menu, tearoff=False)
        tools_menu.add_command(label="Validate", command=self.validate_dialog)
        menu.add_cascade(label="Tools", menu=tools_menu)
        self.config(menu=menu)

        root = ttk.Frame(self, padding=8)
        root.pack(fill="both", expand=True)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(0, weight=1)

        hint_panel = ttk.LabelFrame(root, text="Hints", padding=6)
        hint_panel.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        hint_panel.rowconfigure(0, weight=1)
        hint_panel.columnconfigure(0, weight=1)

        self.hint_listbox = tk.Listbox(
            hint_panel, width=37, height=28, exportselection=False
        )
        self.hint_listbox.grid(row=0, column=0, columnspan=2, sticky="nsew")
        self.hint_listbox.bind("<<ListboxSelect>>", self._on_hint_select)
        hint_scroll = ttk.Scrollbar(
            hint_panel, orient="vertical", command=self.hint_listbox.yview
        )
        hint_scroll.grid(row=0, column=2, sticky="ns")
        self.hint_listbox.configure(yscrollcommand=hint_scroll.set)

        ttk.Button(hint_panel, text="Add", command=self.add_hint).grid(
            row=1, column=0, sticky="ew", pady=(6, 0)
        )
        ttk.Button(hint_panel, text="Duplicate", command=self.duplicate_hint).grid(
            row=1, column=1, sticky="ew", pady=(6, 0), padx=(4, 0)
        )
        ttk.Button(hint_panel, text="Delete", command=self.delete_hint).grid(
            row=2, column=0, columnspan=2, sticky="ew", pady=(4, 0)
        )
        ttk.Button(
            hint_panel, text="Up", command=lambda: self.move_hint(-1)
        ).grid(row=3, column=0, sticky="ew", pady=(4, 0))
        ttk.Button(
            hint_panel, text="Down", command=lambda: self.move_hint(1)
        ).grid(row=3, column=1, sticky="ew", pady=(4, 0), padx=(4, 0))

        editor_panel = ttk.Frame(root)
        editor_panel.grid(row=0, column=1, sticky="nsew")
        editor_panel.columnconfigure(0, weight=1)
        editor_panel.rowconfigure(1, weight=1)

        hint_form = ttk.LabelFrame(editor_panel, text="Selected Hint", padding=8)
        hint_form.grid(row=0, column=0, sticky="ew", pady=(0, 8))
        hint_form.columnconfigure(1, weight=1)
        self._entry(hint_form, 0, "ID", self.hint_id_var)
        self._entry(hint_form, 1, "Unlock No", self.unlock_no_var, width=12)
        self._entry(hint_form, 2, "Title JA", self.title_ja_var)
        self._entry(hint_form, 3, "Title EN", self.title_en_var)

        page_panel = ttk.LabelFrame(editor_panel, text="Pages", padding=8)
        page_panel.grid(row=1, column=0, sticky="nsew")
        page_panel.columnconfigure(1, weight=1)
        page_panel.rowconfigure(0, weight=1)

        page_list_panel = ttk.Frame(page_panel)
        page_list_panel.grid(row=0, column=0, sticky="ns", padx=(0, 8))
        page_list_panel.rowconfigure(0, weight=1)
        page_list_panel.columnconfigure(0, weight=1)
        self.page_listbox = tk.Listbox(
            page_list_panel, width=27, height=19, exportselection=False
        )
        self.page_listbox.grid(row=0, column=0, columnspan=2, sticky="nsew")
        self.page_listbox.bind("<<ListboxSelect>>", self._on_page_select)
        page_scroll = ttk.Scrollbar(
            page_list_panel, orient="vertical", command=self.page_listbox.yview
        )
        page_scroll.grid(row=0, column=2, sticky="ns")
        self.page_listbox.configure(yscrollcommand=page_scroll.set)
        ttk.Button(page_list_panel, text="Add", command=self.add_page).grid(
            row=1, column=0, sticky="ew", pady=(6, 0)
        )
        ttk.Button(page_list_panel, text="Duplicate", command=self.duplicate_page).grid(
            row=1, column=1, sticky="ew", pady=(6, 0), padx=(4, 0)
        )
        ttk.Button(page_list_panel, text="Delete", command=self.delete_page).grid(
            row=2, column=0, columnspan=2, sticky="ew", pady=(4, 0)
        )
        ttk.Button(
            page_list_panel, text="Up", command=lambda: self.move_page(-1)
        ).grid(row=3, column=0, sticky="ew", pady=(4, 0))
        ttk.Button(
            page_list_panel, text="Down", command=lambda: self.move_page(1)
        ).grid(row=3, column=1, sticky="ew", pady=(4, 0), padx=(4, 0))

        page_form = ttk.Frame(page_panel)
        page_form.grid(row=0, column=1, sticky="nsew")
        page_form.columnconfigure(1, weight=1)
        page_form.rowconfigure(5, weight=1)

        ttk.Label(page_form, text="Image").grid(
            row=0, column=0, sticky="w", padx=(0, 8), pady=3
        )
        image_row = ttk.Frame(page_form)
        image_row.grid(row=0, column=1, sticky="ew", pady=3)
        image_row.columnconfigure(0, weight=1)
        ttk.Entry(image_row, textvariable=self.image_var).grid(
            row=0, column=0, sticky="ew"
        )
        ttk.Button(image_row, text="Browse...", command=self.browse_image).grid(
            row=0, column=1, padx=(6, 0)
        )
        ttk.Label(page_form, textvariable=self.image_status_var).grid(
            row=1, column=1, sticky="w", pady=(0, 4)
        )

        preview_frame = tk.Frame(
            page_form,
            height=PREVIEW_MAX_HEIGHT + 2,
            relief="sunken",
            borderwidth=1,
        )
        preview_frame.grid(
            row=2, column=0, columnspan=2, sticky="ew", pady=(0, 8)
        )
        preview_frame.grid_propagate(False)
        self.preview_label = tk.Label(
            preview_frame,
            text="No image selected",
            anchor="center",
        )
        self.preview_label.pack(fill="both", expand=True)

        ttk.Label(page_form, text="Description JA").grid(
            row=3, column=0, sticky="nw", padx=(0, 8), pady=3
        )
        self.description_ja_text = tk.Text(page_form, height=4, wrap="word")
        self.description_ja_text.grid(row=3, column=1, sticky="ew", pady=3)
        self.description_ja_text.bind("<KeyRelease>", self._on_description_change)

        ttk.Label(page_form, text="Description EN").grid(
            row=4, column=0, sticky="nw", padx=(0, 8), pady=3
        )
        self.description_en_text = tk.Text(page_form, height=4, wrap="word")
        self.description_en_text.grid(row=4, column=1, sticky="ew", pady=3)
        self.description_en_text.bind("<KeyRelease>", self._on_description_change)

        actions = ttk.Frame(page_form)
        actions.grid(row=5, column=0, columnspan=2, sticky="sw", pady=(10, 0))
        ttk.Button(actions, text="Validate", command=self.validate_dialog).pack(
            side="left"
        )

        ttk.Label(self, textvariable=self.status_var, anchor="w", padding=(8, 3)).pack(
            fill="x", side="bottom"
        )

    @staticmethod
    def _entry(
        parent: ttk.Frame,
        row: int,
        label: str,
        variable: tk.StringVar,
        width: int = 44,
    ) -> None:
        ttk.Label(parent, text=label).grid(
            row=row, column=0, sticky="w", padx=(0, 8), pady=3
        )
        ttk.Entry(parent, textvariable=variable, width=width).grid(
            row=row, column=1, sticky="ew", pady=3
        )

    def _bind_shortcuts(self) -> None:
        for sequence in ("<Command-n>", "<Control-n>"):
            self.bind(sequence, lambda _event: self.new_file())
        for sequence in ("<Command-o>", "<Control-o>"):
            self.bind(sequence, lambda _event: self.open_file())
        for sequence in ("<Command-s>", "<Control-s>"):
            self.bind(sequence, lambda _event: self.save_file())

    def _bind_variables(self) -> None:
        for variable in (
            self.hint_id_var,
            self.unlock_no_var,
            self.title_ja_var,
            self.title_en_var,
        ):
            variable.trace_add("write", self._on_hint_form_change)
        self.image_var.trace_add("write", self._on_page_form_change)

    def _current_hint(self) -> dict | None:
        index = self.selected_hint_index
        if index is None or not (0 <= index < len(self.playbooks)):
            return None
        return self.playbooks[index]

    def _current_page(self) -> dict | None:
        hint = self._current_hint()
        index = self.selected_page_index
        if hint is None or index is None or not (0 <= index < len(hint["pages"])):
            return None
        return hint["pages"][index]

    def _commit_hint_form(self) -> None:
        hint = self._current_hint()
        if hint is None:
            return
        unlock_text = self.unlock_no_var.get().strip()
        hint["id"] = self.hint_id_var.get().strip()
        hint["unlockNo"] = int(unlock_text) if unlock_text.isdigit() else unlock_text
        hint["title"] = localized(
            self.title_ja_var.get().strip(), self.title_en_var.get().strip()
        )

    def _commit_page_form(self) -> None:
        page = self._current_page()
        if page is None:
            return
        page["image"] = self.image_var.get().strip()
        page["description"] = localized(
            self.description_ja_text.get("1.0", "end-1c").strip(),
            self.description_en_text.get("1.0", "end-1c").strip(),
        )

    def _commit_forms(self) -> None:
        self._commit_hint_form()
        self._commit_page_form()

    def _on_hint_form_change(self, *_args: object) -> None:
        if self._loading:
            return
        self._commit_hint_form()
        self._refresh_current_hint_label()
        self._mark_changed()

    def _on_page_form_change(self, *_args: object) -> None:
        if self._loading:
            return
        self._commit_page_form()
        self._refresh_current_page_label()
        self._update_image_preview()
        self._mark_changed()

    def _on_description_change(self, _event: tk.Event | None = None) -> None:
        if self._loading:
            return
        self._commit_page_form()
        self._mark_changed()

    def _on_hint_select(self, _event: tk.Event | None = None) -> None:
        if self._loading:
            return
        selection = self.hint_listbox.curselection()
        if not selection or selection[0] == self.selected_hint_index:
            return
        self._commit_forms()
        self._load_hint(selection[0])

    def _on_page_select(self, _event: tk.Event | None = None) -> None:
        if self._loading:
            return
        selection = self.page_listbox.curselection()
        if not selection or selection[0] == self.selected_page_index:
            return
        self._commit_page_form()
        self._load_page(selection[0])

    def _load_hint(self, index: int | None) -> None:
        self._loading = True
        self.selected_hint_index = index
        hint = self._current_hint()
        if hint is None:
            self.hint_id_var.set("")
            self.unlock_no_var.set("")
            self.title_ja_var.set("")
            self.title_en_var.set("")
            self.selected_page_index = None
        else:
            self.hint_id_var.set(str(hint.get("id", "")))
            self.unlock_no_var.set(str(hint.get("unlockNo", "")))
            self.title_ja_var.set(str(hint.get("title", {}).get("ja", "")))
            self.title_en_var.set(str(hint.get("title", {}).get("en", "")))
            self.selected_page_index = 0 if hint["pages"] else None
        self._refresh_page_list()
        self._load_page_fields()
        self._refresh_hint_selection()
        self._loading = False
        self._update_image_preview()

    def _load_page(self, index: int | None) -> None:
        self._loading = True
        self.selected_page_index = index
        self._load_page_fields()
        self._refresh_page_selection()
        self._loading = False
        self._update_image_preview()

    def _load_page_fields(self) -> None:
        page = self._current_page()
        image = "" if page is None else str(page.get("image", ""))
        description = {} if page is None else page.get("description", {})
        self.image_var.set(image)
        self.description_ja_text.delete("1.0", tk.END)
        self.description_en_text.delete("1.0", tk.END)
        if isinstance(description, dict):
            self.description_ja_text.insert("1.0", str(description.get("ja", "")))
            self.description_en_text.insert("1.0", str(description.get("en", "")))

    def _hint_label(self, index: int, item: dict) -> str:
        title = item.get("title", {})
        name = title.get("en") or title.get("ja") or "(no title)"
        unlock_no = item.get("unlockNo", "?")
        return f"{index + 1:>3}  U:{unlock_no}  {name}"

    def _page_label(self, index: int, page: dict) -> str:
        image = page.get("image") or "(no image)"
        return f"{index + 1:>3}  {image}"

    def _refresh_hint_list(self) -> None:
        self._loading = True
        self.hint_listbox.delete(0, tk.END)
        for index, item in enumerate(self.playbooks):
            self.hint_listbox.insert(tk.END, self._hint_label(index, item))
        self._refresh_hint_selection()
        self._loading = False

    def _refresh_page_list(self) -> None:
        self.page_listbox.delete(0, tk.END)
        hint = self._current_hint()
        if hint is not None:
            for index, page in enumerate(hint["pages"]):
                self.page_listbox.insert(tk.END, self._page_label(index, page))
        self._refresh_page_selection()

    def _reload_pages(self, selected_index: int | None) -> None:
        """Reload the page list and form without handling transient selections."""
        was_loading = self._loading
        self._loading = True
        try:
            self.selected_page_index = selected_index
            self._refresh_page_list()
            self._load_page_fields()
        finally:
            self._loading = was_loading
        self._update_image_preview()

    def _refresh_hint_selection(self) -> None:
        self.hint_listbox.selection_clear(0, tk.END)
        index = self.selected_hint_index
        if index is not None and 0 <= index < self.hint_listbox.size():
            self.hint_listbox.selection_set(index)
            self.hint_listbox.see(index)

    def _refresh_page_selection(self) -> None:
        self.page_listbox.selection_clear(0, tk.END)
        index = self.selected_page_index
        if index is not None and 0 <= index < self.page_listbox.size():
            self.page_listbox.selection_set(index)
            self.page_listbox.see(index)

    def _refresh_current_hint_label(self) -> None:
        hint = self._current_hint()
        index = self.selected_hint_index
        if hint is None or index is None or index >= self.hint_listbox.size():
            return
        self.hint_listbox.delete(index)
        self.hint_listbox.insert(index, self._hint_label(index, hint))
        self._refresh_hint_selection()

    def _refresh_current_page_label(self) -> None:
        page = self._current_page()
        index = self.selected_page_index
        if page is None or index is None or index >= self.page_listbox.size():
            return
        self.page_listbox.delete(index)
        self.page_listbox.insert(index, self._page_label(index, page))
        self._refresh_page_selection()

    def _mark_changed(self) -> None:
        if self._loading:
            return
        self.dirty = True
        self._update_title()

    def _image_directory(self) -> Path:
        if self.current_path is not None:
            return self.current_path.parent
        if self.working_directory is not None:
            return self.working_directory
        return EDITOR_DIR

    def _update_image_preview(self) -> None:
        self._preview_image = None
        image_name = self.image_var.get().strip()
        if not IMAGE_PATTERN.fullmatch(image_name):
            self.image_status_var.set("Image name must omit path and .png extension")
            self.preview_label.configure(image="", text="No valid image selected")
            return
        image_path = self._image_directory() / f"{image_name}.png"
        if not image_path.is_file():
            self.image_status_var.set(f"Not found: {image_path.name}")
            self.preview_label.configure(image="", text="Image not found")
            return
        try:
            width, height = read_png_size(image_path)
            source = tk.PhotoImage(file=str(image_path))
            factor = max(
                1,
                (width + PREVIEW_MAX_WIDTH - 1) // PREVIEW_MAX_WIDTH,
                (height + PREVIEW_MAX_HEIGHT - 1) // PREVIEW_MAX_HEIGHT,
            )
            self._preview_image = source.subsample(factor, factor) if factor > 1 else source
        except (OSError, ValueError, tk.TclError) as exc:
            self.image_status_var.set(f"Cannot preview: {exc}")
            self.preview_label.configure(image="", text="Cannot preview image")
            return
        size_status = f"{width}x{height}px"
        if width > MAX_IMAGE_WIDTH or height > MAX_IMAGE_HEIGHT:
            size_status += f" — exceeds {MAX_IMAGE_WIDTH}x{MAX_IMAGE_HEIGHT}px"
        else:
            size_status += " — valid game size"
        self.image_status_var.set(size_status)
        self.preview_label.configure(image=self._preview_image, text="")

    def browse_image(self) -> None:
        base_directory = self._image_directory().resolve()
        path_text = filedialog.askopenfilename(
            initialdir=base_directory,
            filetypes=(("PNG images", "*.png"), ("All files", "*.*")),
        )
        if not path_text:
            return
        path = Path(path_text)
        try:
            selected_directory = path.parent.resolve()
        except OSError:
            selected_directory = path.parent
        if self.current_path is not None and selected_directory != base_directory:
            self._show_message(
                "Invalid Image",
                "The image must be in the same folder as playbooks.json.",
            )
            return
        if path.suffix.lower() != ".png":
            self._show_message("Invalid Image", "Select a PNG image.")
            return
        if not IMAGE_PATTERN.fullmatch(path.stem):
            self._show_message(
                "Invalid Image",
                f"Image filename must match {IMAGE_PATTERN.pattern}.",
            )
            return
        if self.current_path is None:
            self.working_directory = selected_directory
        self.image_var.set(path.stem)

    def add_hint(self) -> None:
        self._commit_forms()
        used_ids = {str(item.get("id", "")) for item in self.playbooks}
        sequence = len(self.playbooks) + 1
        item = default_playbook(sequence)
        item["id"] = unique_id(item["id"], used_ids)
        self.playbooks.append(item)
        self._refresh_hint_list()
        self._load_hint(len(self.playbooks) - 1)
        self._mark_changed()

    def duplicate_hint(self) -> None:
        hint = self._current_hint()
        index = self.selected_hint_index
        if hint is None or index is None:
            return
        self._commit_forms()
        duplicate = copy.deepcopy(hint)
        used_ids = {str(item.get("id", "")) for item in self.playbooks}
        duplicate["id"] = unique_id(f"{hint['id']}_copy", used_ids)
        self.playbooks.insert(index + 1, duplicate)
        self._refresh_hint_list()
        self._load_hint(index + 1)
        self._mark_changed()

    def delete_hint(self) -> None:
        hint = self._current_hint()
        index = self.selected_hint_index
        if hint is None or index is None:
            return
        if len(self.playbooks) <= 1:
            self._show_message("Delete", "At least one hint is required.")
            return
        if not self._confirm_delete(
            "Delete Hint", f"Delete {hint.get('id') or '(no id)'}?"
        ):
            return
        del self.playbooks[index]
        self._refresh_hint_list()
        self._load_hint(min(index, len(self.playbooks) - 1))
        self._mark_changed()

    def move_hint(self, direction: int) -> None:
        index = self.selected_hint_index
        if index is None:
            return
        new_index = index + direction
        if not (0 <= new_index < len(self.playbooks)):
            return
        self._commit_forms()
        self.playbooks[index], self.playbooks[new_index] = (
            self.playbooks[new_index],
            self.playbooks[index],
        )
        self.selected_hint_index = new_index
        self._refresh_hint_list()
        self._load_hint(new_index)
        self._mark_changed()

    def add_page(self) -> None:
        hint = self._current_hint()
        if hint is None:
            return
        self._commit_page_form()
        hint["pages"].append(default_page())
        self._refresh_page_list()
        self._load_page(len(hint["pages"]) - 1)
        self._mark_changed()

    def duplicate_page(self) -> None:
        hint = self._current_hint()
        page = self._current_page()
        index = self.selected_page_index
        if hint is None or page is None or index is None:
            return
        self._commit_page_form()
        hint["pages"].insert(index + 1, copy.deepcopy(page))
        self._refresh_page_list()
        self._load_page(index + 1)
        self._mark_changed()

    def delete_page(self) -> None:
        hint = self._current_hint()
        index = self.selected_page_index
        if hint is None or index is None:
            return
        if len(hint["pages"]) <= 1:
            self._show_message("Delete", "At least one page is required.")
            return
        if not self._confirm_delete("Delete Page", f"Delete page {index + 1}?"):
            return
        del hint["pages"][index]
        self._reload_pages(min(index, len(hint["pages"]) - 1))
        self._mark_changed()

    def move_page(self, direction: int) -> None:
        hint = self._current_hint()
        index = self.selected_page_index
        if hint is None or index is None:
            return
        new_index = index + direction
        if not (0 <= new_index < len(hint["pages"])):
            return
        self._commit_page_form()
        hint["pages"][index], hint["pages"][new_index] = (
            hint["pages"][new_index],
            hint["pages"][index],
        )
        self.selected_page_index = new_index
        self._refresh_page_list()
        self._load_page(new_index)
        self._mark_changed()

    def new_file(self) -> None:
        if not self._confirm_discard():
            return
        self.current_path = None
        self.working_directory = None
        self.playbooks = [default_playbook()]
        self.selected_hint_index = 0
        self.selected_page_index = 0
        self.dirty = False
        self._refresh_hint_list()
        self._load_hint(0)
        self.status_var.set("Ready")
        self._update_title()

    def open_file(self) -> None:
        if not self._confirm_discard():
            return
        path_text = filedialog.askopenfilename(
            initialdir=self._initial_directory(),
            filetypes=(("JSON files", "*.json"), ("All files", "*.*")),
        )
        if path_text:
            self._open_file(Path(path_text), confirm_discard=False)

    def _open_file(self, path: Path, confirm_discard: bool = True) -> None:
        if confirm_discard and not self._confirm_discard():
            return
        try:
            with path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
            playbooks = parse_payload(payload)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            self._show_message("Open Failed", str(exc))
            return
        self.current_path = path
        self.working_directory = path.parent
        self.playbooks = playbooks
        self.selected_hint_index = 0 if playbooks else None
        self.selected_page_index = None
        self.dirty = False
        self._refresh_hint_list()
        self._load_hint(self.selected_hint_index)
        self._save_settings()
        errors = validation_errors(self.playbooks, path.parent)
        if errors:
            self.status_var.set(
                f"Opened {path.name} with {len(errors)} validation error(s)"
            )
            self.after_idle(lambda: self._show_validation_errors(errors, "Open Warning"))
        else:
            self.status_var.set(f"Opened {path.name}")
        self._update_title()

    def save_file(self) -> bool:
        if self.current_path is None:
            return self.save_as()
        return self._save_to(self.current_path)

    def save_as(self) -> bool:
        path_text = filedialog.asksaveasfilename(
            initialdir=self._initial_directory(),
            initialfile=(
                self.current_path.name if self.current_path else DEFAULT_SAVE_FILENAME
            ),
            defaultextension=".json",
            filetypes=(("JSON files", "*.json"), ("All files", "*.*")),
        )
        if not path_text:
            return False
        return self._save_to(Path(path_text))

    def _save_to(self, path: Path) -> bool:
        try:
            self._commit_forms()
            errors = validation_errors(self.playbooks, path.parent)
        except Exception as exc:
            errors = [f"Unexpected validation error: {type(exc).__name__}: {exc}"]
        if errors:
            self._show_validation_errors(errors, "Save Failed")
            self.status_var.set(f"Save blocked: {len(errors)} validation error(s)")
            return False
        payload = {"version": FORMAT_VERSION, "playbooks": self.playbooks}
        try:
            with path.open("w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False, indent=JSON_INDENT)
                handle.write("\n")
        except OSError as exc:
            self._show_message("Save Failed", str(exc))
            return False
        self.current_path = path
        self.working_directory = path.parent
        self.dirty = False
        self._save_settings()
        self._update_title()
        self._update_image_preview()
        self.status_var.set(f"Saved {path.name}")
        return True

    def validate_dialog(self) -> None:
        try:
            self._commit_forms()
            errors = validation_errors(self.playbooks, self._image_directory())
        except Exception as exc:
            errors = [f"Unexpected validation error: {type(exc).__name__}: {exc}"]
        if errors:
            self._show_validation_errors(errors, "Validation Failed")
            self.status_var.set(f"Validation failed: {len(errors)} error(s)")
            return
        self._show_message("Validation", "PLAYBOOK data is valid.")
        self.status_var.set("Validation passed")

    def _show_message(self, title: str, message: str) -> None:
        EditorMessageDialog(
            self,
            title,
            message,
            (("OK", "ok"),),
            default_value="ok",
            cancel_value="ok",
        ).show()

    def _confirm_delete(self, title: str, message: str) -> bool:
        result = EditorMessageDialog(
            self,
            title,
            message,
            (("Delete", "delete"), ("Cancel", "cancel")),
            default_value="cancel",
            cancel_value="cancel",
        ).show()
        return result == "delete"

    def _show_validation_errors(self, errors: list[str], title: str) -> None:
        dialog = self._validation_dialog
        if dialog is not None:
            try:
                if dialog.winfo_exists():
                    dialog.close()
            except tk.TclError:
                pass
        self._validation_dialog = ValidationErrorDialog(self, title, errors)

    def _initial_directory(self) -> Path:
        if self.current_path is not None:
            return self.current_path.parent
        if self.working_directory is not None:
            return self.working_directory
        last_path = self._read_last_opened_file()
        if last_path is not None and last_path.is_file():
            return last_path.parent
        return EDITOR_DIR

    def _read_last_opened_file(self) -> Path | None:
        try:
            payload = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            path_text = payload.get("lastOpenedFile", "")
            if not isinstance(path_text, str) or not path_text:
                return None
            return Path(path_text)
        except (OSError, ValueError, json.JSONDecodeError):
            return None

    def _load_last_file(self) -> None:
        path = self._read_last_opened_file()
        if path is not None and path.is_file():
            self._open_file(path, confirm_discard=False)

    def _save_settings(self) -> None:
        if self.current_path is None:
            return
        try:
            SETTINGS_PATH.write_text(
                json.dumps(
                    {"lastOpenedFile": str(self.current_path)}, indent=JSON_INDENT
                )
                + "\n",
                encoding="utf-8",
            )
        except OSError:
            pass

    def _confirm_discard(self) -> bool:
        if not self.dirty:
            return True
        result = EditorMessageDialog(
            self,
            "Unsaved Changes",
            "Save changes before continuing?",
            (("Save", "save"), ("Discard", "discard"), ("Cancel", "cancel")),
            default_value="save",
            cancel_value="cancel",
        ).show()
        if result == "cancel":
            return False
        if result == "save":
            return self.save_file()
        return result == "discard"

    def _close(self) -> None:
        if self._confirm_discard():
            self.destroy()

    def _update_title(self) -> None:
        name = self.current_path.name if self.current_path else "Untitled"
        mark = "*" if self.dirty else ""
        self.title(f"{name}{mark} - {WINDOW_TITLE}")


def main() -> None:
    app = PlaybookEditor(tuple(sys.argv[1:]))
    app.mainloop()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Playdate 2048 achievement editor.

Run directly with Python 3:
    python3 achievement_editor.py
"""

from __future__ import annotations

import copy
import json
import re
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk


EDITOR_DIR = Path(__file__).resolve().parent
SETTINGS_FILENAME = ".achievement_editor_settings.json"
SETTINGS_PATH = EDITOR_DIR / SETTINGS_FILENAME
DEFAULT_SAVE_FILENAME = "achievements.json"
WINDOW_TITLE = "2048 Achievement Editor"
DEFAULT_STATUS = "Ready"
DEFAULT_JSON_INDENT = 2
ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")

CATEGORIES = ["SYSTEM", "NORMAL", "TIME_ATTACK", "CORE_RUSH", "PRACTICE"]
CONDITION_TYPES = [
    "MERGE_COUNT",
    "TILE_VALUE",
    "SCORE",
    "COMBO",
    "CLEAR_MODE",
    "PRACTICE_CLEAR_COUNT",
    "NO_REWIND_CLEAR",
    "PLAY_COUNT",
    "TOTAL_SCORE",
    "BEST_TIME_MS",
]
SCOPES = ["RUN", "LIFETIME"]
OPERATORS = [">=", "==", "<=", ">", "<"]
REWARD_TYPES = ["NONE", "BGM_UNLOCK", "THEME_UNLOCK", "TITLE_BADGE", "SOUND_UNLOCK"]

PARAM_HINTS = {
    "MERGE_COUNT": "count=1",
    "TILE_VALUE": "value=2048",
    "SCORE": "score=10000",
    "COMBO": "combo=3",
    "CLEAR_MODE": "mode=NORMAL",
    "PRACTICE_CLEAR_COUNT": "count=10",
    "NO_REWIND_CLEAR": "mode=NORMAL",
    "PLAY_COUNT": "count=10",
    "TOTAL_SCORE": "score=100000",
    "BEST_TIME_MS": "mode=TIME_ATTACK,target=64,timeMs=60000",
}


def localized(ja: str = "", en: str = "") -> dict:
    return {"ja": ja, "en": en}


def default_achievement(no: int = 1) -> dict:
    return {
        "no": no,
        "id": f"achievement_{no:03d}",
        "category": "SYSTEM",
        "name": localized("NEW ACHIEVEMENT", "NEW ACHIEVEMENT"),
        "description": localized("", ""),
        "condition": {
            "type": "MERGE_COUNT",
            "scope": "LIFETIME",
            "operator": ">=",
            "params": {"count": 1},
        },
        "reward": {"type": "NONE", "id": ""},
        "hidden": False,
        "progressVisible": True,
    }


def normalize_localized(value: object) -> dict:
    if isinstance(value, dict):
        return {
            "ja": str(value.get("ja", "")),
            "en": str(value.get("en", "")),
        }
    if isinstance(value, str):
        return {"ja": value, "en": value}
    return {"ja": "", "en": ""}


def parse_scalar(value: str) -> object:
    text = value.strip()
    if text == "":
        return ""
    lowered = text.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        return text


def parse_params(text: str) -> dict:
    params: dict[str, object] = {}
    stripped = text.strip()
    if stripped == "":
        return params
    for raw_part in stripped.split(","):
        part = raw_part.strip()
        if part == "":
            continue
        if "=" not in part:
            raise ValueError(f"Parameter must be key=value: {part}")
        key, value = part.split("=", 1)
        key = key.strip()
        if key == "":
            raise ValueError("Parameter key cannot be empty.")
        params[key] = parse_scalar(value)
    return params


def format_params(params: object) -> str:
    if not isinstance(params, dict):
        return ""
    parts = []
    for key in sorted(params.keys()):
        value = params[key]
        if isinstance(value, bool):
            value_text = "true" if value else "false"
        else:
            value_text = str(value)
        parts.append(f"{key}={value_text}")
    return ",".join(parts)


def normalize_achievement(raw: object, fallback_no: int) -> dict:
    if not isinstance(raw, dict):
        raw = {}
    item = default_achievement(fallback_no)
    item["no"] = int(raw.get("no", fallback_no)) if str(raw.get("no", "")).strip() else fallback_no
    item["id"] = str(raw.get("id", item["id"]))
    item["category"] = str(raw.get("category", item["category"]))
    item["name"] = normalize_localized(raw.get("name", item["name"]))
    item["description"] = normalize_localized(raw.get("description", item["description"]))

    condition = raw.get("condition", {})
    if not isinstance(condition, dict):
        condition = {}
    item["condition"] = {
        "type": str(condition.get("type", item["condition"]["type"])),
        "scope": str(condition.get("scope", item["condition"]["scope"])),
        "operator": str(condition.get("operator", item["condition"]["operator"])),
        "params": condition.get("params", item["condition"]["params"]),
    }
    if not isinstance(item["condition"]["params"], dict):
        item["condition"]["params"] = {}

    reward = raw.get("reward", {})
    if not isinstance(reward, dict):
        reward = {}
    item["reward"] = {
        "type": str(reward.get("type", item["reward"]["type"])),
        "id": str(reward.get("id", item["reward"]["id"])),
    }
    item["hidden"] = bool(raw.get("hidden", item["hidden"]))
    item["progressVisible"] = bool(raw.get("progressVisible", item["progressVisible"]))
    return item


class AchievementEditor(tk.Tk):
    def __init__(self, initial_paths: tuple[str, ...] = ()) -> None:
        super().__init__()
        self.title(WINDOW_TITLE)
        self.geometry("940x560")
        self.minsize(860, 520)

        self.current_path: Path | None = None
        self.dirty = False
        self.achievements: list[dict] = [default_achievement(1)]
        self.selected_index: int | None = 0
        self._loading_form = False

        self.no_var = tk.StringVar()
        self.id_var = tk.StringVar()
        self.category_var = tk.StringVar()
        self.name_ja_var = tk.StringVar()
        self.name_en_var = tk.StringVar()
        self.description_ja_var = tk.StringVar()
        self.description_en_var = tk.StringVar()
        self.condition_type_var = tk.StringVar()
        self.scope_var = tk.StringVar()
        self.operator_var = tk.StringVar()
        self.params_var = tk.StringVar()
        self.reward_type_var = tk.StringVar()
        self.reward_id_var = tk.StringVar()
        self.hidden_var = tk.BooleanVar()
        self.progress_visible_var = tk.BooleanVar()
        self.status_var = tk.StringVar(value=DEFAULT_STATUS)

        self._build_ui()
        self._bind_shortcuts()
        self._load_form(0)
        self._refresh_list()

        if initial_paths:
            self._open_file(Path(initial_paths[0]), confirm_discard=False)
        else:
            self._load_last_file()
        self.protocol("WM_DELETE_WINDOW", self._close)

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
        self.config(menu=menu)

        root = ttk.Frame(self, padding=8)
        root.pack(fill="both", expand=True)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(0, weight=1)

        left = ttk.Frame(root)
        left.grid(row=0, column=0, sticky="ns", padx=(0, 8))
        left.rowconfigure(0, weight=1)

        self.listbox = tk.Listbox(left, width=34, height=24, exportselection=False)
        self.listbox.grid(row=0, column=0, columnspan=2, sticky="nsew")
        self.listbox.bind("<<ListboxSelect>>", self._on_select)
        scroll = ttk.Scrollbar(left, orient="vertical", command=self.listbox.yview)
        scroll.grid(row=0, column=2, sticky="ns")
        self.listbox.configure(yscrollcommand=scroll.set)

        ttk.Button(left, text="Add", command=self.add_achievement).grid(row=1, column=0, sticky="ew", pady=(6, 0))
        ttk.Button(left, text="Duplicate", command=self.duplicate_achievement).grid(row=1, column=1, sticky="ew", pady=(6, 0), padx=(4, 0))
        ttk.Button(left, text="Delete", command=self.delete_achievement).grid(row=2, column=0, sticky="ew", pady=(4, 0))
        ttk.Button(left, text="Renumber", command=self.renumber).grid(row=2, column=1, sticky="ew", pady=(4, 0), padx=(4, 0))
        ttk.Button(left, text="Up", command=lambda: self.move_selected(-1)).grid(row=3, column=0, sticky="ew", pady=(4, 0))
        ttk.Button(left, text="Down", command=lambda: self.move_selected(1)).grid(row=3, column=1, sticky="ew", pady=(4, 0), padx=(4, 0))

        form = ttk.Frame(root)
        form.grid(row=0, column=1, sticky="nsew")
        form.columnconfigure(1, weight=1)

        row = 0
        row = self._entry(form, row, "NO", self.no_var, width=10)
        row = self._entry(form, row, "ID", self.id_var)
        row = self._combo(form, row, "Category", self.category_var, CATEGORIES)
        row = self._entry(form, row, "Name JA", self.name_ja_var)
        row = self._entry(form, row, "Name EN", self.name_en_var)
        row = self._entry(form, row, "Description JA", self.description_ja_var)
        row = self._entry(form, row, "Description EN", self.description_en_var)

        ttk.Separator(form).grid(row=row, column=0, columnspan=2, sticky="ew", pady=8)
        row += 1
        row = self._combo(form, row, "Condition Type", self.condition_type_var, CONDITION_TYPES)
        row = self._combo(form, row, "Scope", self.scope_var, SCOPES)
        row = self._combo(form, row, "Operator", self.operator_var, OPERATORS, width=8)
        row = self._entry(form, row, "Params", self.params_var)
        self.params_hint = ttk.Label(form, text="", foreground="#555")
        self.params_hint.grid(row=row, column=1, sticky="w", pady=(0, 6))
        row += 1

        ttk.Separator(form).grid(row=row, column=0, columnspan=2, sticky="ew", pady=8)
        row += 1
        row = self._combo(form, row, "Reward Type", self.reward_type_var, REWARD_TYPES)
        row = self._entry(form, row, "Reward ID", self.reward_id_var)

        ttk.Checkbutton(form, text="Hidden until unlocked", variable=self.hidden_var, command=self._mark_changed).grid(
            row=row, column=1, sticky="w", pady=(6, 0)
        )
        row += 1
        ttk.Checkbutton(form, text="Show progress", variable=self.progress_visible_var, command=self._mark_changed).grid(
            row=row, column=1, sticky="w", pady=(2, 0)
        )
        row += 1

        actions = ttk.Frame(form)
        actions.grid(row=row, column=0, columnspan=2, sticky="ew", pady=(12, 0))
        ttk.Button(actions, text="Validate", command=self.validate_dialog).pack(side="left")
        ttk.Button(actions, text="Apply Form", command=self._apply_form_to_selected).pack(side="left", padx=(6, 0))

        status = ttk.Label(self, textvariable=self.status_var, anchor="w", padding=(8, 3))
        status.pack(fill="x", side="bottom")

        for variable in (
            self.no_var,
            self.id_var,
            self.category_var,
            self.name_ja_var,
            self.name_en_var,
            self.description_ja_var,
            self.description_en_var,
            self.condition_type_var,
            self.scope_var,
            self.operator_var,
            self.params_var,
            self.reward_type_var,
            self.reward_id_var,
        ):
            variable.trace_add("write", self._on_form_change)
        self.condition_type_var.trace_add("write", lambda *_: self._update_param_hint())

    def _entry(self, parent: ttk.Frame, row: int, label: str, variable: tk.StringVar, width: int = 42) -> int:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", pady=3, padx=(0, 8))
        ttk.Entry(parent, textvariable=variable, width=width).grid(row=row, column=1, sticky="ew", pady=3)
        return row + 1

    def _combo(
        self,
        parent: ttk.Frame,
        row: int,
        label: str,
        variable: tk.StringVar,
        values: list[str],
        width: int = 24,
    ) -> int:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", pady=3, padx=(0, 8))
        combo = ttk.Combobox(parent, textvariable=variable, values=values, width=width)
        combo.grid(row=row, column=1, sticky="w", pady=3)
        combo.bind("<<ComboboxSelected>>", lambda _event: self._mark_changed())
        return row + 1

    def _bind_shortcuts(self) -> None:
        for sequence in ("<Command-o>", "<Control-o>"):
            self.bind(sequence, lambda _event: self.open_file())
        for sequence in ("<Command-s>", "<Control-s>"):
            self.bind(sequence, lambda _event: self.save_file())
        for sequence in ("<Command-n>", "<Control-n>"):
            self.bind(sequence, lambda _event: self.new_file())

    def _on_select(self, _event: tk.Event | None = None) -> None:
        selection = self.listbox.curselection()
        if not selection:
            return
        index = selection[0]
        if index == self.selected_index:
            return
        if not self._apply_form_to_selected(show_error=True):
            self._refresh_list()
            return
        self._load_form(index)

    def _on_form_change(self, *_args: object) -> None:
        if self._loading_form:
            return
        self._mark_changed()
        self._update_list_label_from_form()

    def _mark_changed(self) -> None:
        if self._loading_form:
            return
        self.dirty = True
        self._update_title()

    def _load_form(self, index: int | None) -> None:
        self._loading_form = True
        self.selected_index = index
        if index is None or index < 0 or index >= len(self.achievements):
            item = default_achievement(1)
        else:
            item = self.achievements[index]
        condition = item["condition"]
        reward = item["reward"]
        self.no_var.set(str(item["no"]))
        self.id_var.set(item["id"])
        self.category_var.set(item["category"])
        self.name_ja_var.set(item["name"]["ja"])
        self.name_en_var.set(item["name"]["en"])
        self.description_ja_var.set(item["description"]["ja"])
        self.description_en_var.set(item["description"]["en"])
        self.condition_type_var.set(condition["type"])
        self.scope_var.set(condition["scope"])
        self.operator_var.set(condition["operator"])
        self.params_var.set(format_params(condition["params"]))
        self.reward_type_var.set(reward["type"])
        self.reward_id_var.set(reward["id"])
        self.hidden_var.set(bool(item["hidden"]))
        self.progress_visible_var.set(bool(item["progressVisible"]))
        self._loading_form = False
        self._update_param_hint()
        self._refresh_selection()

    def _form_to_achievement(self) -> dict:
        no_text = self.no_var.get().strip()
        if no_text == "":
            raise ValueError("NO is required.")
        try:
            no = int(no_text)
        except ValueError as exc:
            raise ValueError("NO must be an integer.") from exc
        item = {
            "no": no,
            "id": self.id_var.get().strip(),
            "category": self.category_var.get().strip(),
            "name": localized(self.name_ja_var.get().strip(), self.name_en_var.get().strip()),
            "description": localized(
                self.description_ja_var.get().strip(),
                self.description_en_var.get().strip(),
            ),
            "condition": {
                "type": self.condition_type_var.get().strip(),
                "scope": self.scope_var.get().strip(),
                "operator": self.operator_var.get().strip(),
                "params": parse_params(self.params_var.get()),
            },
            "reward": {
                "type": self.reward_type_var.get().strip(),
                "id": self.reward_id_var.get().strip(),
            },
            "hidden": bool(self.hidden_var.get()),
            "progressVisible": bool(self.progress_visible_var.get()),
        }
        validate_achievement(item)
        return item

    def _apply_form_to_selected(self, show_error: bool = True) -> bool:
        if self.selected_index is None or self.selected_index >= len(self.achievements):
            return True
        try:
            self.achievements[self.selected_index] = self._form_to_achievement()
        except ValueError as exc:
            if show_error:
                messagebox.showerror("Invalid Achievement", str(exc))
            return False
        self._refresh_list(keep_selection=True)
        return True

    def _refresh_list(self, keep_selection: bool = False) -> None:
        selected = self.selected_index if keep_selection else None
        self.listbox.delete(0, tk.END)
        for item in self.achievements:
            self.listbox.insert(tk.END, self._list_label(item))
        if selected is None:
            selected = self.selected_index
        if selected is not None and 0 <= selected < len(self.achievements):
            self.listbox.selection_set(selected)
            self.listbox.see(selected)
        self._update_title()

    def _refresh_selection(self) -> None:
        self.listbox.selection_clear(0, tk.END)
        if self.selected_index is not None:
            self.listbox.selection_set(self.selected_index)
            self.listbox.see(self.selected_index)

    def _update_list_label_from_form(self) -> None:
        if self.selected_index is None or self.selected_index >= self.listbox.size():
            return
        no = self.no_var.get().strip() or "?"
        ach_id = self.id_var.get().strip() or "(no id)"
        name = self.name_en_var.get().strip() or self.name_ja_var.get().strip() or "(no name)"
        self.listbox.delete(self.selected_index)
        self.listbox.insert(self.selected_index, f"{no:>3}  {ach_id} - {name}")
        self._refresh_selection()

    def _list_label(self, item: dict) -> str:
        name = item["name"].get("en") or item["name"].get("ja") or "(no name)"
        return f"{item['no']:>3}  {item['id']} - {name}"

    def _update_param_hint(self) -> None:
        condition_type = self.condition_type_var.get()
        hint = PARAM_HINTS.get(condition_type, "")
        self.params_hint.configure(text=f"Example: {hint}" if hint else "")

    def new_file(self) -> None:
        if not self._confirm_discard():
            return
        self.current_path = None
        self.achievements = [default_achievement(1)]
        self.dirty = False
        self._load_form(0)
        self._refresh_list(keep_selection=True)
        self.status_var.set(DEFAULT_STATUS)

    def open_file(self) -> None:
        if not self._confirm_discard():
            return
        initial_dir = self._initial_directory()
        path = filedialog.askopenfilename(
            initialdir=initial_dir,
            filetypes=(("JSON files", "*.json"), ("All files", "*.*")),
        )
        if path:
            self._open_file(Path(path), confirm_discard=False)

    def _open_file(self, path: Path, confirm_discard: bool = True) -> None:
        if confirm_discard and not self._confirm_discard():
            return
        try:
            with path.open("r", encoding="utf-8") as handle:
                data = json.load(handle)
            achievements = normalize_file_data(data)
            validate_achievements(achievements)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            messagebox.showerror("Open Failed", str(exc))
            return
        self.current_path = path
        self.achievements = achievements
        self.dirty = False
        self._load_form(0 if achievements else None)
        self._refresh_list(keep_selection=True)
        self._save_settings()
        self.status_var.set(f"Opened {path.name}")

    def save_file(self) -> bool:
        if self.current_path is None:
            return self.save_as()
        return self._save_to(self.current_path)

    def save_as(self) -> bool:
        initial_dir = self._initial_directory()
        initial_file = self.current_path.name if self.current_path else DEFAULT_SAVE_FILENAME
        path_text = filedialog.asksaveasfilename(
            initialdir=initial_dir,
            initialfile=initial_file,
            defaultextension=".json",
            filetypes=(("JSON files", "*.json"), ("All files", "*.*")),
        )
        if not path_text:
            return False
        return self._save_to(Path(path_text))

    def _save_to(self, path: Path) -> bool:
        if not self._apply_form_to_selected(show_error=True):
            return False
        try:
            validate_achievements(self.achievements)
            payload = {"achievements": self.achievements}
            with path.open("w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False, indent=DEFAULT_JSON_INDENT)
                handle.write("\n")
        except (OSError, ValueError) as exc:
            messagebox.showerror("Save Failed", str(exc))
            return False
        self.current_path = path
        self.dirty = False
        self._save_settings()
        self._update_title()
        self.status_var.set(f"Saved {path.name}")
        return True

    def _initial_directory(self) -> Path:
        if self.current_path is not None and self.current_path.is_file():
            return self.current_path.parent
        last_path = self._read_last_opened_file()
        if last_path is not None and last_path.is_file():
            return last_path.parent
        return EDITOR_DIR

    def _read_last_opened_file(self) -> Path | None:
        try:
            settings = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            path_text = settings.get("lastOpenedFile", "")
            if not isinstance(path_text, str) or path_text == "":
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
                json.dumps({"lastOpenedFile": str(self.current_path)}, indent=DEFAULT_JSON_INDENT) + "\n",
                encoding="utf-8",
            )
        except OSError:
            pass

    def add_achievement(self) -> None:
        if not self._apply_form_to_selected(show_error=True):
            return
        next_no = max([item.get("no", 0) for item in self.achievements] + [0]) + 1
        self.achievements.append(default_achievement(next_no))
        self.selected_index = len(self.achievements) - 1
        self._load_form(self.selected_index)
        self._refresh_list(keep_selection=True)
        self._mark_changed()

    def duplicate_achievement(self) -> None:
        if self.selected_index is None:
            return
        if not self._apply_form_to_selected(show_error=True):
            return
        duplicate = copy.deepcopy(self.achievements[self.selected_index])
        duplicate["no"] = max([item.get("no", 0) for item in self.achievements] + [0]) + 1
        duplicate["id"] = f"{duplicate['id']}_copy"
        self.achievements.insert(self.selected_index + 1, duplicate)
        self.selected_index += 1
        self._load_form(self.selected_index)
        self._refresh_list(keep_selection=True)
        self._mark_changed()

    def delete_achievement(self) -> None:
        if self.selected_index is None or not self.achievements:
            return
        if len(self.achievements) == 1:
            messagebox.showinfo("Delete", "At least one achievement is required.")
            return
        item = self.achievements[self.selected_index]
        if not messagebox.askyesno("Delete Achievement", f"Delete {item['id']}?"):
            return
        del self.achievements[self.selected_index]
        self.selected_index = min(self.selected_index, len(self.achievements) - 1)
        self._load_form(self.selected_index)
        self._refresh_list(keep_selection=True)
        self._mark_changed()

    def move_selected(self, direction: int) -> None:
        if self.selected_index is None:
            return
        if not self._apply_form_to_selected(show_error=True):
            return
        new_index = self.selected_index + direction
        if new_index < 0 or new_index >= len(self.achievements):
            return
        self.achievements[self.selected_index], self.achievements[new_index] = (
            self.achievements[new_index],
            self.achievements[self.selected_index],
        )
        self.selected_index = new_index
        self._load_form(new_index)
        self._refresh_list(keep_selection=True)
        self._mark_changed()

    def renumber(self) -> None:
        if not self._apply_form_to_selected(show_error=True):
            return
        for index, item in enumerate(self.achievements, start=1):
            item["no"] = index
        self._load_form(self.selected_index)
        self._refresh_list(keep_selection=True)
        self._mark_changed()

    def validate_dialog(self) -> None:
        if not self._apply_form_to_selected(show_error=True):
            return
        try:
            validate_achievements(self.achievements)
        except ValueError as exc:
            messagebox.showerror("Validation Failed", str(exc))
            return
        messagebox.showinfo("Validation", "Achievements are valid.")
        self.status_var.set("Validation passed")

    def _confirm_discard(self) -> bool:
        if not self.dirty:
            return True
        result = messagebox.askyesnocancel("Unsaved Changes", "Save changes before continuing?")
        if result is None:
            return False
        if result:
            return self.save_file()
        return True

    def _close(self) -> None:
        if self._confirm_discard():
            self.destroy()

    def _update_title(self) -> None:
        name = self.current_path.name if self.current_path else "Untitled"
        mark = "*" if self.dirty else ""
        self.title(f"{name}{mark} - {WINDOW_TITLE}")


def normalize_file_data(data: object) -> list[dict]:
    if isinstance(data, dict) and isinstance(data.get("achievements"), list):
        raw_items = data["achievements"]
    elif isinstance(data, list):
        raw_items = data
    else:
        raise ValueError("JSON must be an array or an object with an achievements array.")
    achievements = [normalize_achievement(raw, index) for index, raw in enumerate(raw_items, start=1)]
    if not achievements:
        achievements = [default_achievement(1)]
    return achievements


def validate_achievement(item: dict) -> None:
    if item["no"] <= 0:
        raise ValueError(f"{item['id']}: NO must be greater than 0.")
    if not ID_PATTERN.match(item["id"]):
        raise ValueError(f"{item['id'] or '(empty id)'}: ID must match {ID_PATTERN.pattern}.")
    if item["category"] not in CATEGORIES:
        raise ValueError(f"{item['id']}: category must be one of {', '.join(CATEGORIES)}.")
    if item["name"]["ja"] == "" and item["name"]["en"] == "":
        raise ValueError(f"{item['id']}: at least one name is required.")
    condition = item["condition"]
    if condition["type"] not in CONDITION_TYPES:
        raise ValueError(f"{item['id']}: condition type is invalid.")
    if condition["scope"] not in SCOPES:
        raise ValueError(f"{item['id']}: condition scope is invalid.")
    if condition["operator"] not in OPERATORS:
        raise ValueError(f"{item['id']}: condition operator is invalid.")
    if not isinstance(condition["params"], dict):
        raise ValueError(f"{item['id']}: condition params must be an object.")
    if item["reward"]["type"] not in REWARD_TYPES:
        raise ValueError(f"{item['id']}: reward type is invalid.")
    if item["reward"]["type"] != "NONE" and item["reward"]["id"] == "":
        raise ValueError(f"{item['id']}: reward id is required when reward type is not NONE.")


def validate_achievements(achievements: list[dict]) -> None:
    if not achievements:
        raise ValueError("At least one achievement is required.")
    ids: set[str] = set()
    numbers: set[int] = set()
    for item in achievements:
        validate_achievement(item)
        if item["id"] in ids:
            raise ValueError(f"Duplicate ID: {item['id']}")
        ids.add(item["id"])
        if item["no"] in numbers:
            raise ValueError(f"Duplicate NO: {item['no']}")
        numbers.add(item["no"])


def main() -> None:
    app = AchievementEditor(tuple(sys.argv[1:]))
    app.mainloop()


if __name__ == "__main__":
    main()

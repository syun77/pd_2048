#!/usr/bin/env python3
"""Playdate 2048 practice-stage editor.

This is intentionally self-contained so it can be run directly with Python 3:
    python3 editor.py
"""

from __future__ import annotations

import copy
import json
import os
import random
import sys
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

# 盤面のサイズ.
BOARD_SIZE = 5
# 最大NEXT数.
MAX_NEXT = 10
# 盤面の中央.
CENTER = (BOARD_SIZE // 2, BOARD_SIZE // 2)  # zero-based
# 1つのセルのサイズ.
CELL_SIZE = 48
MIN_BLOCK_EXPONENT = 1 # 2^1 = 2
MAX_BLOCK_EXPONENT = 11 # 2^11 = 2048
VALUES = [2 ** n for n in range(MIN_BLOCK_EXPONENT, MAX_BLOCK_EXPONENT + 1)]
# デフォルト値.
DEFAULT_STAGE_ID = "001" # ステージID.
DEFAULT_STAGE_LABEL = "NEW STAGE" # ステージラベル.
DEFAULT_DESCRIPTION_JA = ""
DEFAULT_DESCRIPTION_EN = ""
DEFAULT_BLOCK_VALUE = 2 # デフォルトブロック値.
DEFAULT_RANDOM_VALUES = [2, 4] # ランダムブロックの値.
DEFAULT_RANDOM_WEIGHTS = [90, 10] # ランダムブロックの出現確率.
DEFAULT_NEXT_POLICY = "LOOP" # NEXTポリシー: ループ.
RANDOM_NEXT_POLICY = "RANDOM" # NEXTポリシー: ランダム.
FIXED_NEXT_POLICY = "FIXED" # NEXTポリシー: 固定列終了.
DEFAULT_OBJECTIVE_MODE = "ANY"
ALL_OBJECTIVE_MODE = "ALL"
DEFAULT_OBJECTIVE_TYPE = "TILE_VALUE"
DEFAULT_OBJECTIVE_VALUE = 64
DEFAULT_TURN_LIMIT = 0
MAX_TURN_LIMIT = 999
NEXT_POLICY_OPTIONS = [DEFAULT_NEXT_POLICY, FIXED_NEXT_POLICY, RANDOM_NEXT_POLICY]
OBJECTIVE_MODE_OPTIONS = [DEFAULT_OBJECTIVE_MODE, ALL_OBJECTIVE_MODE]
OBJECTIVE_TYPE_OPTIONS = ["TILE_VALUE", "COMBO", "SCORE", "MERGE_COUNT"]
OBJECTIVE_TYPE_LABELS = {
    "TILE_VALUE": "ブロック作成",
    "COMBO": "コンボ数",
    "SCORE": "スコア",
    "MERGE_COUNT": "累計マージ数",
}
OBJECTIVE_TYPE_DISPLAY_OPTIONS = [OBJECTIVE_TYPE_LABELS[key]
                                  for key in OBJECTIVE_TYPE_OPTIONS]
OBJECTIVE_TYPE_VALUES_BY_LABEL = {
    label: value for value, label in OBJECTIVE_TYPE_LABELS.items()
}

# Editor UI parameters
EDITOR_PADDING = 8
BOARD_FRAME_PADDING = 6
BOARD_FRAME_RIGHT_PAD = 10
BOARD_LABEL_TOP_PAD = 6
VALUE_FRAME_PAD_Y = 4
COMBOBOX_PAD_X = 4
FORM_ENTRY_WIDTH = 30
POLICY_COMBOBOX_WIDTH = 10
NEXT_COLUMNS = 5
NEXT_ROW_HEIGHT = 2
NEXT_COMBOBOX_WIDTH = 5
NEXT_BOX_PAD_X = 2
NEXT_BOX_PAD_BOTTOM = 3
FIXED_NEXT_LIST_WIDTH = 18
FIXED_NEXT_LIST_HEIGHT = 10
FIXED_NEXT_EMPTY_LABEL = "---"
FIXED_NEXT_LABEL_PAD_Y = 6
FIXED_NEXT_LIST_BOTTOM_PAD = 6
FIXED_NEXT_DISABLED_BLEND_RATIO = 0.5
FIXED_NEXT_DARK_BACKGROUND_THRESHOLD = 32768
FIXED_NEXT_DARK_FOREGROUND = "#f0f0f0"
FIXED_NEXT_LIGHT_FOREGROUND = "#202020"
FORM_ROW_PAD_Y = 2
DESCRIPTION_ENTRY_WIDTH = 30
OBJECTIVE_FRAME_PADDING = 5
OBJECTIVE_FRAME_TOP_PAD = 8
OBJECTIVE_TYPE_COMBOBOX_WIDTH = 16
OBJECTIVE_VALUE_ENTRY_WIDTH = 10
BUTTONS_PAD_Y = 8
BUTTON_PAD_X = 2
FIRST_BUTTON_RIGHT_PAD = 5
STATUS_COLUMN_COUNT = 2
WINDOW_TITLE = "2048 Practice Stage Editor"
DEFAULT_STATUS = "Ready"
DEFAULT_RANDOM_VALUES_TEXT = "2,4"
DEFAULT_RANDOM_WEIGHTS_TEXT = "90,10"
DEFAULT_OBJECTIVE_VALUE_TEXT = "64"
CANVAS_BACKGROUND = "white"
CELL_OUTLINE = "#777"
CELL_FILL = "#eee"
CENTER_OUTLINE = "#999"
BLOCK_FILL = "#222"
BLOCK_TEXT_FILL = "white"
BLOCK_INSET = 3
CENTER_MARK_SIZE = 24
CENTER_MARK_INSET = (CELL_SIZE - CENTER_MARK_SIZE) // 2
BLOCK_FONT = ("Helvetica", 16, "bold")
VALUE_SELECTOR_FONT = ("Helvetica", 10, "bold")
# 数値選択UIのパラメータ
VALUE_SELECTOR_COLUMNS = 4 # 列の数.
VALUE_SELECTOR_SIZE = 32 # サイズ.
VALUE_SELECTOR_BORDER_WIDTH = 2
VALUE_SELECTOR_ACTIVE_BORDER_WIDTH = 4
VALUE_SELECTOR_PAD_X = 2
VALUE_SELECTOR_PAD_Y = 2

# File and preview parameters
SETTINGS_FILENAME = ".practice_editor_settings.json"
DEFAULT_SAVE_FILENAME = "001.json"
DEFAULT_JSON_INDENT = 2
DEFAULT_RANDOM_SEED = 1
PREVIEW_CELL_SIZE = 72
PREVIEW_TOP = 42
PREVIEW_HEIGHT_EXTRA = 12
PREVIEW_PADDING = 8
PREVIEW_SIDE_PAD = 8
PREVIEW_CONTROLS_TOP_PAD = 12
PREVIEW_CURSOR_TOP_PAD = 8
PREVIEW_LOG_TOP_PAD = 8
PREVIEW_LOG_WIDTH = 64
PREVIEW_LOG_HEIGHT = 13
PREVIEW_BUTTON_PAD_Y = 6
PREVIEW_BLOCK_TOP = 4
PREVIEW_BLOCK_BOTTOM_GAP = 7
PREVIEW_CURSOR_LEFT_INSET = 4
PREVIEW_CURSOR_RIGHT_INSET = 4
PREVIEW_CURSOR_TOP_GAP = 3
PREVIEW_CURSOR_HEIGHT = 5
PREVIEW_CENTER_MARK_INSET = 24
PREVIEW_CENTER_MARK_SIZE = 24
PREVIEW_NEXT_QUEUE_SIZE = 4
PREVIEW_NEXT_DISPLAY_COUNT = 3
PREVIEW_ROTATION_DELAY_MS = 200

# Preview game parameters
INITIAL_CURSOR_COLUMN = BOARD_SIZE // 2
EMPTY_CELL = 0
NO_EVALUATION = 0
EVALUATION_SIDE = 10
EVALUATION_DIRECTION_SIDE = 5
EVALUATION_DIRECTION_VERTICAL = 10
DROP_EVALUATION_MULTIPLIER = 20
SCORE_PER_MERGED_TILE = 100
COMBO_BONUS_MULTIPLIER = 2
COMBO_BONUS_SCALE = 100
NO_HOLD_VALUE = 0
NO_TARGET = 0
HOLD_QUEUE_SIZE = PREVIEW_NEXT_QUEUE_SIZE
ROTATION_EDGE = BOARD_SIZE - 1
DEFAULT_FALLBACK_VALUE = 2
MIN_CURSOR = 0
INVALID_COORDINATE = 0
LOGICAL_COORDINATE_OFFSET = 1
ROTATION_CLOCKWISE = "CLOCKWISE"
ROTATION_COUNTER_CLOCKWISE = "COUNTER-CLOCKWISE"
# キーバインド設定.
KEY_BINDINGS = {
    "open": ("<Command-o>", "<Control-o>"),
    "save": ("<Command-s>", "<Control-s>"),
    "undo": ("<Command-z>", "<Control-z>"),
    "redo": ("<Command-Shift-z>", "<Control-Shift-z>"),
}
EDITOR_DIR = Path(__file__).resolve().parent
SETTINGS_PATH = EDITOR_DIR / SETTINGS_FILENAME


def new_stage() -> dict:
    return {
        "id": DEFAULT_STAGE_ID,
        "label": DEFAULT_STAGE_LABEL,
        "description": {"ja": DEFAULT_DESCRIPTION_JA, "en": DEFAULT_DESCRIPTION_EN},
        "initialBoard": [],
        "nextValues": [DEFAULT_BLOCK_VALUE] * MAX_NEXT,
        "nextPolicy": DEFAULT_NEXT_POLICY,
        "nextRandom": {"values": DEFAULT_RANDOM_VALUES.copy(),
                        "weights": DEFAULT_RANDOM_WEIGHTS.copy()},
        "objectiveMode": DEFAULT_OBJECTIVE_MODE,
        "objectives": [{"type": DEFAULT_OBJECTIVE_TYPE, "value": DEFAULT_OBJECTIVE_VALUE}],
        "turnLimit": DEFAULT_TURN_LIMIT,
    }


class StageEditor(tk.Tk):
    def __init__(self, initial_paths: tuple[str, ...] = ()) -> None:
        super().__init__()
        self.title(WINDOW_TITLE)
        #self.geometry("800x500")
        self.resizable(False, False)
        self.current_path: Path | None = None
        self.dirty = False
        self.history: list[dict] = []
        self.redo_history: list[dict] = []
        self.stage = new_stage()
        self.selected_value = tk.IntVar(value=DEFAULT_BLOCK_VALUE)
        self.id_var = tk.StringVar(value=DEFAULT_STAGE_ID)
        self.label_var = tk.StringVar()
        self.description_ja_var = tk.StringVar(value=DEFAULT_DESCRIPTION_JA)
        self.description_en_var = tk.StringVar(value=DEFAULT_DESCRIPTION_EN)
        self.policy_var = tk.StringVar(value=DEFAULT_NEXT_POLICY)
        self.random_values_var = tk.StringVar(value=DEFAULT_RANDOM_VALUES_TEXT)
        self.random_weights_var = tk.StringVar(value=DEFAULT_RANDOM_WEIGHTS_TEXT)
        self.objective_mode_var = tk.StringVar(value=DEFAULT_OBJECTIVE_MODE)
        self.objective_type_var = tk.StringVar(value=DEFAULT_OBJECTIVE_TYPE)
        self.objective_type_display_var = tk.StringVar()
        self.objective_value_var = tk.StringVar(value=DEFAULT_OBJECTIVE_VALUE_TEXT)
        self.turn_limit_var = tk.StringVar(value=str(DEFAULT_TURN_LIMIT))
        self.turn_limit_var.trace_add("write", lambda *_: self._refresh_next_listbox())
        self.status_var = tk.StringVar(value=DEFAULT_STATUS)
        self.board: list[list[int]] = []
        self.next_vars: list[tk.StringVar] = []
        self.value_tiles: list[tuple[tk.Canvas, int]] = []
        self.next_listbox: tk.Listbox | None = None
        self._updating_next_listbox = False
        self.random_field_widgets: list[tk.Widget] = []
        self._drop_command: str | None = None
        self._build_ui()
        self._bind_shortcuts()
        self._bind_file_drop()
        if initial_paths:
            self._open_file_paths(initial_paths, confirm_discard=False)
        else:
            self._load_last_file()
        self.protocol("WM_DELETE_WINDOW", self._close)

    # ---------- UI ----------
    def _build_ui(self) -> None:
        menu = tk.Menu(self)
        file_menu = tk.Menu(menu, tearoff=False)
        file_menu.add_command(label="New", command=self.new_stage)
        file_menu.add_command(label="Open...", command=self.open_stage)
        file_menu.add_command(label="Save", command=self.save_stage)
        file_menu.add_command(label="Save As...", command=self.save_as)
        file_menu.add_separator()
        file_menu.add_command(label="Exit", command=self._close)
        menu.add_cascade(label="File", menu=file_menu)
        edit_menu = tk.Menu(menu, tearoff=False)
        edit_menu.add_command(label="Undo", command=self.undo)
        edit_menu.add_command(label="Redo", command=self.redo)
        menu.add_cascade(label="Edit", menu=edit_menu)
        self.config(menu=menu)

        root = ttk.Frame(self, padding=EDITOR_PADDING)
        root.grid()
        selector_frame = ttk.LabelFrame(root, text="Block", padding=BOARD_FRAME_PADDING)
        selector_frame.grid(row=0, column=1, rowspan=3, sticky="n",
                            padx=(0, BOARD_FRAME_RIGHT_PAD))
        board_frame = ttk.LabelFrame(root, text="Initial Board", padding=BOARD_FRAME_PADDING)
        board_frame.grid(row=0, column=0, rowspan=3,
                         padx=(0, BOARD_FRAME_RIGHT_PAD), sticky="n")
        self.canvas = tk.Canvas(board_frame, width=CELL_SIZE * BOARD_SIZE,
                                height=CELL_SIZE * BOARD_SIZE, bg=CANVAS_BACKGROUND,
                                highlightthickness=0)
        self.canvas.grid()
        self.canvas.bind("<Button-1>", self._place_block)
        self.canvas.bind("<Button-3>", self._remove_block)
        ttk.Label(board_frame, text="Left: place / Right: remove").grid(
            pady=(BOARD_LABEL_TOP_PAD, 0))
        value_frame = ttk.Frame(selector_frame)
        value_frame.grid(pady=VALUE_FRAME_PAD_Y)
        for index, value in enumerate(VALUES):
            tile = tk.Canvas(
                value_frame,
                width=VALUE_SELECTOR_SIZE,
                height=VALUE_SELECTOR_SIZE,
                bg=CANVAS_BACKGROUND,
                highlightthickness=0,
            )
            tile.grid(
                row=1 + index // VALUE_SELECTOR_COLUMNS,
                column=index % VALUE_SELECTOR_COLUMNS,
                padx=VALUE_SELECTOR_PAD_X,
                pady=VALUE_SELECTOR_PAD_Y,
            )
            tile.bind("<Button-1>", lambda _, value=value: self._select_value(value))
            self.value_tiles.append((tile, value))
        self._update_value_tiles()

        ttk.Label(selector_frame, text="Fixed NEXT (1-10)").grid(
            row=2, column=0, sticky="w",
            pady=(FIXED_NEXT_LABEL_PAD_Y, VALUE_FRAME_PAD_Y))
        next_list_frame = ttk.Frame(selector_frame)
        next_list_frame.grid(row=3, column=0, sticky="w",
                             pady=(0, FIXED_NEXT_LIST_BOTTOM_PAD))
        self.next_listbox = tk.Listbox(
            next_list_frame,
            width=FIXED_NEXT_LIST_WIDTH,
            height=FIXED_NEXT_LIST_HEIGHT,
            selectmode=tk.SINGLE,
            exportselection=False,
        )
        next_scrollbar = ttk.Scrollbar(next_list_frame, orient="vertical",
                                       command=self.next_listbox.yview)
        self.next_listbox.configure(yscrollcommand=next_scrollbar.set)
        self.next_listbox.grid(row=0, column=0, sticky="nsew")
        next_scrollbar.grid(row=0, column=1, sticky="ns")
        next_list_frame.rowconfigure(0, weight=1)
        self.next_listbox.bind("<<ListboxSelect>>", self._select_next_item)
        for i in range(MAX_NEXT):
            var = tk.StringVar(value=str(DEFAULT_BLOCK_VALUE))
            self.next_vars.append(var)
        self._refresh_next_listbox()

        form = ttk.Frame(root)
        form.grid(row=0, column=2, sticky="nw")
        ttk.Label(form, text="Stage ID").grid(row=0, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.id_var, width=FORM_ENTRY_WIDTH).grid(
            row=0, column=1, columnspan=3, sticky="ew", pady=FORM_ROW_PAD_Y)
        ttk.Label(form, text="Label").grid(row=1, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.label_var, width=FORM_ENTRY_WIDTH).grid(
            row=1, column=1, columnspan=3, sticky="ew", pady=FORM_ROW_PAD_Y)
        ttk.Label(form, text="Description JA").grid(row=2, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.description_ja_var,
                  width=DESCRIPTION_ENTRY_WIDTH).grid(
                      row=2, column=1, columnspan=3, sticky="ew",
                      pady=FORM_ROW_PAD_Y)
        ttk.Label(form, text="Description EN").grid(row=3, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.description_en_var,
                  width=DESCRIPTION_ENTRY_WIDTH).grid(
                      row=3, column=1, columnspan=3, sticky="ew",
                      pady=FORM_ROW_PAD_Y)
        ttk.Label(form, text="NEXT mode").grid(row=4, column=0, sticky="w")
        policy = ttk.Combobox(form, textvariable=self.policy_var,
                              values=NEXT_POLICY_OPTIONS, state="readonly",
                              width=POLICY_COMBOBOX_WIDTH)
        policy.grid(row=4, column=1, sticky="w", pady=FORM_ROW_PAD_Y)
        policy.bind("<<ComboboxSelected>>", self._select_next_policy)
        random_values_label = ttk.Label(form, text="Random values")
        random_values_label.grid(row=5, column=0, sticky="w")
        random_values_entry = ttk.Entry(form, textvariable=self.random_values_var, width=20)
        random_values_entry.grid(row=5, column=1, columnspan=3, sticky="w")
        random_weights_label = ttk.Label(form, text="Random weights")
        random_weights_label.grid(row=6, column=0, sticky="w")
        random_weights_entry = ttk.Entry(form, textvariable=self.random_weights_var, width=20)
        random_weights_entry.grid(row=6, column=1, columnspan=3, sticky="w")
        self.random_field_widgets = [
            random_values_label, random_values_entry,
            random_weights_label, random_weights_entry,
        ]

        ttk.Label(form, text="Move Limit (0 = unlimited)").grid(
            row=7, column=0, sticky="w")
        ttk.Spinbox(form, from_=DEFAULT_TURN_LIMIT, to=MAX_TURN_LIMIT,
                    increment=1, textvariable=self.turn_limit_var,
                    width=OBJECTIVE_VALUE_ENTRY_WIDTH).grid(
                        row=7, column=1, sticky="w")

        objective = ttk.LabelFrame(form, text="Clear Objective",
                                   padding=OBJECTIVE_FRAME_PADDING)
        objective.grid(row=8, column=0, columnspan=4, sticky="ew",
                       pady=(OBJECTIVE_FRAME_TOP_PAD, 0))
        ttk.Label(objective, text="Mode").grid(row=0, column=0, sticky="w")
        ttk.Combobox(objective, textvariable=self.objective_mode_var,
                     values=OBJECTIVE_MODE_OPTIONS, state="readonly", width=8).grid(
                         row=0, column=1, sticky="w")
        ttk.Label(objective, text="Type").grid(row=1, column=0, sticky="w")
        objective_type = ttk.Combobox(
                     objective, textvariable=self.objective_type_display_var,
                     values=OBJECTIVE_TYPE_DISPLAY_OPTIONS, state="readonly",
                     width=OBJECTIVE_TYPE_COMBOBOX_WIDTH,
                     )
        objective_type.grid(row=1, column=1, sticky="w")
        objective_type.bind("<<ComboboxSelected>>", self._select_objective_type)
        ttk.Label(objective, text="Value").grid(row=2, column=0, sticky="w")
        ttk.Entry(objective, textvariable=self.objective_value_var,
                  width=OBJECTIVE_VALUE_ENTRY_WIDTH).grid(row=2, column=1, sticky="w")

        buttons = ttk.Frame(root)
        buttons.grid(row=1, column=2, sticky="ew", pady=BUTTONS_PAD_Y)
        ttk.Button(buttons, text="Preview / Check", command=self.preview).grid(
            row=0, column=0, columnspan=2, sticky="w", pady=(0, BUTTON_PAD_X))
        ttk.Label(root, textvariable=self.status_var, anchor="w").grid(
            row=2, column=0, columnspan=3, sticky="ew")
        self._reset_model(new_stage())

    def _bind_shortcuts(self) -> None:
        for key in KEY_BINDINGS["open"]:
            self.bind_all(key, lambda _: self.open_stage())
        for key in KEY_BINDINGS["save"]:
            self.bind_all(key, lambda _: self.save_stage())
        for key in KEY_BINDINGS["undo"]:
            self.bind_all(key, lambda _: self.undo())
        for key in KEY_BINDINGS["redo"]:
            self.bind_all(key, lambda _: self.redo())

    def _bind_file_drop(self) -> None:
        """Register native/optional TkDND callbacks when the Tk build supports them."""
        try:
            self.tk.createcommand("::tk::mac::OpenDocument",
                                  self._open_native_documents)
        except tk.TclError:
            pass

        try:
            self.tk.call("package", "require", "tkdnd")
            self.tk.call("tkdnd::drop_target", "register", self._w, "DND_Files")
            self._drop_command = self.register(self._open_drop_data)
            self.tk.call("bind", self._w, "<<Drop>>", self._drop_command + " %D")
        except tk.TclError:
            # tkdnd is an optional Tk extension. Startup-argument and macOS
            # OpenDocument handling remain available without it.
            self._drop_command = None

    def _open_native_documents(self, *paths: str) -> None:
        self._open_file_paths(tuple(paths))

    def _open_drop_data(self, data: str) -> str:
        try:
            paths = tuple(self.tk.splitlist(data))
        except tk.TclError:
            paths = (data,)
        self._open_file_paths(paths)
        return "copy"

    def _open_file_paths(self, paths: tuple[str, ...],
                         confirm_discard: bool = True) -> None:
        if len(paths) != 1:
            messagebox.showerror("Open failed", "Drop one stage JSON file at a time")
            return
        if confirm_discard and not self._confirm_discard():
            return
        self._load_path(Path(paths[0]).expanduser())

    def _select_value(self, value: int) -> None:
        selected_next = (self.next_listbox.curselection()
                         if self.next_listbox is not None else ())
        if selected_next:
            index = selected_next[0] - 1
            if index >= 0 and self._is_next_item_enabled(index + 1) \
                    and self.next_vars[index].get() != str(value):
                self._mark_changed()
                self.next_vars[index].set(str(value))
                self._refresh_next_listbox()
        self.selected_value.set(value)
        self._update_value_tiles()

    def _select_objective_type(self, _event=None) -> None:
        display_value = self.objective_type_display_var.get()
        internal_value = OBJECTIVE_TYPE_VALUES_BY_LABEL.get(display_value)
        if internal_value is None or internal_value == self.objective_type_var.get():
            return
        self._mark_changed()
        self.objective_type_var.set(internal_value)

    def _select_next_policy(self, _event=None) -> None:
        self._mark_changed()
        self._update_random_fields_visibility()

    def _update_random_fields_visibility(self) -> None:
        if self.policy_var.get() == RANDOM_NEXT_POLICY:
            for widget in self.random_field_widgets:
                widget.grid()
        else:
            for widget in self.random_field_widgets:
                widget.grid_remove()

    def _select_next_item(self, _event=None) -> None:
        if self._updating_next_listbox or self.next_listbox is None:
            return
        selected = self.next_listbox.curselection()
        if not selected:
            return
        index = selected[0] - 1
        if index >= 0 and not self._is_next_item_enabled(index + 1):
            self.next_listbox.selection_clear(0, tk.END)
            return
        if index < 0 or self.next_vars[index].get() == str(self.selected_value.get()):
            return
        self._mark_changed()
        self.next_vars[index].set(str(self.selected_value.get()))
        self._refresh_next_listbox()

    def _is_next_item_enabled(self, item_number: int) -> bool:
        try:
            turn_limit = int(self.turn_limit_var.get())
        except ValueError:
            turn_limit = DEFAULT_TURN_LIMIT
        return turn_limit <= DEFAULT_TURN_LIMIT or item_number <= turn_limit

    def _get_list_foregrounds(self) -> tuple[str, str]:
        """Return theme-aware normal and subdued Listbox text colors."""
        if self.next_listbox is None:
            return FIXED_NEXT_LIGHT_FOREGROUND, "#888888"
        try:
            background = self.next_listbox.winfo_rgb(
                self.next_listbox.cget("background"))
        except tk.TclError:
            return FIXED_NEXT_LIGHT_FOREGROUND, "#888888"
        background_luminance = sum(background) / len(background)
        normal = (FIXED_NEXT_DARK_FOREGROUND
                  if background_luminance < FIXED_NEXT_DARK_BACKGROUND_THRESHOLD
                  else FIXED_NEXT_LIGHT_FOREGROUND)
        foreground = self.next_listbox.winfo_rgb(normal)
        ratio = FIXED_NEXT_DISABLED_BLEND_RATIO
        blended = tuple(
            round(bg + (fg - bg) * ratio)
            for fg, bg in zip(foreground, background)
        )
        disabled = "#%02x%02x%02x" % tuple(channel // 256 for channel in blended)
        return normal, disabled

    def _refresh_next_listbox(self) -> None:
        if self.next_listbox is None:
            return
        selected = self.next_listbox.curselection()
        selected_index = selected[0] if selected else None
        try:
            turn_limit = int(self.turn_limit_var.get())
        except ValueError:
            turn_limit = DEFAULT_TURN_LIMIT
        normal_foreground, disabled_foreground = self._get_list_foregrounds()
        self._updating_next_listbox = True
        try:
            self.next_listbox.delete(0, tk.END)
            self.next_listbox.insert(tk.END, FIXED_NEXT_EMPTY_LABEL)
            for index, var in enumerate(self.next_vars):
                self.next_listbox.insert(tk.END, f"{index + 1:02}: {var.get()}")
                if turn_limit > DEFAULT_TURN_LIMIT and index + 1 > turn_limit:
                    self.next_listbox.itemconfigure(
                        index + 1,
                        foreground=disabled_foreground)
                else:
                    self.next_listbox.itemconfigure(
                        index + 1, foreground=normal_foreground)
            selected_is_enabled = (
                selected_index is not None
                and (selected_index == 0
                     or turn_limit <= DEFAULT_TURN_LIMIT
                     or selected_index <= turn_limit)
            )
            if selected_is_enabled and selected_index <= len(self.next_vars):
                self.next_listbox.selection_set(selected_index)
                self.next_listbox.activate(selected_index)
            elif selected_index is not None:
                self.next_listbox.selection_clear(0, tk.END)
        finally:
            self._updating_next_listbox = False

    def _update_value_tiles(self) -> None:
        selected_value = self.selected_value.get()
        for tile, value in self.value_tiles:
            is_selected = value == selected_value
            border_width = (VALUE_SELECTOR_ACTIVE_BORDER_WIDTH
                            if is_selected else VALUE_SELECTOR_BORDER_WIDTH)
            tile.delete("all")
            tile.create_rectangle(
                border_width // 2,
                border_width // 2,
                VALUE_SELECTOR_SIZE - border_width // 2,
                VALUE_SELECTOR_SIZE - border_width // 2,
                fill=BLOCK_FILL,
                outline=BLOCK_TEXT_FILL if is_selected else CELL_OUTLINE,
                width=border_width,
            )
            tile.create_text(
                VALUE_SELECTOR_SIZE / 2,
                VALUE_SELECTOR_SIZE / 2,
                text=str(value),
                fill=BLOCK_TEXT_FILL,
                font=VALUE_SELECTOR_FONT,
            )

    # ---------- Model ----------
    def _reset_model(self, stage: dict) -> None:
        self.stage = copy.deepcopy(stage)
        self.board = [[EMPTY_CELL for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
        for block in self.stage.get("initialBoard", []):
            if LOGICAL_COORDINATE_OFFSET <= block.get("x", INVALID_COORDINATE) <= BOARD_SIZE and LOGICAL_COORDINATE_OFFSET <= block.get("y", INVALID_COORDINATE) <= BOARD_SIZE:
                self.board[block["y"] - 1][block["x"] - 1] = block.get("value", EMPTY_CELL)
        self.id_var.set(str(self.stage.get("id", DEFAULT_STAGE_ID)))
        self.label_var.set(self.stage.get("label", ""))
        description = self.stage.get("description", {})
        if isinstance(description, str):
            self.description_ja_var.set("")
            self.description_en_var.set(description)
        else:
            self.description_ja_var.set(description.get("ja", ""))
            self.description_en_var.set(description.get("en", ""))
        self.policy_var.set(self.stage.get("nextPolicy", DEFAULT_NEXT_POLICY))
        self._update_random_fields_visibility()
        values = self.stage.get("nextValues", [])
        for i, var in enumerate(self.next_vars):
            var.set(str(values[i]) if i < len(values) else str(DEFAULT_BLOCK_VALUE))
        self._refresh_next_listbox()
        random_data = self.stage.get("nextRandom", {})
        self.random_values_var.set(",".join(map(str, random_data.get("values", DEFAULT_RANDOM_VALUES))))
        self.random_weights_var.set(",".join(map(str, random_data.get("weights", DEFAULT_RANDOM_WEIGHTS))))
        self.objective_mode_var.set(self.stage.get("objectiveMode", DEFAULT_OBJECTIVE_MODE))
        objective = (self.stage.get("objectives") or
                     [{"type": DEFAULT_OBJECTIVE_TYPE, "value": DEFAULT_OBJECTIVE_VALUE}])[0]
        objective_type = objective.get("type", DEFAULT_OBJECTIVE_TYPE)
        self.objective_type_var.set(objective_type)
        self.objective_type_display_var.set(
            OBJECTIVE_TYPE_LABELS.get(objective_type,
                                      OBJECTIVE_TYPE_LABELS[DEFAULT_OBJECTIVE_TYPE]))
        self.objective_value_var.set(str(objective.get("value", DEFAULT_OBJECTIVE_VALUE)))
        self.turn_limit_var.set(str(self.stage.get("turnLimit", DEFAULT_TURN_LIMIT)))
        self._draw_board()

    def _snapshot(self) -> dict:
        return {
            "board": copy.deepcopy(self.board),
            "id": self.id_var.get(),
            "label": self.label_var.get(),
            "description_ja": self.description_ja_var.get(),
            "description_en": self.description_en_var.get(),
            "policy": self.policy_var.get(),
            "next": [v.get() for v in self.next_vars],
            "random_values": self.random_values_var.get(),
            "random_weights": self.random_weights_var.get(),
            "objective_mode": self.objective_mode_var.get(),
            "objective_type": self.objective_type_var.get(),
            "objective_value": self.objective_value_var.get(),
            "turn_limit": self.turn_limit_var.get(),
        }

    def _restore_snapshot(self, snapshot: dict) -> None:
        self.board = copy.deepcopy(snapshot["board"])
        self.id_var.set(snapshot["id"])
        self.label_var.set(snapshot["label"])
        self.description_ja_var.set(snapshot["description_ja"])
        self.description_en_var.set(snapshot["description_en"])
        self.policy_var.set(snapshot["policy"])
        for var, value in zip(self.next_vars, snapshot["next"]):
            var.set(value)
        self._refresh_next_listbox()
        self.random_values_var.set(snapshot["random_values"])
        self.random_weights_var.set(snapshot["random_weights"])
        self.objective_mode_var.set(snapshot["objective_mode"])
        self.objective_type_var.set(snapshot["objective_type"])
        self.objective_type_display_var.set(
            OBJECTIVE_TYPE_LABELS.get(snapshot["objective_type"],
                                      OBJECTIVE_TYPE_LABELS[DEFAULT_OBJECTIVE_TYPE]))
        self.objective_value_var.set(snapshot["objective_value"])
        self.turn_limit_var.set(snapshot["turn_limit"])
        self._draw_board()

    def _mark_changed(self) -> None:
        self.history.append(self._snapshot())
        self.redo_history.clear()
        self.dirty = True
        self._update_title()

    # ---------- Board ----------
    def _draw_board(self) -> None:
        self.canvas.delete("all")
        for y in range(BOARD_SIZE):
            for x in range(BOARD_SIZE):
                left, top = x * CELL_SIZE, y * CELL_SIZE
                self.canvas.create_rectangle(left, top, left + CELL_SIZE, top + CELL_SIZE,
                                             outline=CELL_OUTLINE, fill=CELL_FILL)
                if (x, y) == CENTER:
                    self.canvas.create_oval(left + CENTER_MARK_INSET,
                                            top + CENTER_MARK_INSET,
                                            left + CENTER_MARK_INSET + CENTER_MARK_SIZE,
                                            top + CENTER_MARK_INSET + CENTER_MARK_SIZE,
                                            outline=CENTER_OUTLINE)
                value = self.board[y][x]
                if value != EMPTY_CELL:
                    self.canvas.create_rectangle(left + BLOCK_INSET, top + BLOCK_INSET,
                                                 left + CELL_SIZE - BLOCK_INSET,
                                                 top + CELL_SIZE - BLOCK_INSET,
                                                 fill=BLOCK_FILL, outline=BLOCK_FILL)
                    self.canvas.create_text(left + CELL_SIZE / 2, top + CELL_SIZE / 2,
                                            text=str(value), fill=BLOCK_TEXT_FILL,
                                            font=BLOCK_FONT)

    def _cell_from_event(self, event) -> tuple[int, int] | None:
        x, y = event.x // CELL_SIZE, event.y // CELL_SIZE
        if not (0 <= x < BOARD_SIZE and 0 <= y < BOARD_SIZE) or (x, y) == CENTER:
            return None
        return x, y

    def _place_block(self, event) -> None:
        cell = self._cell_from_event(event)
        if cell is None:
            self.status_var.set("The center cell cannot contain a block")
            return
        self._mark_changed()
        x, y = cell
        self.board[y][x] = self.selected_value.get()
        self._draw_board()

    def _remove_block(self, event) -> None:
        cell = self._cell_from_event(event)
        if cell is None or self.board[cell[1]][cell[0]] == EMPTY_CELL:
            return
        self._mark_changed()
        self.board[cell[1]][cell[0]] = EMPTY_CELL
        self._draw_board()

    # ---------- File operations ----------
    def _collect_stage(self) -> dict:
        values = [int(var.get()) for var in self.next_vars]
        random_values = [int(x.strip()) for x in self.random_values_var.get().split(",") if x.strip()]
        random_weights = [int(x.strip()) for x in self.random_weights_var.get().split(",") if x.strip()]
        objective_value = int(self.objective_value_var.get())
        turn_limit = int(self.turn_limit_var.get())
        blocks = [{"x": x + 1, "y": y + 1, "value": self.board[y][x]}
                  for y in range(BOARD_SIZE) for x in range(BOARD_SIZE)
                  if self.board[y][x]]
        return {
            "id": self.id_var.get().strip(),
            "label": self.label_var.get().strip(),
            "description": {
                "ja": self.description_ja_var.get().strip(),
                "en": self.description_en_var.get().strip(),
            },
            "initialBoard": blocks,
            "nextValues": values,
            "nextPolicy": self.policy_var.get(),
            "nextRandom": {"values": random_values, "weights": random_weights},
            "objectiveMode": self.objective_mode_var.get(),
            "objectives": [{"type": self.objective_type_var.get(), "value": objective_value}],
            "turnLimit": turn_limit,
        }

    def _validate(self, stage: dict) -> list[str]:
        errors = []
        if not stage["id"]:
            errors.append("Stage ID is required")
        if not stage["label"]:
            errors.append("Label is required")
        description = stage.get("description", {})
        if isinstance(description, str):
            pass
        elif not isinstance(description, dict):
            errors.append("Description must be an object")
        else:
            if not isinstance(description.get("ja", ""), str):
                errors.append("Japanese description must be text")
            if not isinstance(description.get("en", ""), str):
                errors.append("English description must be text")
        if len(stage["nextValues"]) != MAX_NEXT:
            errors.append("NEXT must contain 10 values")
        for block in stage["initialBoard"]:
            if (block["x"], block["y"]) == (INITIAL_CURSOR_COLUMN + 1, INITIAL_CURSOR_COLUMN + 1):
                errors.append("The center cell cannot contain a block")
            if block["value"] not in VALUES:
                errors.append(f"Invalid block value: {block['value']}")
        random_data = stage["nextRandom"]
        if stage["nextPolicy"] == RANDOM_NEXT_POLICY:
            if not random_data["values"]:
                errors.append("Random mode needs at least one value")
            if len(random_data["values"]) != len(random_data["weights"]):
                errors.append("Random values and weights must have the same length")
            if any(value not in VALUES for value in random_data["values"]):
                errors.append("Random values must be powers of two")
            if any(weight < 0 for weight in random_data["weights"]):
                errors.append("Random weights cannot be negative")
        if stage["objectives"][0]["value"] <= 0:
            errors.append("Objective value must be positive")
        if stage.get("turnLimit", DEFAULT_TURN_LIMIT) < DEFAULT_TURN_LIMIT:
            errors.append("Move limit cannot be negative")
        return errors

    def save_stage(self) -> None:
        if self.current_path is None:
            self.save_as()
            return
        stage = self._collect_stage()
        errors = self._validate(stage)
        if errors:
            messagebox.showerror("Cannot save", "\n".join(errors))
            return
        self.current_path.write_text(json.dumps(stage, ensure_ascii=False,
                                                indent=DEFAULT_JSON_INDENT) + "\n",
                                     encoding="utf-8")
        self.stage = stage
        self.dirty = False
        self._save_settings()
        self._update_title()
        self.status_var.set(f"Saved: {self.current_path.name}")

    def save_as(self) -> None:
        path = filedialog.asksaveasfilename(initialdir=str(self._file_dialog_initial_dir()),
                                            initialfile=DEFAULT_SAVE_FILENAME,
                                            defaultextension=".json",
                                            filetypes=[("JSON", "*.json")])
        if path:
            self.current_path = Path(path)
            self.save_stage()

    def open_stage(self) -> None:
        if not self._confirm_discard():
            return
        path = filedialog.askopenfilename(initialdir=str(self._file_dialog_initial_dir()),
                                          filetypes=[("JSON", "*.json")])
        if path:
            self._load_path(Path(path))

    def _file_dialog_initial_dir(self) -> Path:
        if self.current_path is not None and self.current_path.is_file():
            return self.current_path.parent
        return EDITOR_DIR

    def _load_path(self, path: Path) -> None:
        try:
            stage = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(stage, dict):
                raise ValueError("The stage JSON root must be an object")
            stage.setdefault("id", DEFAULT_STAGE_ID)
            stage.setdefault("label", path.stem)
            stage.setdefault("description", {"ja": DEFAULT_DESCRIPTION_JA,
                                             "en": DEFAULT_DESCRIPTION_EN})
            stage.setdefault("initialBoard", [])
            stage.setdefault("nextValues", [DEFAULT_BLOCK_VALUE] * MAX_NEXT)
            stage.setdefault("nextPolicy", DEFAULT_NEXT_POLICY)
            stage.setdefault("nextRandom", {"values": DEFAULT_RANDOM_VALUES.copy(),
                                             "weights": DEFAULT_RANDOM_WEIGHTS.copy()})
            stage.setdefault("objectiveMode", DEFAULT_OBJECTIVE_MODE)
            stage.setdefault("objectives", [{"type": DEFAULT_OBJECTIVE_TYPE,
                                              "value": DEFAULT_OBJECTIVE_VALUE}])
            stage.setdefault("turnLimit", DEFAULT_TURN_LIMIT)
            errors = self._validate(stage)
            if errors:
                raise ValueError("\n".join(errors))
        except (OSError, ValueError, TypeError, KeyError, IndexError,
                json.JSONDecodeError) as exc:
            messagebox.showerror("Open failed", str(exc))
            return
        self.current_path = path
        self.history.clear()
        self.redo_history.clear()
        self.dirty = False
        self._reset_model(stage)
        self._save_settings()
        self._update_title()
        self.status_var.set(f"Opened: {path.name}")

    def new_stage(self) -> None:
        if not self._confirm_discard():
            return
        self.current_path = None
        self.history.clear()
        self.redo_history.clear()
        self.dirty = False
        self._reset_model(new_stage())
        self._update_title()

    def _load_last_file(self) -> None:
        try:
            settings = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            path = Path(settings.get("lastOpenedFile", ""))
            if path.is_file():
                self._load_path(path)
        except (OSError, ValueError, json.JSONDecodeError):
            pass

    def _save_settings(self) -> None:
        if self.current_path is not None:
            SETTINGS_PATH.write_text(
                json.dumps({"lastOpenedFile": str(self.current_path)},
                           indent=DEFAULT_JSON_INDENT) + "\n", encoding="utf-8")

    def _confirm_discard(self) -> bool:
        if not self.dirty:
            return True
        answer = messagebox.askyesnocancel("Unsaved changes", "Save changes first?")
        if answer is None:
            return False
        if answer:
            self.save_stage()
            return not self.dirty
        return True

    def _update_title(self) -> None:
        name = self.current_path.name if self.current_path else "Untitled"
        self.title(name + ("*" if self.dirty else "") + " - " + WINDOW_TITLE)

    # ---------- Undo / redo ----------
    def undo(self) -> None:
        if not self.history:
            return
        self.redo_history.append(self._snapshot())
        self._restore_snapshot(self.history.pop())
        self.dirty = True
        self._update_title()

    def redo(self) -> None:
        if not self.redo_history:
            return
        self.history.append(self._snapshot())
        self._restore_snapshot(self.redo_history.pop())
        self.dirty = True
        self._update_title()

    # ---------- Preview ----------
    def preview(self) -> None:
        stage = self._collect_stage()
        errors = self._validate(stage)
        if errors:
            messagebox.showerror("Preview unavailable", "\n".join(errors))
            return
        PreviewWindow(self, stage)

    def _close(self) -> None:
        if self._confirm_discard():
            self.destroy()


class PreviewWindow(tk.Toplevel):
    """A playable, non-animated approximation of the Playdate game loop."""

    def __init__(self, parent: StageEditor, stage: dict) -> None:
        super().__init__(parent)
        self.parent_editor = parent
        self.stage = copy.deepcopy(stage)
        self.title(f"Preview - {stage['label']}")
        self.resizable(False, False)
        self.board = [[EMPTY_CELL for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
        for block in stage.get("initialBoard", []):
            self.board[block["y"] - 1][block["x"] - 1] = block["value"]
        self.cursor = INITIAL_CURSOR_COLUMN
        self.next_index = MIN_CURSOR
        self.current_value = EMPTY_CELL
        self.next_queue: list[int] = []
        self.hold_value = NO_HOLD_VALUE
        self.hold_available = True
        self.score = NO_EVALUATION
        self.combo = NO_EVALUATION
        self.merge_count = NO_EVALUATION
        self.turn = NO_EVALUATION
        self.turn_limit = self.stage.get("turnLimit", DEFAULT_TURN_LIMIT)
        self.random = random.Random(stage.get("randomSeed", DEFAULT_RANDOM_SEED))
        self.complete = False
        self.game_over = False
        self.failure_reason = None
        self.drop_pending = False
        self.drop_after_id = None
        self.cursor_var = tk.StringVar()
        self.info_var = tk.StringVar()
        self._build_ui()
        self.reset()
        self.focus_force()
        self.bind("<Left>", lambda _: self.move_cursor(-1))
        self.bind("<Right>", lambda _: self.move_cursor(1))
        self.bind("<Down>", lambda _: self.drop())
        self.bind("<space>", lambda _: self.drop())
        self.bind("<KeyPress-s>", lambda _: self.hold()) # Playdate Simulatorの操作に合わせて "S"キーでもホールド可能.
        self.bind("<KeyPress-h>", lambda _: self.hold())
        self.bind("<KeyPress-H>", lambda _: self.hold())
        self.bind("<KeyPress-r>", lambda _: self.reset())
        self.bind("<KeyPress-R>", lambda _: self.reset())

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=PREVIEW_PADDING)
        root.grid()
        self.canvas = tk.Canvas(root, width=PREVIEW_CELL_SIZE * BOARD_SIZE,
                                height=PREVIEW_TOP + PREVIEW_CELL_SIZE * BOARD_SIZE
                                + PREVIEW_HEIGHT_EXTRA,
                                bg=CANVAS_BACKGROUND, highlightthickness=0)
        self.canvas.grid(row=0, column=0, rowspan=2, padx=(0, PREVIEW_SIDE_PAD))
        side = ttk.Frame(root)
        side.grid(row=0, column=1, sticky="n")
        ttk.Label(side, textvariable=self.info_var, justify="left").grid(sticky="w")
        ttk.Label(side, text="Controls").grid(
            sticky="w", pady=(PREVIEW_CONTROLS_TOP_PAD, 0))
        ttk.Label(side, text="←/→ Move   ↓/Space Drop\nH Hold   R Reset").grid(sticky="w")
        ttk.Label(side, textvariable=self.cursor_var).grid(
            sticky="w", pady=(PREVIEW_CURSOR_TOP_PAD, 0))
        ttk.Label(root, text="Event log").grid(row=2, column=0, columnspan=2,
                                               sticky="w", pady=(PREVIEW_LOG_TOP_PAD, 0))
        self.log = tk.Text(root, width=PREVIEW_LOG_WIDTH, height=PREVIEW_LOG_HEIGHT,
                           state="disabled", background="#f5f5f5")
        self.log.grid(row=3, column=0, columnspan=2)
        ttk.Button(root, text="Reset", command=self.reset).grid(row=4, column=0,
                                                                  columnspan=2,
                                                                  pady=PREVIEW_BUTTON_PAD_Y)

    def _log(self, message: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", message + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def reset(self) -> None:
        if self.drop_after_id is not None:
            self.after_cancel(self.drop_after_id)
            self.drop_after_id = None
        self.drop_pending = False
        self.board = [[EMPTY_CELL for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
        for block in self.stage.get("initialBoard", []):
            self.board[block["y"] - 1][block["x"] - 1] = block["value"]
        self.cursor = INITIAL_CURSOR_COLUMN
        self.next_index = MIN_CURSOR
        self.next_queue = []
        self.hold_value = NO_HOLD_VALUE
        self.hold_available = True
        self.score = NO_EVALUATION
        self.combo = NO_EVALUATION
        self.merge_count = NO_EVALUATION
        self.turn = NO_EVALUATION
        self.turn_limit = self.stage.get("turnLimit", DEFAULT_TURN_LIMIT)
        self.complete = False
        self.game_over = False
        self.failure_reason = None
        self.random = random.Random(self.stage.get("randomSeed", DEFAULT_RANDOM_SEED))
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")
        self._ensure_queue(PREVIEW_NEXT_QUEUE_SIZE)
        self.current_value = self.next_queue.pop(0)
        self._ensure_queue(PREVIEW_NEXT_QUEUE_SIZE)
        self._log(f"RESET  board loaded, current={self.current_value}")
        self._check_objective()
        self._draw()

    def _random_value(self) -> int:
        data = self.stage.get("nextRandom", {})
        values = data.get("values", DEFAULT_RANDOM_VALUES)
        weights = data.get("weights", DEFAULT_RANDOM_WEIGHTS)
        if not values or len(values) != len(weights):
            return DEFAULT_FALLBACK_VALUE
        return self.random.choices(values, weights=weights, k=1)[0]

    def _next_value(self) -> int | None:
        if self.stage.get("nextPolicy", DEFAULT_NEXT_POLICY) == RANDOM_NEXT_POLICY:
            return self._random_value()
        values = self.stage.get("nextValues", [DEFAULT_BLOCK_VALUE]) or [DEFAULT_BLOCK_VALUE]
        if self.stage.get("nextPolicy", DEFAULT_NEXT_POLICY) == FIXED_NEXT_POLICY:
            if self.next_index >= len(values):
                return None
            value = values[self.next_index]
            self.next_index += 1
            return value
        value = values[self.next_index % len(values)]
        self.next_index += 1
        return value

    def _ensure_queue(self, count: int) -> None:
        while len(self.next_queue) < count:
            value = self._next_value()
            if value is None:
                return
            self.next_queue.append(value)

    def _is_playable(self, x: int, y: int) -> bool:
        return 0 <= x < BOARD_SIZE and 0 <= y < BOARD_SIZE and (x, y) != CENTER

    def _occupied(self, x: int, y: int) -> bool:
        return self._is_playable(x, y) and self.board[y][x] != EMPTY_CELL

    def _find_drop_cell(self, column: int) -> tuple[int, int] | None:
        for y in range(BOARD_SIZE):
            if (column, y) == CENTER or self.board[y][column] != 0:
                return None
            supported = (self._occupied(column, y + 1)
                         or (column == INITIAL_CURSOR_COLUMN and y == INITIAL_CURSOR_COLUMN - 1)
                         or self._occupied(column - 1, y)
                         or self._occupied(column + 1, y))
            if supported:
                return column, y
        return None

    def _keeps_connected(self, source: tuple[int, int], target: tuple[int, int]) -> bool:
        sx, sy = source
        tx, ty = target
        for x, y in ((tx - 1, ty), (tx + 1, ty), (tx, ty - 1), (tx, ty + 1)):
            if (x, y) != source and self._occupied(x, y):
                return True
        return False

    def _find_merge(self, x: int, y: int) -> tuple[tuple[int, int], tuple[int, int]] | None:
        value = self.board[y][x]
        fallback = None
        for dx, dy in ((0, 1), (-1, 0), (1, 0), (0, -1)):
            target = (x + dx, y + dy)
            if self._is_playable(*target) and self.board[target[1]][target[0]] == value:
                if self._keeps_connected((x, y), target):
                    return (x, y), target
                if fallback is None:
                    fallback = ((x, y), target)
        return fallback

    @staticmethod
    def _position_evaluation(x: int) -> int:
        if x > INITIAL_CURSOR_COLUMN:
            return EVALUATION_SIDE
        if x < INITIAL_CURSOR_COLUMN:
            return -EVALUATION_SIDE
        return NO_EVALUATION

    def _merge_evaluation(self, source: tuple[int, int], target: tuple[int, int]) -> int:
        sx, _ = source
        tx, _ = target
        direction = (-EVALUATION_DIRECTION_SIDE if tx < sx
                     else EVALUATION_DIRECTION_SIDE if tx > sx
                     else EVALUATION_DIRECTION_VERTICAL * self._position_evaluation(tx))
        return (-EVALUATION_DIRECTION_VERTICAL * self._position_evaluation(sx)
                + EVALUATION_DIRECTION_VERTICAL * self._position_evaluation(tx)
                + direction)

    def _rotate(self, clockwise: bool) -> None:
        rotated = [[EMPTY_CELL for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
        for y in range(BOARD_SIZE):
            for x in range(BOARD_SIZE):
                if not self._is_playable(x, y) or not self.board[y][x]:
                    continue
                nx, ny = (ROTATION_EDGE - y, x) if clockwise else (y, ROTATION_EDGE - x)
                if self._is_playable(nx, ny):
                    rotated[ny][nx] = self.board[y][x]
        self.board = rotated

    def _resolve(self, active: tuple[int, int], evaluation: int) -> None:
        while True:
            merge = self._find_merge(*active)
            if merge is None:
                break
            source, target = merge
            value = self.board[source[1]][source[0]] * 2
            self.board[source[1]][source[0]] = EMPTY_CELL
            self.board[target[1]][target[0]] = value
            self.combo += 1
            self.merge_count += 1
            bonus = int(COMBO_BONUS_MULTIPLIER * self.combo ** 1.5
                        - COMBO_BONUS_MULTIPLIER * (self.combo - 1) ** 1.5)
            self.score += value * SCORE_PER_MERGED_TILE + bonus * COMBO_BONUS_SCALE
            evaluation += self._merge_evaluation(source, target)
            active = target
            self._log(f"MERGE {value // 2}+{value // 2}={value} at ({target[0] + 1},{target[1] + 1})")
        if evaluation:
            clockwise = evaluation > 0
            self._rotate(clockwise)
            self._draw_now()
            x, y = active
            active = (ROTATION_EDGE - y, x) if clockwise else (y, ROTATION_EDGE - x)
            self._log("ROTATE " + (ROTATION_CLOCKWISE if clockwise
                                     else ROTATION_COUNTER_CLOCKWISE))
            self._resolve_after_rotation(active)

    def _draw_now(self) -> None:
        """Redraw the preview immediately, including delayed rotation updates."""
        self._draw()
        self.update_idletasks()
        self.update()

    def _resolve_after_rotation(self, active: tuple[int, int]) -> None:
        while True:
            merge = self._find_merge(*active)
            if merge is None:
                return
            source, target = merge
            value = self.board[source[1]][source[0]] * 2
            self.board[source[1]][source[0]] = EMPTY_CELL
            self.board[target[1]][target[0]] = value
            self.combo += 1
            self.merge_count += 1
            bonus = int(COMBO_BONUS_MULTIPLIER * self.combo ** 1.5
                        - COMBO_BONUS_MULTIPLIER * (self.combo - 1) ** 1.5)
            self.score += value * SCORE_PER_MERGED_TILE + bonus * COMBO_BONUS_SCALE
            active = target
            self._log(f"MERGE AFTER ROTATION -> {value}")

    def drop(self) -> None:
        if self.complete or self.game_over or self.drop_pending:
            return
        cell = self._find_drop_cell(self.cursor)
        if cell is None:
            self._log(f"DROP column={self.cursor + 1} -> NO SPACE")
            self._draw()
            return
        x, y = cell
        self.combo = 0
        self.board[y][x] = self.current_value
        self._draw_now()
        self.turn += 1
        self._log(f"DROP column={x + 1} cell=({x + 1},{y + 1}) value={self.current_value}")
        evaluation = self._position_evaluation(x) * DROP_EVALUATION_MULTIPLIER
        self.drop_pending = True
        self.drop_after_id = self.after(
            PREVIEW_ROTATION_DELAY_MS,
            lambda: self._finish_drop((x, y), evaluation),
        )

    def _finish_drop(self, active: tuple[int, int], evaluation: int) -> None:
        self.drop_after_id = None
        if self.complete or self.game_over:
            self.drop_pending = False
            return
        self._resolve(active, evaluation)
        self.drop_pending = False
        self.hold_available = True
        self._ensure_queue(PREVIEW_NEXT_QUEUE_SIZE)
        self.current_value = self.next_queue.pop(0) if self.next_queue else None
        self._ensure_queue(PREVIEW_NEXT_QUEUE_SIZE)
        self._check_objective()
        if self.current_value is None and not self.complete:
            self._fail("*** FAILED: FIXED NEXT EXHAUSTED ***")
        if (not self.complete and self.turn_limit > DEFAULT_TURN_LIMIT
                and self.turn >= self.turn_limit):
            self._fail("*** FAILED: MOVE LIMIT REACHED ***")
        if not self.complete and not any(self._find_drop_cell(column)
                                         for column in range(BOARD_SIZE)):
            self._fail("*** FAILED: NO DROP AVAILABLE ***")
        self._draw_now()

    def hold(self) -> None:
        if self.complete or self.game_over or self.drop_pending:
            return
        if not self.hold_available:
            self._log("HOLD -> UNAVAILABLE")
            return
        if self.hold_value == NO_HOLD_VALUE:
            self.hold_value = self.current_value
            self._ensure_queue(HOLD_QUEUE_SIZE)
            self.current_value = (self.next_queue.pop(0)
                                  if self.next_queue else None)
            self._ensure_queue(PREVIEW_NEXT_QUEUE_SIZE)
            self._log(f"HOLD {self.hold_value}; next current={self.current_value}")
            if self.current_value is None:
                self._fail("*** FAILED: FIXED NEXT EXHAUSTED ***")
        else:
            self.current_value, self.hold_value = self.hold_value, self.current_value
            self._log(f"HOLD SWAP current={self.current_value} hold={self.hold_value}")
        self.hold_available = False
        self._draw()

    def move_cursor(self, delta: int) -> None:
        if self.drop_pending:
            return
        self.cursor = max(MIN_CURSOR, min(BOARD_SIZE - 1, self.cursor + delta))
        self._draw()

    def _fail(self, message: str) -> None:
        if self.complete or self.game_over:
            return
        self.game_over = True
        self.failure_reason = message
        self._log(message)

    def _objective_results(self) -> list[bool]:
        objectives = self.stage.get("objectives", [])
        results = []
        max_tile = max(max(row) for row in self.board)
        for objective in objectives:
            target = objective.get("value", NO_TARGET)
            kind = objective.get("type")
            results.append({
                DEFAULT_OBJECTIVE_TYPE: max_tile >= target,
                "COMBO": self.combo >= target,
                "SCORE": self.score >= target,
                "MERGE_COUNT": self.merge_count >= target,
            }.get(kind, False))
        return results

    def _check_objective(self) -> None:
        results = self._objective_results()
        if results and ((self.stage.get("objectiveMode") == ALL_OBJECTIVE_MODE and all(results))
                        or (self.stage.get("objectiveMode", DEFAULT_OBJECTIVE_MODE)
                            != ALL_OBJECTIVE_MODE and any(results))):
            if not self.complete:
                self.complete = True
                self._log("*** OBJECTIVE COMPLETE ***")

    def _objective_summary(self) -> str:
        objectives = self.stage.get("objectives", [])
        results = self._objective_results()
        if not objectives:
            return "-"
        labels = []
        for objective, achieved in zip(objectives, results):
            kind = objective.get("type", DEFAULT_OBJECTIVE_TYPE)
            target = objective.get("value", NO_TARGET)
            labels.append(f"{kind} {target} {'OK' if achieved else '...'}")
        return ", ".join(labels)

    def _description_summary(self) -> str:
        description = self.stage.get("description", {})
        if isinstance(description, str):
            return description or "-"
        if not isinstance(description, dict):
            return "-"
        return description.get("en") or description.get("ja") or "-"

    def _draw(self) -> None:
        self.canvas.delete("all")
        for y in range(BOARD_SIZE):
            for x in range(BOARD_SIZE):
                left = x * PREVIEW_CELL_SIZE
                top = PREVIEW_TOP + y * PREVIEW_CELL_SIZE
                self.canvas.create_rectangle(left, top, left + PREVIEW_CELL_SIZE,
                                             top + PREVIEW_CELL_SIZE, outline=CELL_OUTLINE,
                                             fill=CELL_FILL)
                if (x, y) == CENTER:
                    self.canvas.create_oval(left + PREVIEW_CENTER_MARK_INSET,
                                            top + PREVIEW_CENTER_MARK_INSET,
                                            left + PREVIEW_CENTER_MARK_INSET
                                            + PREVIEW_CENTER_MARK_SIZE,
                                            top + PREVIEW_CENTER_MARK_INSET
                                            + PREVIEW_CENTER_MARK_SIZE,
                                            outline=CENTER_OUTLINE)
                value = self.board[y][x]
                if value:
                    self.canvas.create_rectangle(left + BLOCK_INSET, top + BLOCK_INSET,
                                                 left + PREVIEW_CELL_SIZE - BLOCK_INSET,
                                                 top + PREVIEW_CELL_SIZE - BLOCK_INSET,
                                                 fill=BLOCK_FILL, outline=BLOCK_FILL)
                    self.canvas.create_text(left + PREVIEW_CELL_SIZE / 2,
                                            top + PREVIEW_CELL_SIZE / 2,
                                            text=str(value), fill=BLOCK_TEXT_FILL,
                                            font=BLOCK_FONT)
        # 現在操作中のブロックを、選択列の盤面上部に表示する。
        current_left = self.cursor * PREVIEW_CELL_SIZE
        self.canvas.create_rectangle(current_left + BLOCK_INSET, PREVIEW_BLOCK_TOP,
                                     current_left + PREVIEW_CELL_SIZE - BLOCK_INSET,
                                     PREVIEW_TOP - PREVIEW_BLOCK_BOTTOM_GAP,
                                     fill=BLOCK_FILL, outline=BLOCK_FILL)
        self.canvas.create_text(current_left + PREVIEW_CELL_SIZE / 2,
                                (PREVIEW_BLOCK_TOP + PREVIEW_TOP
                                 - PREVIEW_BLOCK_BOTTOM_GAP) / 2,
                                text=str(self.current_value or "-"), fill=BLOCK_TEXT_FILL,
                                font=BLOCK_FONT)
        cursor_y = PREVIEW_TOP + PREVIEW_CELL_SIZE * BOARD_SIZE + PREVIEW_CURSOR_TOP_GAP
        self.canvas.create_rectangle(self.cursor * PREVIEW_CELL_SIZE
                                     + PREVIEW_CURSOR_LEFT_INSET, cursor_y,
                                     (self.cursor + 1) * PREVIEW_CELL_SIZE
                                     - PREVIEW_CURSOR_RIGHT_INSET,
                                     cursor_y + PREVIEW_CURSOR_HEIGHT,
                                     fill="#333", outline="#333")
        self._ensure_queue(PREVIEW_NEXT_DISPLAY_COUNT)
        preview = ", ".join(map(str, self.next_queue[:PREVIEW_NEXT_DISPLAY_COUNT]))
        state = "CLEAR" if self.complete else "FAILED" if self.game_over else "PLAYING"
        result = "OBJECTIVE COMPLETE" if self.complete else self.failure_reason or "-"
        self.info_var.set(f"State: {state}\nTurn: {self.turn}\nCurrent: {self.current_value}\n"
                          f"NEXT: {preview}\nHOLD: {self.hold_value or '-'}\n"
                          f"Move limit: {self.turn_limit or '-'}\n"
                          f"Description: {self._description_summary()}\n"
                          f"Objective: {self._objective_summary()}\n"
                          f"Result: {result}\n"
                          f"Score: {self.score}\nCombo: {self.combo}\nMerges: {self.merge_count}")
        self.cursor_var.set(f"Column: {self.cursor + 1}")
        self.canvas.update_idletasks()

if __name__ == "__main__":
    StageEditor(tuple(sys.argv[1:])).mainloop()

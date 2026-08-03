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
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk


BOARD_SIZE = 5
MAX_NEXT = 10
CENTER = (2, 2)  # zero-based
CELL_SIZE = 64
VALUES = [2 ** n for n in range(1, 12)]
EDITOR_DIR = Path(__file__).resolve().parent
SETTINGS_PATH = EDITOR_DIR / ".practice_editor_settings.json"


def new_stage() -> dict:
    return {
        "id": "001",
        "label": "NEW STAGE",
        "initialBoard": [],
        "nextValues": [2] * MAX_NEXT,
        "nextPolicy": "LOOP",
        "nextRandom": {"values": [2, 4], "weights": [90, 10]},
        "objectiveMode": "ANY",
        "objectives": [{"type": "TILE_VALUE", "value": 64}],
    }


class StageEditor(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("2048 Practice Stage Editor")
        self.resizable(False, False)
        self.current_path: Path | None = None
        self.dirty = False
        self.history: list[dict] = []
        self.redo_history: list[dict] = []
        self.stage = new_stage()
        self.selected_value = tk.IntVar(value=2)
        self.label_var = tk.StringVar()
        self.policy_var = tk.StringVar(value="LOOP")
        self.random_values_var = tk.StringVar(value="2,4")
        self.random_weights_var = tk.StringVar(value="90,10")
        self.objective_mode_var = tk.StringVar(value="ANY")
        self.objective_type_var = tk.StringVar(value="TILE_VALUE")
        self.objective_value_var = tk.StringVar(value="64")
        self.status_var = tk.StringVar(value="Ready")
        self.board: list[list[int]] = []
        self.next_vars: list[tk.StringVar] = []
        self._build_ui()
        self._bind_shortcuts()
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

        root = ttk.Frame(self, padding=8)
        root.grid()
        board_frame = ttk.LabelFrame(root, text="Initial Board", padding=6)
        board_frame.grid(row=0, column=0, rowspan=3, padx=(0, 10), sticky="n")
        self.canvas = tk.Canvas(board_frame, width=CELL_SIZE * BOARD_SIZE,
                                height=CELL_SIZE * BOARD_SIZE, bg="white",
                                highlightthickness=0)
        self.canvas.grid()
        self.canvas.bind("<Button-1>", self._place_block)
        self.canvas.bind("<Button-3>", self._remove_block)
        ttk.Label(board_frame, text="Left: place / Right: remove").grid(pady=(6, 0))
        value_frame = ttk.Frame(board_frame)
        value_frame.grid(pady=4)
        ttk.Label(value_frame, text="Block:").pack(side="left")
        ttk.Combobox(value_frame, textvariable=self.selected_value,
                     values=VALUES, width=8, state="readonly").pack(side="left", padx=4)

        form = ttk.Frame(root)
        form.grid(row=0, column=1, sticky="nw")
        ttk.Label(form, text="Label").grid(row=0, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.label_var, width=30).grid(
            row=0, column=1, columnspan=3, sticky="ew", pady=2)
        ttk.Label(form, text="NEXT mode").grid(row=1, column=0, sticky="w")
        policy = ttk.Combobox(form, textvariable=self.policy_var,
                              values=["LOOP", "RANDOM"], state="readonly", width=10)
        policy.grid(row=1, column=1, sticky="w", pady=2)
        policy.bind("<<ComboboxSelected>>", lambda _: self._mark_changed())
        ttk.Label(form, text="Fixed NEXT (1-10)").grid(row=2, column=0, sticky="nw")
        next_frame = ttk.Frame(form)
        next_frame.grid(row=2, column=1, columnspan=3, sticky="w")
        for i in range(MAX_NEXT):
            var = tk.StringVar(value="2")
            self.next_vars.append(var)
            ttk.Label(next_frame, text=f"{i + 1:02}").grid(row=i // 5 * 2, column=i % 5)
            box = ttk.Combobox(next_frame, textvariable=var, values=VALUES,
                               width=5, state="readonly")
            box.grid(row=i // 5 * 2 + 1, column=i % 5, padx=2, pady=(0, 3))
            box.bind("<<ComboboxSelected>>", lambda _: self._mark_changed())
        ttk.Label(form, text="Random values").grid(row=4, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.random_values_var, width=20).grid(
            row=4, column=1, columnspan=3, sticky="w")
        ttk.Label(form, text="Random weights").grid(row=5, column=0, sticky="w")
        ttk.Entry(form, textvariable=self.random_weights_var, width=20).grid(
            row=5, column=1, columnspan=3, sticky="w")

        objective = ttk.LabelFrame(form, text="Clear Objective", padding=5)
        objective.grid(row=6, column=0, columnspan=4, sticky="ew", pady=(8, 0))
        ttk.Label(objective, text="Mode").grid(row=0, column=0, sticky="w")
        ttk.Combobox(objective, textvariable=self.objective_mode_var,
                     values=["ANY", "ALL"], state="readonly", width=8).grid(
                         row=0, column=1, sticky="w")
        ttk.Label(objective, text="Type").grid(row=1, column=0, sticky="w")
        ttk.Combobox(objective, textvariable=self.objective_type_var,
                     values=["TILE_VALUE", "COMBO", "SCORE", "MERGE_COUNT"],
                     state="readonly", width=16).grid(row=1, column=1, sticky="w")
        ttk.Label(objective, text="Value").grid(row=2, column=0, sticky="w")
        ttk.Entry(objective, textvariable=self.objective_value_var,
                  width=10).grid(row=2, column=1, sticky="w")

        buttons = ttk.Frame(root)
        buttons.grid(row=1, column=1, sticky="ew", pady=8)
        ttk.Button(buttons, text="Preview / Check", command=self.preview).pack(
            side="left", padx=(0, 5))
        ttk.Button(buttons, text="Undo", command=self.undo).pack(side="left", padx=2)
        ttk.Button(buttons, text="Redo", command=self.redo).pack(side="left", padx=2)
        ttk.Button(buttons, text="Save", command=self.save_stage).pack(side="right")
        ttk.Button(buttons, text="Open", command=self.open_stage).pack(side="right", padx=2)
        ttk.Label(root, textvariable=self.status_var, anchor="w").grid(
            row=2, column=0, columnspan=2, sticky="ew")
        self._reset_model(new_stage())

    def _bind_shortcuts(self) -> None:
        for key in ("<Command-s>", "<Control-s>"):
            self.bind_all(key, lambda _: self.save_stage())
        for key in ("<Command-z>", "<Control-z>"):
            self.bind_all(key, lambda _: self.undo())
        for key in ("<Command-Shift-z>", "<Control-Shift-z>"):
            self.bind_all(key, lambda _: self.redo())

    # ---------- Model ----------
    def _reset_model(self, stage: dict) -> None:
        self.stage = copy.deepcopy(stage)
        self.board = [[0 for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
        for block in self.stage.get("initialBoard", []):
            if 1 <= block.get("x", 0) <= BOARD_SIZE and 1 <= block.get("y", 0) <= BOARD_SIZE:
                self.board[block["y"] - 1][block["x"] - 1] = block.get("value", 0)
        self.label_var.set(self.stage.get("label", ""))
        self.policy_var.set(self.stage.get("nextPolicy", "LOOP"))
        values = self.stage.get("nextValues", [])
        for i, var in enumerate(self.next_vars):
            var.set(str(values[i]) if i < len(values) else "2")
        random_data = self.stage.get("nextRandom", {})
        self.random_values_var.set(",".join(map(str, random_data.get("values", [2, 4]))))
        self.random_weights_var.set(",".join(map(str, random_data.get("weights", [90, 10]))))
        self.objective_mode_var.set(self.stage.get("objectiveMode", "ANY"))
        objective = (self.stage.get("objectives") or [{"type": "TILE_VALUE", "value": 64}])[0]
        self.objective_type_var.set(objective.get("type", "TILE_VALUE"))
        self.objective_value_var.set(str(objective.get("value", 64)))
        self._draw_board()

    def _snapshot(self) -> dict:
        return {
            "board": copy.deepcopy(self.board),
            "label": self.label_var.get(),
            "policy": self.policy_var.get(),
            "next": [v.get() for v in self.next_vars],
            "random_values": self.random_values_var.get(),
            "random_weights": self.random_weights_var.get(),
            "objective_mode": self.objective_mode_var.get(),
            "objective_type": self.objective_type_var.get(),
            "objective_value": self.objective_value_var.get(),
        }

    def _restore_snapshot(self, snapshot: dict) -> None:
        self.board = copy.deepcopy(snapshot["board"])
        self.label_var.set(snapshot["label"])
        self.policy_var.set(snapshot["policy"])
        for var, value in zip(self.next_vars, snapshot["next"]):
            var.set(value)
        self.random_values_var.set(snapshot["random_values"])
        self.random_weights_var.set(snapshot["random_weights"])
        self.objective_mode_var.set(snapshot["objective_mode"])
        self.objective_type_var.set(snapshot["objective_type"])
        self.objective_value_var.set(snapshot["objective_value"])
        self._draw_board()

    def _mark_changed(self) -> None:
        self.history.append(self._snapshot())
        self.redo_history.clear()
        self.dirty = True

    # ---------- Board ----------
    def _draw_board(self) -> None:
        self.canvas.delete("all")
        for y in range(BOARD_SIZE):
            for x in range(BOARD_SIZE):
                left, top = x * CELL_SIZE, y * CELL_SIZE
                self.canvas.create_rectangle(left, top, left + CELL_SIZE, top + CELL_SIZE,
                                             outline="#777", fill="#eee")
                if (x, y) == CENTER:
                    self.canvas.create_oval(left + 20, top + 20, left + 44, top + 44,
                                            outline="#999")
                value = self.board[y][x]
                if value:
                    self.canvas.create_rectangle(left + 3, top + 3,
                                                 left + CELL_SIZE - 3, top + CELL_SIZE - 3,
                                                 fill="#222", outline="#222")
                    self.canvas.create_text(left + CELL_SIZE / 2, top + CELL_SIZE / 2,
                                            text=str(value), fill="white",
                                            font=("Helvetica", 16, "bold"))

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
        if cell is None or self.board[cell[1]][cell[0]] == 0:
            return
        self._mark_changed()
        self.board[cell[1]][cell[0]] = 0
        self._draw_board()

    # ---------- File operations ----------
    def _collect_stage(self) -> dict:
        values = [int(var.get()) for var in self.next_vars]
        random_values = [int(x.strip()) for x in self.random_values_var.get().split(",") if x.strip()]
        random_weights = [int(x.strip()) for x in self.random_weights_var.get().split(",") if x.strip()]
        objective_value = int(self.objective_value_var.get())
        blocks = [{"x": x + 1, "y": y + 1, "value": self.board[y][x]}
                  for y in range(BOARD_SIZE) for x in range(BOARD_SIZE)
                  if self.board[y][x]]
        return {
            "id": self.stage.get("id", "001"),
            "label": self.label_var.get().strip(),
            "initialBoard": blocks,
            "nextValues": values,
            "nextPolicy": self.policy_var.get(),
            "nextRandom": {"values": random_values, "weights": random_weights},
            "objectiveMode": self.objective_mode_var.get(),
            "objectives": [{"type": self.objective_type_var.get(), "value": objective_value}],
        }

    def _validate(self, stage: dict) -> list[str]:
        errors = []
        if not stage["label"]:
            errors.append("Label is required")
        if len(stage["nextValues"]) != MAX_NEXT:
            errors.append("NEXT must contain 10 values")
        for block in stage["initialBoard"]:
            if (block["x"], block["y"]) == (3, 3):
                errors.append("The center cell cannot contain a block")
            if block["value"] not in VALUES:
                errors.append(f"Invalid block value: {block['value']}")
        random_data = stage["nextRandom"]
        if stage["nextPolicy"] == "RANDOM":
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
        self.current_path.write_text(json.dumps(stage, ensure_ascii=False, indent=2) + "\n",
                                     encoding="utf-8")
        self.stage = stage
        self.dirty = False
        self._save_settings()
        self._update_title()
        self.status_var.set(f"Saved: {self.current_path.name}")

    def save_as(self) -> None:
        path = filedialog.asksaveasfilename(initialdir=str(EDITOR_DIR),
                                            initialfile="001.json",
                                            defaultextension=".json",
                                            filetypes=[("JSON", "*.json")])
        if path:
            self.current_path = Path(path)
            self.save_stage()

    def open_stage(self) -> None:
        if not self._confirm_discard():
            return
        path = filedialog.askopenfilename(initialdir=str(EDITOR_DIR),
                                          filetypes=[("JSON", "*.json")])
        if path:
            self._load_path(Path(path))

    def _load_path(self, path: Path) -> None:
        try:
            stage = json.loads(path.read_text(encoding="utf-8"))
            stage.setdefault("label", path.stem)
            stage.setdefault("initialBoard", [])
            stage.setdefault("nextValues", [2] * MAX_NEXT)
            stage.setdefault("nextPolicy", "LOOP")
            stage.setdefault("nextRandom", {"values": [2, 4], "weights": [90, 10]})
            stage.setdefault("objectiveMode", "ANY")
            stage.setdefault("objectives", [{"type": "TILE_VALUE", "value": 64}])
            errors = self._validate(stage)
            if errors:
                raise ValueError("\n".join(errors))
        except (OSError, ValueError, json.JSONDecodeError) as exc:
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
            SETTINGS_PATH.write_text(json.dumps({"lastOpenedFile": str(self.current_path)},
                                                indent=2) + "\n", encoding="utf-8")

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
        self.title(("*" if self.dirty else "") + name + " - 2048 Practice Stage Editor")

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

    PREVIEW_CELL = 72
    PREVIEW_TOP = 42

    def __init__(self, parent: StageEditor, stage: dict) -> None:
        super().__init__(parent)
        self.parent_editor = parent
        self.stage = copy.deepcopy(stage)
        self.title(f"Preview - {stage['label']}")
        self.resizable(False, False)
        self.board = [[0 for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
        for block in stage.get("initialBoard", []):
            self.board[block["y"] - 1][block["x"] - 1] = block["value"]
        self.cursor = 2
        self.next_index = 0
        self.current_value = 0
        self.next_queue: list[int] = []
        self.hold_value = 0
        self.hold_available = True
        self.score = 0
        self.combo = 0
        self.merge_count = 0
        self.turn = 0
        self.random = random.Random(stage.get("randomSeed", 1))
        self.complete = False
        self.game_over = False
        self.cursor_var = tk.StringVar()
        self.info_var = tk.StringVar()
        self._build_ui()
        self.reset()
        self.focus_force()
        self.bind("<Left>", lambda _: self.move_cursor(-1))
        self.bind("<Right>", lambda _: self.move_cursor(1))
        self.bind("<Down>", lambda _: self.drop())
        self.bind("<space>", lambda _: self.drop())
        self.bind("<KeyPress-h>", lambda _: self.hold())
        self.bind("<KeyPress-H>", lambda _: self.hold())
        self.bind("<KeyPress-r>", lambda _: self.reset())
        self.bind("<KeyPress-R>", lambda _: self.reset())

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=8)
        root.grid()
        self.canvas = tk.Canvas(root, width=self.PREVIEW_CELL * BOARD_SIZE,
                                height=self.PREVIEW_TOP + self.PREVIEW_CELL * BOARD_SIZE + 12,
                                bg="white", highlightthickness=0)
        self.canvas.grid(row=0, column=0, rowspan=2, padx=(0, 8))
        side = ttk.Frame(root)
        side.grid(row=0, column=1, sticky="n")
        ttk.Label(side, textvariable=self.info_var, justify="left").grid(sticky="w")
        ttk.Label(side, text="Controls").grid(sticky="w", pady=(12, 0))
        ttk.Label(side, text="←/→ Move   ↓/Space Drop\nH Hold   R Reset").grid(sticky="w")
        ttk.Label(side, textvariable=self.cursor_var).grid(sticky="w", pady=(8, 0))
        ttk.Label(root, text="Event log").grid(row=2, column=0, columnspan=2,
                                               sticky="w", pady=(8, 0))
        self.log = tk.Text(root, width=64, height=13, state="disabled",
                           background="#f5f5f5")
        self.log.grid(row=3, column=0, columnspan=2)
        ttk.Button(root, text="Reset", command=self.reset).grid(row=4, column=0,
                                                                  columnspan=2, pady=6)

    def _log(self, message: str) -> None:
        self.log.configure(state="normal")
        self.log.insert("end", message + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def reset(self) -> None:
        self.board = [[0 for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
        for block in self.stage.get("initialBoard", []):
            self.board[block["y"] - 1][block["x"] - 1] = block["value"]
        self.cursor = 2
        self.next_index = 0
        self.next_queue = []
        self.hold_value = 0
        self.hold_available = True
        self.score = 0
        self.combo = 0
        self.merge_count = 0
        self.turn = 0
        self.complete = False
        self.game_over = False
        self.random = random.Random(self.stage.get("randomSeed", 1))
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")
        self._ensure_queue(4)
        self.current_value = self.next_queue.pop(0)
        self._ensure_queue(4)
        self._log(f"RESET  board loaded, current={self.current_value}")
        self._draw()

    def _random_value(self) -> int:
        data = self.stage.get("nextRandom", {})
        values = data.get("values", [2, 4])
        weights = data.get("weights", [90, 10])
        if not values or len(values) != len(weights):
            return 2
        return self.random.choices(values, weights=weights, k=1)[0]

    def _next_value(self) -> int:
        if self.stage.get("nextPolicy", "LOOP") == "RANDOM":
            return self._random_value()
        values = self.stage.get("nextValues", [2]) or [2]
        value = values[self.next_index % len(values)]
        self.next_index += 1
        return value

    def _ensure_queue(self, count: int) -> None:
        while len(self.next_queue) < count:
            self.next_queue.append(self._next_value())

    def _is_playable(self, x: int, y: int) -> bool:
        return 0 <= x < BOARD_SIZE and 0 <= y < BOARD_SIZE and (x, y) != CENTER

    def _occupied(self, x: int, y: int) -> bool:
        return self._is_playable(x, y) and self.board[y][x] != 0

    def _find_drop_cell(self, column: int) -> tuple[int, int] | None:
        for y in range(BOARD_SIZE):
            if (column, y) == CENTER or self.board[y][column] != 0:
                return None
            supported = (self._occupied(column, y + 1)
                         or (column == 2 and y == 1)
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
        if x > 2:
            return 10
        if x < 2:
            return -10
        return 0

    def _merge_evaluation(self, source: tuple[int, int], target: tuple[int, int]) -> int:
        sx, _ = source
        tx, _ = target
        direction = -5 if tx < sx else 5 if tx > sx else 10 * self._position_evaluation(tx)
        return (-10 * self._position_evaluation(sx)
                + 10 * self._position_evaluation(tx) + direction)

    def _rotate(self, clockwise: bool) -> None:
        rotated = [[0 for _ in range(BOARD_SIZE)] for _ in range(BOARD_SIZE)]
        for y in range(BOARD_SIZE):
            for x in range(BOARD_SIZE):
                if not self._is_playable(x, y) or not self.board[y][x]:
                    continue
                nx, ny = (4 - y, x) if clockwise else (y, 4 - x)
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
            self.board[source[1]][source[0]] = 0
            self.board[target[1]][target[0]] = value
            self.combo += 1
            self.merge_count += 1
            bonus = int(2 * self.combo ** 1.5 - 2 * (self.combo - 1) ** 1.5)
            self.score += value * 100 + bonus * 100
            evaluation += self._merge_evaluation(source, target)
            active = target
            self._log(f"MERGE {value // 2}+{value // 2}={value} at ({target[0] + 1},{target[1] + 1})")
        if evaluation:
            clockwise = evaluation > 0
            self._rotate(clockwise)
            x, y = active
            active = (4 - y, x) if clockwise else (y, 4 - x)
            self._log("ROTATE " + ("CLOCKWISE" if clockwise else "COUNTER-CLOCKWISE"))
            self._resolve_after_rotation(active)

    def _resolve_after_rotation(self, active: tuple[int, int]) -> None:
        while True:
            merge = self._find_merge(*active)
            if merge is None:
                return
            source, target = merge
            value = self.board[source[1]][source[0]] * 2
            self.board[source[1]][source[0]] = 0
            self.board[target[1]][target[0]] = value
            self.combo += 1
            self.merge_count += 1
            bonus = int(2 * self.combo ** 1.5 - 2 * (self.combo - 1) ** 1.5)
            self.score += value * 100 + bonus * 100
            active = target
            self._log(f"MERGE AFTER ROTATION -> {value}")

    def drop(self) -> None:
        if self.complete or self.game_over:
            return
        cell = self._find_drop_cell(self.cursor)
        if cell is None:
            self._log(f"DROP column={self.cursor + 1} -> NO SPACE")
            return
        x, y = cell
        self.combo = 0
        self.board[y][x] = self.current_value
        self.turn += 1
        self._log(f"DROP column={x + 1} cell=({x + 1},{y + 1}) value={self.current_value}")
        evaluation = self._position_evaluation(x) * 20
        self._resolve((x, y), evaluation)
        self.hold_available = True
        self._ensure_queue(4)
        self.current_value = self.next_queue.pop(0)
        self._ensure_queue(4)
        self._check_objective()
        if not self.complete and not any(self._find_drop_cell(column)
                                         for column in range(BOARD_SIZE)):
            self.game_over = True
            self._log("*** GAME OVER: NO DROP AVAILABLE ***")
        self._draw()

    def hold(self) -> None:
        if self.complete or self.game_over:
            return
        if not self.hold_available:
            self._log("HOLD -> UNAVAILABLE")
            return
        if self.hold_value == 0:
            self.hold_value = self.current_value
            self._ensure_queue(1)
            self.current_value = self.next_queue.pop(0)
            self._ensure_queue(4)
            self._log(f"HOLD {self.hold_value}; next current={self.current_value}")
        else:
            self.current_value, self.hold_value = self.hold_value, self.current_value
            self._log(f"HOLD SWAP current={self.current_value} hold={self.hold_value}")
        self.hold_available = False
        self._draw()

    def move_cursor(self, delta: int) -> None:
        self.cursor = max(0, min(BOARD_SIZE - 1, self.cursor + delta))
        self._draw()

    def _check_objective(self) -> None:
        objectives = self.stage.get("objectives", [])
        results = []
        max_tile = max(max(row) for row in self.board)
        for objective in objectives:
            target = objective.get("value", 0)
            kind = objective.get("type")
            results.append({
                "TILE_VALUE": max_tile >= target,
                "COMBO": self.combo >= target,
                "SCORE": self.score >= target,
                "MERGE_COUNT": self.merge_count >= target,
            }.get(kind, False))
        if results and ((self.stage.get("objectiveMode") == "ALL" and all(results))
                        or (self.stage.get("objectiveMode", "ANY") != "ALL" and any(results))):
            if not self.complete:
                self.complete = True
                self._log("*** OBJECTIVE COMPLETE ***")

    def _draw(self) -> None:
        self.canvas.delete("all")
        for y in range(BOARD_SIZE):
            for x in range(BOARD_SIZE):
                left = x * self.PREVIEW_CELL
                top = self.PREVIEW_TOP + y * self.PREVIEW_CELL
                self.canvas.create_rectangle(left, top, left + self.PREVIEW_CELL,
                                             top + self.PREVIEW_CELL, outline="#777",
                                             fill="#eee")
                if (x, y) == CENTER:
                    self.canvas.create_oval(left + 24, top + 24, left + 48, top + 48,
                                            outline="#999")
                value = self.board[y][x]
                if value:
                    self.canvas.create_rectangle(left + 3, top + 3,
                                                 left + self.PREVIEW_CELL - 3,
                                                 top + self.PREVIEW_CELL - 3,
                                                 fill="#222", outline="#222")
                    self.canvas.create_text(left + self.PREVIEW_CELL / 2,
                                            top + self.PREVIEW_CELL / 2,
                                            text=str(value), fill="white",
                                            font=("Helvetica", 16, "bold"))
        # 現在操作中のブロックを、選択列の盤面上部に表示する。
        current_left = self.cursor * self.PREVIEW_CELL
        self.canvas.create_rectangle(current_left + 3, 4,
                                     current_left + self.PREVIEW_CELL - 3,
                                     self.PREVIEW_TOP - 7,
                                     fill="#222", outline="#222")
        self.canvas.create_text(current_left + self.PREVIEW_CELL / 2,
                                (4 + self.PREVIEW_TOP - 7) / 2,
                                text=str(self.current_value), fill="white",
                                font=("Helvetica", 16, "bold"))
        cursor_y = self.PREVIEW_TOP + self.PREVIEW_CELL * BOARD_SIZE + 3
        self.canvas.create_rectangle(self.cursor * self.PREVIEW_CELL + 4, cursor_y,
                                     (self.cursor + 1) * self.PREVIEW_CELL - 4, cursor_y + 5,
                                     fill="#333", outline="#333")
        self._ensure_queue(3)
        preview = ", ".join(map(str, self.next_queue[:3]))
        state = "CLEAR" if self.complete else "GAME OVER" if self.game_over else "PLAYING"
        self.info_var.set(f"State: {state}\nTurn: {self.turn}\nCurrent: {self.current_value}\n"
                          f"NEXT: {preview}\nHOLD: {self.hold_value or '-'}\n"
                          f"Score: {self.score}\nCombo: {self.combo}\nMerges: {self.merge_count}")
        self.cursor_var.set(f"Column: {self.cursor + 1}")

if __name__ == "__main__":
    StageEditor().mainloop()

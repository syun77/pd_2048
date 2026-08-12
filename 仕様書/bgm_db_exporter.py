#!/usr/bin/env python3
"""Export 0.2-second BGM peak levels as compact JSON files.

The project's BGM files are Playdate-friendly IMA ADPCM WAV files. This tool
decodes them to 16-bit PCM, measures the peak dBFS for each interval, maps the
result to 0-100, and writes one JSON file per WAV.

Run from the repository root:

    python3 仕様書/bgm_db_exporter.py
"""

from __future__ import annotations

import argparse
import json
import math
import struct
from dataclasses import dataclass
from pathlib import Path


WAVE_FORMAT_PCM = 0x0001
WAVE_FORMAT_IMA_ADPCM = 0x0011
MAX_16BIT_SAMPLE = 32767
DEFAULT_INTERVAL_SECONDS = 0.2
DEFAULT_MIN_DB = -60.0

IMA_INDEX_TABLE = (
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8,
)

IMA_STEP_TABLE = (
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
    19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
    5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
)


@dataclass
class WavData:
    path: Path
    audio_format: int
    channels: int
    sample_rate: int
    block_align: int
    bits_per_sample: int
    samples_per_block: int | None
    data: bytes


def read_chunks(path: Path) -> dict[bytes, bytes]:
    data = path.read_bytes()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError(f"{path} is not a RIFF/WAVE file")

    chunks: dict[bytes, bytes] = {}
    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset:offset + 4]
        chunk_size = struct.unpack_from("<I", data, offset + 4)[0]
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_size
        chunks[chunk_id] = data[chunk_start:chunk_end]
        offset = chunk_end + (chunk_size % 2)
    return chunks


def read_wav(path: Path) -> WavData:
    chunks = read_chunks(path)
    fmt = chunks.get(b"fmt ")
    sound_data = chunks.get(b"data")
    if fmt is None or sound_data is None:
        raise ValueError(f"{path} is missing fmt or data chunk")
    if len(fmt) < 16:
        raise ValueError(f"{path} has an invalid fmt chunk")

    audio_format, channels, sample_rate, _, block_align, bits_per_sample = (
        struct.unpack_from("<HHIIHH", fmt, 0)
    )
    samples_per_block = None
    if audio_format == WAVE_FORMAT_IMA_ADPCM and len(fmt) >= 20:
        extra_size = struct.unpack_from("<H", fmt, 16)[0]
        if extra_size >= 2 and len(fmt) >= 20:
            samples_per_block = struct.unpack_from("<H", fmt, 18)[0]

    return WavData(
        path=path,
        audio_format=audio_format,
        channels=channels,
        sample_rate=sample_rate,
        block_align=block_align,
        bits_per_sample=bits_per_sample,
        samples_per_block=samples_per_block,
        data=sound_data,
    )


def clamp(value: int, low: int, high: int) -> int:
    return max(low, min(high, value))


def decode_ima_nibble(nibble: int, predictor: int, step_index: int) -> tuple[int, int]:
    step = IMA_STEP_TABLE[step_index]
    diff = step >> 3
    if nibble & 0x01:
        diff += step >> 2
    if nibble & 0x02:
        diff += step >> 1
    if nibble & 0x04:
        diff += step
    if nibble & 0x08:
        predictor -= diff
    else:
        predictor += diff

    predictor = clamp(predictor, -32768, 32767)
    step_index = clamp(step_index + IMA_INDEX_TABLE[nibble], 0, 88)
    return predictor, step_index


def decode_ima_adpcm_mono(wav: WavData) -> list[int]:
    if wav.channels != 1:
        raise ValueError(f"{wav.path} uses {wav.channels} channels; only mono IMA ADPCM is supported")
    if wav.block_align <= 4:
        raise ValueError(f"{wav.path} has invalid blockAlign={wav.block_align}")

    samples: list[int] = []
    for block_start in range(0, len(wav.data), wav.block_align):
        block = wav.data[block_start:block_start + wav.block_align]
        if len(block) < 4:
            continue

        predictor = struct.unpack_from("<h", block, 0)[0]
        step_index = clamp(block[2], 0, 88)
        samples.append(predictor)

        for byte in block[4:]:
            predictor, step_index = decode_ima_nibble(byte & 0x0F, predictor, step_index)
            samples.append(predictor)
            predictor, step_index = decode_ima_nibble(byte >> 4, predictor, step_index)
            samples.append(predictor)

    return samples


def decode_pcm(wav: WavData) -> list[int]:
    if wav.channels != 1:
        raise ValueError(f"{wav.path} uses {wav.channels} channels; only mono PCM is supported")
    if wav.bits_per_sample == 16:
        sample_count = len(wav.data) // 2
        return list(struct.unpack_from(f"<{sample_count}h", wav.data, 0))
    if wav.bits_per_sample == 8:
        return [(byte - 128) << 8 for byte in wav.data]
    raise ValueError(f"{wav.path} uses unsupported PCM bit depth: {wav.bits_per_sample}")


def decode_wav_samples(path: Path) -> tuple[WavData, list[int]]:
    wav = read_wav(path)
    if wav.audio_format == WAVE_FORMAT_IMA_ADPCM:
        return wav, decode_ima_adpcm_mono(wav)
    if wav.audio_format == WAVE_FORMAT_PCM:
        return wav, decode_pcm(wav)
    raise ValueError(f"{path} uses unsupported WAV format: 0x{wav.audio_format:04x}")


def peak_to_db(peak: int) -> float:
    if peak <= 0:
        return float("-inf")
    return 20.0 * math.log10(min(peak, MAX_16BIT_SAMPLE) / MAX_16BIT_SAMPLE)


def db_to_level(db: float, min_db: float) -> int:
    if not math.isfinite(db) or db <= min_db:
        return 0
    if db >= 0:
        return 100
    return int(round((db - min_db) / (0.0 - min_db) * 100.0))


def build_levels(samples: list[int], sample_rate: int, interval: float, min_db: float) -> list[int]:
    window_size = max(1, int(round(sample_rate * interval)))
    levels: list[int] = []
    for start in range(0, len(samples), window_size):
        window = samples[start:start + window_size]
        peak = max((abs(sample) for sample in window), default=0)
        levels.append(db_to_level(peak_to_db(peak), min_db))
    return levels


def export_file(wav_path: Path, output_dir: Path, interval: float, min_db: float) -> Path:
    wav, samples = decode_wav_samples(wav_path)
    levels = build_levels(samples, wav.sample_rate, interval, min_db)
    duration = len(samples) / wav.sample_rate
    payload = {
        "source": wav_path.name,
        "interval": interval,
        "minDb": min_db,
        "sampleRate": wav.sample_rate,
        "duration": round(duration, 3),
        "levels": levels,
    }

    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{wav_path.stem}.json"
    with output_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=True, separators=(",", ":"))
        file.write("\n")
    return output_path


def default_repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def parse_args() -> argparse.Namespace:
    repo_root = default_repo_root()
    parser = argparse.ArgumentParser(
        description="Export per-BGM peak dB levels to pd_2048/source/assets/bgm_db JSON files."
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=repo_root / "pd_2048" / "source" / "sounds" / "bgm",
        help="Directory containing BGM wav files.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=repo_root / "pd_2048" / "source" / "assets" / "bgm_db",
        help="Directory where JSON files will be written.",
    )
    parser.add_argument(
        "--interval",
        type=float,
        default=DEFAULT_INTERVAL_SECONDS,
        help="Analysis interval in seconds.",
    )
    parser.add_argument(
        "--min-db",
        type=float,
        default=DEFAULT_MIN_DB,
        help="dBFS value mapped to level 0. 0 dBFS maps to level 100.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    wav_paths = sorted(args.input.glob("*.wav"))
    if not wav_paths:
        raise SystemExit(f"No wav files found: {args.input}")

    for wav_path in wav_paths:
        output_path = export_file(wav_path, args.output, args.interval, args.min_db)
        print(f"{wav_path.name} -> {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

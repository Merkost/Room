#!/usr/bin/env python3
"""Encode and verify App Store previews from approved native Room recordings."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import subprocess
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from tempfile import TemporaryDirectory

PREVIEWS = ("01-overview-map", "02-cache-review", "03-memory-monitor")
WIDTH, HEIGHT, FPS = 1920, 1080, 30
VIDEO_EXTENSIONS = (".mov", ".mp4", ".m4v")


@dataclass
class Shot:
    source: Path
    stream_index: int
    first_frame: int
    frames: int
    crop: tuple[int, int, int, int] | None


def probe(source: Path) -> dict:
    report = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(source)],
        text=True,
    )
    return json.loads(report)


def seconds(value: float, label: str) -> float:
    if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise ValueError(f"{label} must be a finite number of seconds")
    return value


def shots_for(recordings: Path, slug: str, edits: dict) -> list[Shot]:
    if slug in edits:
        segments = edits[slug]
        if not isinstance(segments, list) or not segments:
            raise ValueError(f"{slug} needs at least one recording segment")
    else:
        source = next((recordings / (slug + ext) for ext in VIDEO_EXTENSIONS
                       if (recordings / (slug + ext)).is_file()), None)
        if source is None:
            return []
        segments = [{"file": source.name}]
    return [read_shot(recordings, segment) for segment in segments]


def read_shot(recordings: Path, segment: dict) -> Shot:
    source = (recordings / segment["file"]).resolve()
    if not source.is_file() or source.suffix.lower() not in VIDEO_EXTENSIONS:
        raise ValueError(f"Missing native recording: {source}")
    if not source.is_relative_to(recordings):
        raise ValueError(f"Recording is outside {recordings}")
    report = probe(source)
    video = next((stream for stream in report["streams"]
                  if stream["codec_type"] == "video" and not stream.get("disposition", {}).get("attached_pic")), None)
    if video is None:
        raise ValueError(f"No footage in {source.name}")
    if video.get("color_transfer") in {"smpte2084", "arib-std-b67"}:
        raise ValueError(f"{source.name} is HDR. Record Room in SDR for a consistent poster and preview.")
    if any(side.get("rotation", 0) for side in video.get("side_data_list", [])):
        raise ValueError(f"{source.name} is rotated. Supply an upright landscape recording.")
    if video.get("sample_aspect_ratio") not in {None, "N/A", "1:1", "0:1"}:
        raise ValueError(f"{source.name} uses non-square pixels")
    captured_width, captured_height = video["width"], video["height"]
    crop = None
    if "crop" in segment:
        parts = segment["crop"]
        if not isinstance(parts, list) or len(parts) != 4 or any(
            not isinstance(part, int) or part < 0 or part % 2 for part in parts
        ):
            raise ValueError("crop expects four non-negative even integers: width, height, x, y")
        width, height, x, y = parts
        if width + x > captured_width or height + y > captured_height:
            raise ValueError(f"Crop extends beyond {source.name}")
        crop = (width, height, x, y)
    else:
        width, height = captured_width, captured_height
    if width < 1280 or height < 720:
        raise ValueError(f"{source.name} is too small to keep Room's text legible")
    if abs(width / height - WIDTH / HEIGHT) > 0.005:
        raise ValueError(f"{source.name} is {width}×{height}. Choose a 16:9 crop in the edit sheet.")
    available = float(video.get("duration", report["format"]["duration"]))
    start = seconds(segment.get("start", 0), "start")
    end = seconds(segment.get("end", available), "end")
    if start >= end or end > available + 0.01:
        raise ValueError(f"Invalid cut for {source.name}. Available duration: {available:.3f}s")
    first_frame = math.ceil(start * FPS)
    frame_count = math.floor(end * FPS + 0.0001) - first_frame
    if frame_count < 1:
        raise ValueError(f"Cut shorter than one frame in {source.name}")
    return Shot(source, video["index"], first_frame, frame_count, crop)


def render(shots: list[Shot], output: Path, recordings: Path) -> dict:
    frames = sum(shot.frames for shot in shots)
    if not 15 * FPS <= frames <= 30 * FPS:
        raise ValueError(f"{output.stem} is {frames / FPS:.2f}s. Set cuts totaling 15–30 seconds.")
    command = ["ffmpeg", "-hide_banner", "-nostdin", "-v", "error", "-y"]
    filters = []
    for index, shot in enumerate(shots):
        command += ["-i", str(shot.source)]
        crop = "crop=" + ":".join(map(str, shot.crop)) + "," if shot.crop else ""
        filters.append(
            f"[{index}:{shot.stream_index}]setpts=PTS-STARTPTS,fps={FPS},"
            f"trim=start_frame={shot.first_frame}:end_frame={shot.first_frame + shot.frames},"
            f"setpts=PTS-STARTPTS,{crop}scale={WIDTH}:{HEIGHT}:flags=lanczos:out_color_matrix=bt709,"
            f"setsar=1,format=yuv420p[shot{index}]"
        )
    command += ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo"]
    segments = "".join(f"[shot{index}]" for index in range(len(shots)))
    filters.append(f"{segments}concat=n={len(shots)}:v=1:a=0[video]")
    with TemporaryDirectory(prefix=".room-preview-", dir=output.parent) as stage:
        temporary = Path(stage) / output.name
        subprocess.run(command + [
            "-filter_complex_threads", "2", "-filter_complex", ";".join(filters),
            "-map", "[video]", "-map", f"{len(shots)}:a:0", "-map_metadata", "-1",
            "-c:v", "libx264", "-threads", "2", "-preset", "veryfast",
            "-profile:v", "high", "-level:v", "4.0", "-pix_fmt", "yuv420p", "-r", str(FPS),
            "-b:v", "11M", "-minrate", "11M", "-maxrate", "11M", "-bufsize", "22M",
            "-x264-params", "nal-hrd=cbr",
            "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709", "-color_range", "tv",
            "-c:a", "aac", "-profile:a", "aac_low", "-b:a", "256k", "-ar", "48000", "-ac", "2",
            "-t", f"{frames / FPS:.6f}", "-fps_mode", "cfr", "-movflags", "+faststart", str(temporary),
        ], check=True)
        report = verify(temporary)
        report["source_sha256"] = {
            shot.source.relative_to(recordings).as_posix(): sha256(shot.source) for shot in shots
        }
        poster = extract_poster(temporary)
        evidence = temporary.with_suffix(".verify.json")
        evidence.write_text(json.dumps(report, indent=2) + "\n")
        for item in (temporary, poster, evidence):
            item.replace(output.parent / item.name)
    return report


def verify(output: Path) -> dict:
    report = probe(output)
    streams = report["streams"]
    video = next((stream for stream in streams if stream["codec_type"] == "video"), {})
    audio = next((stream for stream in streams if stream["codec_type"] == "audio"), {})
    metadata = report["format"]
    result = {
        "filename": output.name,
        "video": video.get("codec_name"),
        "profile": video.get("profile"),
        "level": video.get("level"),
        "width": video.get("width"),
        "height": video.get("height"),
        "frame_rate": video.get("avg_frame_rate"),
        "field_order": video.get("field_order"),
        "pixel_format": video.get("pix_fmt"),
        "video_bitrate": int(video.get("bit_rate", 0)),
        "duration": float(metadata["duration"]),
        "size_bytes": int(metadata["size"]),
        "audio": audio.get("codec_name"),
        "audio_frame_rate": audio.get("sample_rate"),
        "audio_channels": audio.get("channels"),
    }
    if (result["video"], result["profile"], result["level"], result["width"], result["height"],
        result["field_order"], result["pixel_format"]) != (
        "h264", "High", 40, WIDTH, HEIGHT, "progressive", "yuv420p"
    ):
        raise ValueError(f"{output.name} has unexpected video settings: {result}")
    if Fraction(result["frame_rate"]) != FPS or Fraction(video["r_frame_rate"]) != FPS:
        raise ValueError(f"{output.name} did not encode at constant {FPS} fps")
    if not 15 <= result["duration"] <= 30 or result["size_bytes"] > 500_000_000:
        raise ValueError(f"{output.name} is outside Apple's duration or file-size range")
    if not 10_000_000 <= result["video_bitrate"] <= 12_000_000:
        raise ValueError(f"{output.name} is outside our 10–12 Mbps delivery target")
    if (result["audio"], result["audio_frame_rate"], result["audio_channels"]) != ("aac", "48000", 2):
        raise ValueError(f"{output.name} is missing a 48 kHz stereo AAC track")
    if (video.get("color_space"), video.get("color_transfer"), video.get("color_primaries")) != ("bt709", "bt709", "bt709"):
        raise ValueError(f"{output.name} is missing the BT.709 color tags")
    if abs(float(video["duration"]) - result["duration"]) > 1 / FPS:
        raise ValueError(f"{output.name} has an incomplete video track")
    result["color_space"] = video["color_space"]
    result["sha256"] = sha256(output)
    return result


def sha256(source: Path) -> str:
    digest = hashlib.sha256()
    with source.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def extract_poster(output: Path) -> Path:
    poster = output.with_suffix(".poster.png")
    subprocess.run([
        "ffmpeg", "-hide_banner", "-nostdin", "-v", "error", "-y", "-ss", "5",
        "-i", str(output), "-frames:v", "1", "-update", "1", str(poster),
    ], check=True)
    return poster


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--recordings", type=Path, help="Directory containing native recordings")
    parser.add_argument("--exports", type=Path, help="Directory for rendered previews and verification reports")
    parser.add_argument("--edit-sheet", type=Path, default=Path(__file__).with_name("preview-edits.json"),
                        help="JSON cut list. Defaults to this repository’s three Store previews.")
    parser.add_argument("--only", choices=PREVIEWS)
    parser.add_argument("--verify", type=Path, nargs="+", help="Check existing renders without encoding")
    args = parser.parse_args()
    if args.verify:
        for output in args.verify:
            print(json.dumps(verify(output), indent=2))
        return 0
    if args.recordings is None or args.exports is None:
        parser.error("rendering requires --recordings and --exports")

    recordings = args.recordings.resolve()
    exports = args.exports.resolve()
    exports.mkdir(parents=True, exist_ok=True)
    edits = json.loads(args.edit_sheet.read_text())
    failed = False
    for slug in [args.only] if args.only else PREVIEWS:
        try:
            shots = shots_for(recordings, slug, edits)
            if not shots:
                raise ValueError("Missing native footage")
            output = exports / (slug + ".mov")
            report = render(shots, output, recordings)
            print(f"Verified {output} ({report['duration']:.2f}s)", flush=True)
        except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
            print(f"{slug}: {error}", flush=True)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())

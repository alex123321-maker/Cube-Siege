"""
tools/build_issue_43_gif.py - Assemble dynamic verification sequential captures into an animated GIF.
"""
import re
from pathlib import Path
from typing import Union, List

def extract_frame_index(filename_or_path: Union[str, Path]) -> int:
    """Extract numeric index from frame filename (e.g. 'dyn_seq_105.png' -> 105)."""
    name = Path(filename_or_path).stem
    m = re.search(r"(\d+)", name)
    return int(m.group(1)) if m else -1

def sort_and_select_frames(files: List[Union[str, Path]], step: int = 2) -> List[Union[str, Path]]:
    """Numerically sort frame paths and select every `step`-th frame,
    guaranteeing strictly ascending order and preserving the exact final frame.
    """
    sorted_files = sorted(files, key=extract_frame_index)
    if not sorted_files:
        return []
    selected = sorted_files[::step]
    if sorted_files[-1] not in selected:
        selected.append(sorted_files[-1])
    return selected

def main():
    try:
        from PIL import Image
    except ImportError:
        print("[ERROR] Pillow is required to build animated GIFs. Install via 'pip install Pillow'.")
        return

    root = Path(__file__).resolve().parent.parent
    vdir = root / "docs" / "verification" / "issue43"
    
    # Collect all sequential recorded transition frames
    raw_files = list(vdir.glob("dyn_seq_*.png"))
    
    if raw_files:
        print(f"[GIF] Found {len(raw_files)} sequential transition frames.")
        # Numerically sort and step through frames to maintain strictly ascending chronological order
        selected_files = sort_and_select_frames(raw_files, step=2)
        print(f"[GIF] Selected {len(selected_files)} frames for final animation (first: {selected_files[0].name}, last: {selected_files[-1].name}).")
        
        frames = []
        durations = []
        for i, fpath in enumerate(selected_files):
            img = Image.open(fpath)
            # Resize to 512x288 for crisp 16:9 presentation and compact GIF size (< 5 MB)
            img_resized = img.resize((512, 288), Image.Resampling.BILINEAR)
            img_p = img_resized.convert("P", palette=Image.Palette.ADAPTIVE, colors=96)
            frames.append(img_p)
            
            # Normal frame duration ~120ms; pause slightly on key milestones
            if i == 0 or i == len(selected_files) - 1:
                durations.append(600)
            else:
                durations.append(120)
    else:
        frame_names = [
            "dyn_01_step_approach.png",
            "dyn_02_step_climb.png",
            "dyn_03_step_success_on_top.png",
            "dyn_04_cliff_approach.png",
            "dyn_05_cliff_blocked.png",
            "dyn_06_chunk_unloaded.png",
            "dyn_07_chunk_reloaded.png",
        ]
        frames = []
        durations = [800, 800, 1000, 800, 1000, 1200, 1500]
        for fname in frame_names:
            fpath = vdir / fname
            if not fpath.is_file():
                continue
            img = Image.open(fpath)
            img_resized = img.resize((800, 450), Image.Resampling.LANCZOS)
            img_p = img_resized.convert("P", palette=Image.Palette.ADAPTIVE, colors=256)
            frames.append(img_p)
            
    if not frames:
        print("No frames found to build GIF!")
        return
        
    gif_path = vdir / "terrain_dynamic_walk_streaming.gif"
    if len(durations) != len(frames):
        durations = [100] * len(frames)
        
    frames[0].save(
        gif_path,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
    )
    print(f"[GIF] Generated {gif_path} ({gif_path.stat().st_size / 1024:.1f} KB, {len(frames)} frames)")

if __name__ == "__main__":
    main()

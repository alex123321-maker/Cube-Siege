"""
tools/build_issue_43_gif.py - Assemble dynamic verification captures into an animated GIF.
"""
from pathlib import Path
from PIL import Image

def main():
    root = Path(__file__).resolve().parent.parent
    vdir = root / "docs" / "verification" / "issue43"
    
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
    for fname in frame_names:
        fpath = vdir / fname
        if not fpath.is_file():
            print(f"Warning: {fpath} not found")
            continue
        img = Image.open(fpath)
        # Resize to 960x540 for crisp display while keeping GIF under 5MB
        img_resized = img.resize((960, 540), Image.Resampling.LANCZOS)
        # Convert to P mode with adaptive palette for clean GIF compression
        img_p = img_resized.convert("P", palette=Image.Palette.ADAPTIVE, colors=256)
        frames.append(img_p)
        
    if not frames:
        print("No frames found to build GIF!")
        return
        
    gif_path = vdir / "terrain_dynamic_walk_streaming.gif"
    # Durations per frame (ms): 800ms for steps, 1200ms for chunk streaming
    durations = [800, 800, 1000, 800, 1000, 1200, 1500]
    if len(durations) != len(frames):
        durations = [900] * len(frames)
        
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

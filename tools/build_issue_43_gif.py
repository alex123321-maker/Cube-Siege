"""
tools/build_issue_43_gif.py - Assemble dynamic verification sequential captures into an animated GIF.
"""
from pathlib import Path
from PIL import Image

def main():
    root = Path(__file__).resolve().parent.parent
    vdir = root / "docs" / "verification" / "issue43"
    
    # Collect all sequential recorded transition frames
    seq_files = sorted(vdir.glob("dyn_seq_*.png"))
    
    if seq_files:
        print(f"[GIF] Found {len(seq_files)} sequential transition frames.")
        frames = []
        durations = []
        for i, fpath in enumerate(seq_files):
            img = Image.open(fpath)
            # Resize to 640x360 for clean 16:9 presentation and compact GIF size (~3-4 MB)
            img_resized = img.resize((640, 360), Image.Resampling.BILINEAR)
            img_p = img_resized.convert("P", palette=Image.Palette.ADAPTIVE, colors=128)
            frames.append(img_p)
            
            # Normal frame duration ~90ms (~11 fps); pause slightly on key milestones
            if i == 0 or i == len(seq_files) - 1:
                durations.append(500)
            else:
                durations.append(90)
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

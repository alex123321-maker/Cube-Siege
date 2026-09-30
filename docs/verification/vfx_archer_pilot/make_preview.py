"""Encode real Godot captures and build a labelled comparison; no generated frames."""
from pathlib import Path
import argparse
import json
import subprocess


def run(args, timeout=90):
    subprocess.run(args, check=True, timeout=timeout)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--raw-dir', type=Path, default=Path('D:/Temp/codex-archer-impact-01a0eb73'))
    parser.add_argument('--ffmpeg', default='D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe')
    args = parser.parse_args()
    out = Path(__file__).resolve().parent
    ffmpeg = [args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y']
    for name in ['before', 'after', 'surface']:
        raw = args.raw_dir / (name + '.avi')
        if raw.exists():
            run(ffmpeg + ['-i', str(raw), '-an', '-c:v', 'libx264', '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(out / (name + '.mp4'))])

    # First contact is at (80 warm-up + 28 action) / 60 = 1.8 s.
    # Two day contacts at 0.5x, two night-crowd contacts at 0.5x,
    # then three uninterrupted full-frame examples at normal speed.
    filters = []
    for index, (start, duration, crop, text) in enumerate([
        (1.55, 1.6, 'crop=640:500:370:120', 'DETAIL - DAY - 0.5x - MATCHED CROPS'),
        (10.55, 1.0, 'crop=640:500:345:145', 'CROWD - NIGHT - 0.5x - MATCHED CROPS'),
    ]):
        for stream, tag in [(0, 'b'), (1, 'a')]:
            filters.append(f'[{stream}:v]trim=start={start}:duration={duration},setpts=2*(PTS-STARTPTS),{crop}[{tag}{index}]')
        filters.append(f'[b{index}][a{index}]hstack=inputs=2,pad=1280:720:0:100:color=0x101820,'
                       f"drawtext=font=Arial:text='BEFORE':x=28:y=28:fontsize=27:fontcolor=white,"
                       f"drawtext=font=Arial:text='AFTER':x=668:y=28:fontsize=27:fontcolor=white,"
                       f"drawtext=font=Arial:text='{text}':x=28:y=650:fontsize=23:fontcolor=white[v{index}]")
    for index, (stream, start, duration) in enumerate([(1, 4.5, 2.8), (1, 10.5, 2.8), (2, 1.5, 2.0)], start=2):
        filters.append(f'[{stream}:v]trim=start={start}:duration={duration},setpts=PTS-STARTPTS,'
                       f"drawtext=font=Arial:text='1x - FULL FRAME':x=28:y=676:fontsize=23:fontcolor=white:box=1:boxcolor=black@0.65[v{index}]")
    filters.append('[v0][v1][v2][v3][v4]concat=n=5:v=1:a=0[v]')
    preview = out / 'archer-impact-before-after.mp4'
    run(ffmpeg + ['-i', str(out / 'before.mp4'), '-i', str(out / 'after.mp4'), '-i', str(out / 'surface.mp4'),
                  '-filter_complex', ';'.join(filters), '-map', '[v]', '-an', '-r', '60', '-c:v', 'libx264',
                  '-crf', '18', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(preview)])
    validation = {}
    probe = str(Path(args.ffmpeg).with_name('ffprobe.exe'))
    for path in [out / 'before.mp4', out / 'after.mp4', out / 'surface.mp4', preview]:
        run(ffmpeg + ['-xerror', '-i', str(path), '-f', 'null', '-'], timeout=60)
        result = subprocess.run([probe, '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                                 'stream=width,height,r_frame_rate:format=duration', '-of', 'json', str(path)],
                                check=True, capture_output=True, text=True, timeout=30)
        validation[path.name] = {'full_decode': 'passed', **json.loads(result.stdout)}
    for time, name in [(0.57, 'comparison-contact.png'), (3.8, 'comparison-crowd.png'), (11.025, 'comparison-terrain.png')]:
        run(ffmpeg + ['-ss', str(time), '-i', str(preview), '-frames:v', '1', str(out / name)], timeout=30)
    (out / 'media-validation.json').write_text(json.dumps(validation, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(validation, indent=2))


if __name__ == '__main__':
    main()

"""Package real before/after captures; no synthetic or interpolated frames."""
from pathlib import Path
import argparse
import json
import subprocess

HERE = Path(__file__).resolve().parent
FFMPEG = 'D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe'
FFPROBE = 'D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffprobe.exe'
FONT = r"fontfile='C\:/Windows/Fonts/arial.ttf'"


def run(args, timeout=90):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout)


def label(text, x, y, size=22):
    return f"drawtext={FONT}:text='{text}':x={x}:y={y}:fontsize={size}:fontcolor=white"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--capture-dir', type=Path, required=True)
    args = parser.parse_args()
    run([FFMPEG, '-y', '-v', 'error', '-i', str(args.capture_dir/'radius_blast.avi'),
         '-an', '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p',
         '-movflags', '+faststart', str(HERE/'radius_blast.mp4')])
    parts = []
    # Day and night crowd at native pixel size, with crop explicitly disclosed.
    for index, start in enumerate([4.9, 11.9]):
        for stream, side in [(0, 'a'), (1, 'b')]:
            parts.append(f'[{stream}:v]trim=start={start}:duration=2.4,setpts=PTS-STARTPTS,'
                         f'crop=640:480:320:140,setsar=1[{side}{index}]')
        parts.append(f'[a{index}][b{index}]hstack,pad=1280:720:0:120:color=0x101722,'
                     + label('BEFORE', 28, 60) + ',' + label('AFTER / FULL BLAST', 668, 60) + ','
                     + label('1x speed / game-camera crop / same immediate 250 damage and radius 4.5', 28, 640, 20)
                     + f'[ab{index}]')
    for index, start in enumerate([4.9, 8.4, 11.9, 15.4]):
        parts.append(f'[1:v]trim=start={start}:duration=2.4,setpts=PTS-STARTPTS,setsar=1[full{index}]')
    parts.append('[ab0][ab1][full0][full1][full2][full3]concat=n=6:v=1:a=0[out]')
    output = HERE/'radius-before-after.mp4'
    run([FFMPEG, '-y', '-v', 'error', '-i', str(HERE/'radius_before.mp4'),
         '-i', str(HERE/'radius_blast.mp4'), '-filter_complex', ';'.join(parts), '-map', '[out]',
         '-an', '-r', '60', '-c:v', 'libx264', '-preset', 'fast', '-crf', '18',
         '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(output)])
    validation = {}
    for file in [HERE/'radius_before.mp4', HERE/'radius_blast.mp4', output]:
        run([FFMPEG, '-v', 'error', '-i', str(file), '-f', 'null', '-'], 60)
        info = run([FFPROBE, '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                    'stream=width,height,r_frame_rate:format=duration', '-of', 'json', str(file)], 30)
        validation[file.name] = json.loads(info.stdout)
    run([FFMPEG, '-y', '-v', 'error', '-ss', '0.72', '-i', str(output), '-frames:v', '1',
         str(HERE/'radius-before-after-preview.png')], 30)
    (HERE/'radius-media-validation.json').write_text(json.dumps(validation, indent=2)+'\n')
    print(json.dumps(validation, indent=2))


if __name__ == '__main__':
    main()

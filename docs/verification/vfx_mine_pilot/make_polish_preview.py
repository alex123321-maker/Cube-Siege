"""Package actual before/after Godot captures; only crop, retime and label."""
from pathlib import Path
import json
import subprocess

HERE = Path(__file__).resolve().parent
TEMP = Path('D:/Temp/codex-mine-polish-01a0eb73')
FFMPEG = 'D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe'
FFPROBE = 'D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffprobe.exe'
FONT = r"fontfile='C\:/Windows/Fonts/arial.ttf'"
ENCODE = ['-an', '-r', '60', '-c:v', 'libx264', '-preset', 'fast', '-crf', '18',
          '-pix_fmt', 'yuv420p', '-movflags', '+faststart']


def run(args, timeout=90):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout)


def caption(text, x, y, size=24):
    return f"drawtext={FONT}:text='{text}':x={x}:y={y}:fontsize={size}:fontcolor=white"


def main():
    after = HERE/'polish_after.mp4'
    raw = TEMP/'polish_v3.avi'
    if raw.exists():
        run([FFMPEG, '-y', '-v', 'error', '-i', str(raw), *ENCODE, str(after)])
    pieces = []
    for index, start in enumerate([1.8, 12.3]):
        for source in range(2):
            pieces.append(f'[{source}:v]trim=start={start}:duration=2,setpts=2*(PTS-STARTPTS),'
                          f'crop=640:520:320:100,setsar=1[s{index}{source}]')
        title = 'DETAIL / DAY' if index == 0 else 'CROWD / NIGHT'
        pieces.append(f'[s{index}0][s{index}1]hstack=inputs=2,pad=1280:720:0:100:color=0x101722,'
                      + caption('BEFORE', 28, 38) + ',' + caption('POLISHED', 668, 38) + ','
                      + caption(f'{title} / 0.5x speed / detail crops / same radius and damage', 28, 653, 21)
                      + f'[ab{index}]')
    for index, start in enumerate([4.95, 11.95]):
        pieces.append(f'[1:v]trim=start={start}:duration=2.8,setpts=PTS-STARTPTS,setsar=1[g{index}]')
    pieces.append('[ab0][ab1][g0][g1]concat=n=4:v=1:a=0[out]')
    output = HERE/'mine-polish-before-after.mp4'
    run([FFMPEG, '-y', '-v', 'error', '-i', str(HERE/'polish_before.mp4'), '-i', str(after),
         '-filter_complex', ';'.join(pieces), '-map', '[out]', *ENCODE, str(output)])
    result = {}
    for file in [HERE/'polish_before.mp4', after, output]:
        run([FFMPEG, '-v', 'error', '-i', str(file), '-f', 'null', '-'], 60)
        info = run([FFPROBE, '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                    'stream=width,height,r_frame_rate:format=duration', '-of', 'json', str(file)], 30)
        result[file.name] = json.loads(info.stdout)
    (HERE/'polish-media-validation.json').write_text(json.dumps(result, indent=2)+'\n')
    for name, time in [('peak', 0.6), ('tail', 1.9), ('crowd', 4.6)]:
        run([FFMPEG, '-y', '-v', 'error', '-ss', str(time), '-i', str(output),
             '-frames:v', '1', str(HERE/f'polish-comparison-{name}.png')], 30)
    if raw.exists():
        assert raw.resolve().is_relative_to(TEMP.resolve())
        raw.unlink()
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()

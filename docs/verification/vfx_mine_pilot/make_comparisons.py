"""Package real Godot recordings. FFmpeg only trims, crops, labels and retimes.

No generated/interpolated frames. All commands have a 90-second deadline.
"""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[3]
MINE = ROOT / 'docs/verification/vfx_mine_pilot'
SWORD = ROOT / 'docs/verification/vfx_slash_pilot'
FFMPEG = 'D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe'
FFPROBE = 'D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffprobe.exe'
FONT = r"fontfile='C\:/Windows/Fonts/arial.ttf'"


def label(text, x, y, size=24):
    return f"drawtext={FONT}:text='{text}':x={x}:y={y}:fontsize={size}:fontcolor=white"


def encode(inputs, graph, output):
    args = [FFMPEG, '-y', '-v', 'error']
    for source in inputs:
        args += ['-i', str(source)]
    args += ['-filter_complex', graph, '-map', '[out]', '-an', '-r', '60',
             '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt',
             'yuv420p', '-movflags', '+faststart', str(output)]
    subprocess.run(args, check=True, timeout=90)
    info = subprocess.run([FFPROBE, '-v', 'error', '-select_streams', 'v:0',
                           '-show_entries', 'stream=width,height,r_frame_rate:format=duration',
                           '-of', 'json', str(output)], capture_output=True, text=True,
                          check=True, timeout=30)
    subprocess.run([FFMPEG, '-v', 'error', '-i', str(output), '-f', 'null', '-'],
                   check=True, timeout=60)
    print(output.name, info.stdout.strip(), flush=True)
    return json.loads(info.stdout)


def compare_segment(a, b, start, end, slowdown, titles, note, name):
    parts = []
    for stream, suffix in [(a, 'a'), (b, 'b')]:
        parts.append(f'[{stream}]trim=start={start}:end={end},setpts={slowdown}*(PTS-STARTPTS),'
                     f'crop=640:480:320:140,setsar=1[{name}{suffix}]')
    parts.append(f'[{name}a][{name}b]hstack=inputs=2,pad=1280:720:0:120:color=0x101722,'
                 + label(titles[0], 28, 58) + ',' + label(titles[1], 668, 58) + ','
                 + label(note, 28, 637, 21) + f'[{name}]')
    return ';'.join(parts)


def main():
    results = {}
    graph = '[0:v]split=1[a];[1:v]split=2[b][c];'
    graph += compare_segment('a', 'b', 0, 3.5, 2, ('ORIGINAL MINE', 'PAINTED MINE'),
                             '0.5x speed / detail crop / same damage and radius', 'ab') + ';'
    graph += '[c]trim=start=3.5:end=14,setpts=PTS-STARTPTS,setsar=1[game];'
    graph += '[ab][game]concat=n=2:v=1:a=0[out]'
    results['mine-before-after.mp4'] = encode([MINE/'baseline.mp4', MINE/'ember_final.mp4'],
                                            graph, MINE/'mine-before-after.mp4')

    graph = '[0:v]split=2[a][c];[1:v]split=3[b][d][e];'
    graph += compare_segment('a', 'b', 0, 3, 1, ('CURRENT SWORD', 'LUNA / SOFTER TAIL'),
                             '1x speed / detail crop / attacks every 0.35 seconds', 'ab') + ';'
    graph += compare_segment('c', 'd', 12, 15, 2, ('CURRENT SWORD', 'LUNA / SOFTER TAIL'),
                             '0.5x speed / detail crop / blade tracking without hit flashes', 'miss') + ';'
    graph += '[e]trim=start=6:end=12,setpts=PTS-STARTPTS,setsar=1[game];'
    graph += '[ab][miss][game]concat=n=3:v=1:a=0[out]'
    results['sword-soft-tail-ab.mp4'] = encode([SWORD/'current_rapid.mp4', SWORD/'luna_tail.mp4'],
                                             graph, SWORD/'sword-soft-tail-ab.mp4')

    graph = ';'.join(f'[{i}:v]trim=start=0:end=3.5,setpts=2*(PTS-STARTPTS),'
                     f'crop=480:480:400:140,setsar=1[v{i}]' for i in range(3)) + ';'
    graph += '[v0][v1][v2]hstack=inputs=3,pad=1440:640:0:80:color=0x101722,'
    graph += ','.join([label('REFERENCE', 24, 28), label('LUNA / CLEAR', 504, 28),
                       label('LUNA / WEIGHTY', 984, 28),
                       label('0.5x speed / detail crops / same textures and code; art parameters only', 24, 591, 22)]) + '[out]'
    results['mine-profile-variants.mp4'] = encode([MINE/'ember_final.mp4', MINE/'luna_clear.mp4',
                                                 MINE/'luna_weighty.mp4'], graph,
                                                MINE/'mine-profile-variants.mp4')
    (MINE/'media-validation.json').write_text(json.dumps(results, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()

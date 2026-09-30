"""Trim real Godot captures of ground imprints on the game's voxel steps."""
from pathlib import Path
import json
import subprocess

HERE = Path(__file__).resolve().parent
CAPTURES = Path('D:/Temp/codex-mine-ground-20260929')
FFMPEG = 'D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe'
FFPROBE = 'D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffprobe.exe'


def run(args, timeout=90):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=timeout)


def main():
    for name in ['ground_steps']:
        run([FFMPEG, '-y', '-v', 'error', '-i', str(CAPTURES/(name+'.avi')), '-an',
             '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p',
             '-movflags', '+faststart', str(HERE/(name+'.mp4'))])
    # Detail, game/day, game/night, crowd/night; full frame and 1x speed.
    clips = [(0, 1.45), (0, 4.95), (0, 8.45), (0, 11.95)]
    graph = ';'.join(f'[{source}:v]trim=start={start}:duration=2.8,setpts=PTS-STARTPTS[v{i}]'
                     for i, (source, start) in enumerate(clips))
    graph += ';[v0][v1][v2][v3]concat=n=4:v=1:a=0[out]'
    output = HERE/'ground-and-slopes.mp4'
    run([FFMPEG, '-y', '-v', 'error', '-i', str(HERE/'ground_steps.mp4'),
         '-filter_complex', graph, '-map', '[out]', '-an',
         '-c:v', 'libx264', '-preset', 'fast', '-crf', '18', '-pix_fmt', 'yuv420p',
         '-movflags', '+faststart', str(output)])
    results = {}
    for file in [HERE/'ground_steps.mp4', output]:
        run([FFMPEG, '-v', 'error', '-i', str(file), '-f', 'null', '-'], 60)
        info = run([FFPROBE, '-v', 'error', '-select_streams', 'v:0', '-show_entries',
                    'stream=width,height,r_frame_rate:format=duration', '-of', 'json', str(file)], 30)
        results[file.name] = json.loads(info.stdout)
    (HERE/'ground-media-validation.json').write_text(json.dumps(results, indent=2)+'\n')
    print(json.dumps(results, indent=2))


if __name__ == '__main__':
    main()

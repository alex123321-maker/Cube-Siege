"""Assemble the actual model renders into a review contact sheet; no generated concept art."""
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE=Path(__file__).resolve().parent
OUT=HERE/"review"
sheet=Image.new("RGB",(2200,1120),(233,230,222))
draw=ImageDraw.Draw(sheet)


def font(size,bold=False):
    return ImageFont.truetype("C:/Windows/Fonts/"+("bahnschrift.ttf" if bold else "segoeui.ttf"),size)


ink=(54,55,57)
muted=(104,103,100)
draw.text((50,27),"CUBE SIEGE",font=font(48,True),fill=ink)
draw.text((50,84),"CHARACTER STUDY  /  BLOCKBENCH",font=font(17),fill=muted)
draw.text((1410,31),"WARRIOR",font=font(43,True),fill=ink)
draw.text((1412,82),"STEEL  /  LEATHER  /  BLUE CLOTH",font=font(18),fill=muted)
draw.line((50,119,2150,119),fill=(163,161,155),width=2)

views=[("front","01  FRONT"),("side","02  PROFILE"),("back","03  BACK"),("three_quarter","04  THREE-QUARTER")]
for i,(name,label) in enumerate(views):
    # Identical canvas and scaling preserve proportions across all four views.
    image=Image.open(OUT/(name+".png")).convert("RGB")
    image=image.resize((512,574),Image.Resampling.LANCZOS)
    x=50+i*537
    sheet.paste(image,(x,144))
    draw.text((x,732),label,font=font(19,True),fill=ink)

draw.line((50,779,2150,779),fill=(163,161,155),width=2)
for i,name in enumerate(("gameplay","rear_three_quarter")):
    image=Image.open(OUT/(name+".png")).convert("RGB")
    image.thumbnail((245,274),Image.Resampling.LANCZOS)
    sheet.paste(image,(50+i*264,799))
draw.text((609,812),"REFERENCE-DRIVEN MODEL  /  v03 COMBAT IDLE",font=font(27,True),fill=ink)
draw.text((609,860),"Editable geometry, pixel atlas, separate sword and shield.",font=font(22),fill=muted)
draw.text((609,895),"Combat idle pose. Animation and gameplay integration are pending.",font=font(22),fill=muted)
report=json.loads((OUT/"report.json").read_text(encoding="utf-8"))
draw.text((609,946),f"{report['height_m']:.1f} m     /     {report['triangles']:,} triangles     /     512 px atlas",font=font(22,True),fill=ink)
for i,color in enumerate(((113,112,119),(87,58,41),(70,46,32),(48,71,104),(174,159,134),(191,132,91))):
    x=610+i*70
    draw.rectangle((x,1000,x+51,1033),fill=color)
draw.text((1150,1004),"RENDERS OF THE ACTUAL 3D ASSET",font=font(17),fill=muted)
sheet.save(OUT/"turnaround.jpg",quality=94,subsampling=0)
print(OUT/"turnaround.jpg")

before=OUT/"before_combat_idle"/"three_quarter.png"
if before.exists():
    comparison=Image.new("RGB",(1800,1150),(233,230,222))
    pen=ImageDraw.Draw(comparison)
    pen.text((50,26),"WARRIOR / COMBAT IDLE",font=font(40,True),fill=ink)
    for x,path,label in ((50,before,"v02 / LOW GUARD"),(925,OUT/"three_quarter.png","v03 / COMBAT IDLE")):
        frame=Image.open(path).convert("RGB").resize((825,924),Image.Resampling.LANCZOS)
        comparison.paste(frame,(x,124))
        pen.text((x,88),label,font=font(23,True),fill=ink)
    pose=report["pose"]
    pen.text((50,1081),f"Shoulder 9 deg  /  Elbow {pose['elbow_bend_deg']:.0f} deg  /  Blade {pose['blade_outward_deg']:.0f} deg outward, {pose['blade_forward_deg']:.0f} deg forward  /  Roll 8 deg",font=font(24),fill=ink)
    comparison.save(OUT/"combat_idle_comparison.jpg",quality=94,subsampling=0)
    print(OUT/"combat_idle_comparison.jpg")

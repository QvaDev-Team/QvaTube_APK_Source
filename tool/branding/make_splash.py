# Genera assets/splash/navidad.png y sanvalentin.png (provisionales, a partir del
# logo normal) hasta que diseño entregue el arte de esas temporadas.
# Uso: python3 tool/branding/make_splash.py [vista_previa.png]
import math, random
from PIL import Image, ImageDraw, ImageFilter

base = Image.open('assets/icons/icon-512.png').convert('RGBA')
W, H = base.size
SS = 4  # supersampling para bordes suaves

def layer():
    return Image.new('RGBA', (W*SS, H*SS), (0,0,0,0))

def finish(l):
    return l.resize((W, H), Image.LANCZOS)

def heart(d, cx, cy, s, color):
    pts = []
    for i in range(200):
        t = 2*math.pi*i/200
        x = 16*math.sin(t)**3
        y = 13*math.cos(t) - 5*math.cos(2*t) - 2*math.cos(3*t) - math.cos(4*t)
        pts.append(((cx + x*s)*SS, (cy - y*s)*SS))
    d.polygon(pts, fill=color)

def snowflake(d, cx, cy, r, color, w):
    for k in range(6):
        a = math.pi/3*k
        x2, y2 = cx + r*math.cos(a), cy + r*math.sin(a)
        d.line([(cx*SS, cy*SS), (x2*SS, y2*SS)], fill=color, width=int(w*SS))
        for f in (0.55,):
            bx, by = cx + r*f*math.cos(a), cy + r*f*math.sin(a)
            for sgn in (-1, 1):
                b = a + sgn*math.pi/4
                d.line([(bx*SS, by*SS), ((bx + r*0.32*math.cos(b))*SS, (by + r*0.32*math.sin(b))*SS)],
                       fill=color, width=int(w*SS))

# ── Navidad: gorro sobre la Q + copos ────────────────────────────────────
nav = base.copy()
l = layer(); d = ImageDraw.Draw(l)
random.seed(7)
for (x, y, r) in [(70,90,16),(430,80,20),(455,250,12),(60,420,14),(400,440,18),(250,60,11),(120,250,9),(470,390,10),(300,470,12)]:
    snowflake(d, x, y, r, (255,255,255,215), 2.2)
# gorro inclinado apoyado en la parte alta-derecha del aro de la Q
hat = Image.new('RGBA', (W*SS, H*SS), (0,0,0,0)); hd = ImageDraw.Draw(hat)
cx, top = 300, 70
hd.polygon([((cx-70)*SS,(top+75)*SS), ((cx+70)*SS,(top+75)*SS), ((cx+95)*SS,(top-25)*SS)], fill=(220,20,40,255))
hd.rounded_rectangle([(cx-82)*SS,(top+62)*SS,(cx+82)*SS,(top+92)*SS], radius=15*SS, fill=(250,250,250,255))
hd.ellipse([(cx+80)*SS,(top-42)*SS,(cx+112)*SS,(top-10)*SS], fill=(250,250,250,255))
hat = hat.rotate(-12, resample=Image.BICUBIC, center=(cx*SS,(top+80)*SS))
l = Image.alpha_composite(l, hat)
nav = Image.alpha_composite(nav, finish(l))
nav.save('assets/splash/navidad.png', optimize=True)

# ── San Valentín: corazones alrededor ───────────────────────────────────
val = base.copy()
l = layer(); d = ImageDraw.Draw(l)
for (x, y, s, c) in [(80,95,2.2,(255,77,109,235)),(430,95,2.8,(255,61,26,235)),(460,300,1.6,(255,120,150,220)),
                      (70,410,2.0,(255,61,26,220)),(410,440,2.4,(255,77,109,235)),(250,62,1.3,(255,140,165,210)),
                      (300,470,1.4,(255,120,150,210))]:
    heart(d, x, y, s, c)
glow = finish(l).filter(ImageFilter.GaussianBlur(6))
val = Image.alpha_composite(val, glow)
val = Image.alpha_composite(val, finish(l))
val.save('assets/splash/sanvalentin.png', optimize=True)

# vista previa de las 4
prev = Image.new('RGBA', (4*260, 260), (0,0,0,255))
for i, p in enumerate(['assets/icons/icon-512.png','assets/themes/halloween/icons/icon-512.png','assets/splash/navidad.png','assets/splash/sanvalentin.png']):
    im = Image.open(p).convert('RGBA').resize((256,256), Image.LANCZOS)
    prev.paste(im, (i*260+2, 2), im)
import sys
if len(sys.argv) > 1: prev.save(sys.argv[1])

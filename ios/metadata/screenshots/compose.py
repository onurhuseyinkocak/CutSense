import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter
S=sys.argv[1]
W,H=1290,2796
ACC=(182,243,92)
def font(size,weight):
    f=ImageFont.truetype('/System/Library/Fonts/SFNS.ttf',size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f
def shot(raw,lines,sub,out):
    bg=Image.new('RGB',(W,H),(0,0,0)); d=ImageDraw.Draw(bg)
    for y in range(H):  # top glow to black
        t=max(0,1-y/1400); c=int(14+30*t); d.line([(0,y),(W,y)],fill=(c,c+2,c+10))
    y=170
    for i,(txt,accent) in enumerate(lines):
        f=font(118,'Bold'); w=d.textlength(txt,font=f)
        d.text(((W-w)/2,y),txt,font=f,fill=ACC if accent else (255,255,255)); y+=140
    f2=font(54,'Regular'); w=d.textlength(sub,font=f2)
    d.text(((W-w)/2,y+20),sub,font=f2,fill=(165,170,180))
    # device
    im=Image.open(raw).convert('RGB'); dw=980; dh=int(im.height*dw/im.width)
    im=im.resize((dw,dh),Image.LANCZOS)
    top=y+150; r=110
    mask=Image.new('L',(dw,dh),0); ImageDraw.Draw(mask).rounded_rectangle([0,0,dw,dh],r,fill=255)
    bez=24; frame=Image.new('RGBA',(dw+2*bez,dh+2*bez),(0,0,0,0))
    ImageDraw.Draw(frame).rounded_rectangle([0,0,dw+2*bez-1,dh+2*bez-1],r+bez,fill=(28,30,36,255),outline=(70,74,84,255),width=4)
    shadow=Image.new('RGBA',(W,H),(0,0,0,0)); ImageDraw.Draw(shadow).rounded_rectangle([(W-dw)/2-bez,top-bez+30,(W+dw)/2+bez,top+dh+bez+30],r+bez,fill=(0,0,0,200))
    shadow=shadow.filter(ImageFilter.GaussianBlur(40))
    bg=Image.alpha_composite(bg.convert('RGBA'),shadow)
    x=(W-dw)//2
    bg.paste(frame,(x-bez,top-bez),frame)
    bg.paste(im,(x,top),mask)
    bg.convert('RGB').save(out,optimize=True)
shot(f'{S}/raw_review.png',[('Remove silence',False),('in one tap',True)],'Free. No watermark. No sign-up.',f'{S}/store/01_review.png')
shot(f'{S}/raw_cuts.png',[('Review',False),('every cut',True)],'Restore any pause before you save.',f'{S}/store/02_cuts.png')
shot(f'{S}/raw_home.png',[('Runs on',False),('your iPhone',True)],'Your video is never uploaded.',f'{S}/store/03_home.png')
shot(f'{S}/raw_paywall.png',[('No',False),('subscription',True)],'Free with ads. One-time Pro removes them.',f'{S}/store/04_pro.png')

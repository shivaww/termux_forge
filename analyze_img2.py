from PIL import Image
img = Image.open('assets/icon.png').convert('RGBA')
width, height = img.size
print("Star:", img.getpixel((width//2, height//2)))
print("Top Radiating Line:", img.getpixel((width//2, int(height*0.15))))

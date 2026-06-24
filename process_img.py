import math
from PIL import Image

img = Image.open('assets/icon.png').convert('RGBA')
pixels = img.load()
width, height = img.size

cx, cy = width / 2, height / 2

for y in range(height):
    for x in range(width):
        r, g, b, a = pixels[x, y]
        
        # Distance from center
        dx = x - cx
        dy = y - cy
        dist_center = math.sqrt(dx*dx + dy*dy)
        
        if dist_center > 440:
            pixels[x, y] = (r, g, b, 0)
            continue
            
        # Color distance to beige (245, 234, 221)
        dr = r - 245
        dg = g - 234
        db = b - 221
        dist_color = math.sqrt(dr*dr + dg*dg + db*db)
        
        if dist_color < 30:
            pixels[x, y] = (r, g, b, 0)
        elif dist_color < 80:
            # Smooth blend
            factor = (dist_color - 30) / 50.0
            pixels[x, y] = (r, g, b, int(255 * factor))

img.save('assets/icon_transparent.png')
print("Image saved as assets/icon_transparent.png")

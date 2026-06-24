from PIL import Image

img = Image.open('assets/icon.png').convert('RGBA')
pixels = list(img.getdata())
width, height = img.size

print("Corners:")
print("Top-Left:", pixels[0])
print("Top-Right:", pixels[width-1])

print("\nCenter:")
print("Center:", pixels[(height//2)*width + (width//2)])

print("\nCenter Top Line:")
print("Top Line:", pixels[(height//4)*width + (width//2)])

print("\nBeige background area (offset from center):")
print("Beige:", pixels[(height//4)*width + (width//4)])


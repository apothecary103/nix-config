#!/usr/bin/env bash

WALL_DIR="$HOME/Pictures/Wallpapers"
CACHE_DIR="$HOME/.cache/rofi-wallpapers"

if [ ! -d "$WALL_DIR" ]; then
  notify-send "Rofi Wallpaper" "Directory $WALL_DIR not found."
  exit 1
fi

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

menu_items=""

# Loop through all images, generate thumbnails if missing, and build the Rofi string
for img in "$WALL_DIR"/*.{jpg,jpeg,png,webp}; do
  # Skip if the glob didn't match anything
  [ -e "$img" ] || continue
  
  filename=$(basename "$img")
  thumb="$CACHE_DIR/${filename%.*}.jpg" # Save thumbnails as JPEGs for speed

  # If thumbnail doesn't exist, create it (strips metadata, crops to 512x512)
  if [ ! -f "$thumb" ]; then
    # magick "$img" -strip -resize 512x512^ -gravity center -extent 512x512 "$thumb"
    magick "$img" -strip -gravity center -crop 3024:1964 +repage "$thumb"
  fi

  # Append to menu items: "Filename\0icon\x1fThumbnailPath\n"
  menu_items+="${filename}\0icon\x1f${thumb}\n"
done

# Feed items to rofi
selected=$(echo -en "$menu_items" | rofi -dmenu \
  -show-icons \
  -p "wallpaper " \
  -theme-str 'window { width: 750px; }' \
  -theme-str 'listview { columns: 3; lines: 2; flow: horizontal; scrollbar: false; fixed-columns: true; }' \
  -theme-str 'element { orientation: vertical; padding: 15px; spacing: 0px; }' \
  -theme-str 'element-icon { size: 180px; }' \
  -theme-str 'element-text { horizontal-align: 0.5; }'
)

# Apply wallpaper if an image was selected
if [ -n "$selected" ]; then
  awww query || awww daemon &
  sleep 0.1 
  
  awww img "$WALL_DIR/$selected" \
    --transition-type fade \
    --transition-fps 120 \
    --transition-duration 1
fi

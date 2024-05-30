require 'find'
require 'mini_magick'

# Function to add rounded corners to an image
def add_rounded_corners(image_path, radius_percentage)
  image = MiniMagick::Image.open(image_path)
  width = image.width
  height = image.height
  radius = [(width * radius_percentage / 100.0), (height * radius_percentage / 100.0)].min

  # Ensure the image has an alpha channel
  image.combine_options do |c|
    c.alpha 'set'
    c.background 'none'
  end

  # Create a mask image with rounded corners
  mask = MiniMagick::Image.open(image_path)
  mask.format 'png'
  mask.combine_options do |c|
    c.alpha 'transparent'
    c.background 'none'
    c.fill 'white'
    c.draw "roundrectangle 0,0,#{width},#{height},#{radius},#{radius}"
  end

  # Apply the mask to the original image
  result = image.composite(mask) do |c|
    c.compose 'DstIn'
  end

  result.format 'png'
  result.write(image_path)
end

# Traverse the folder and process PNG images
def process_folder(folder_path)
  Find.find(folder_path) do |path|
    if File.extname(path).downcase == '.png'
      puts "Processing #{path}"
      add_rounded_corners(path, 22.5)
    end
  end
end


# Replace 'your_folder_path' with the path to your folder
process_folder('/Users/yanguosun/Developer/SFL3/SFL3/Assets.xcassets/AppIcon.appiconset')

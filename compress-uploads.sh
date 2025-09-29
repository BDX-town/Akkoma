#!/bin/sh

formats="\.webm$|\.flv$|\.vob$|\.ogg$|\.ogv$|\.drc$|\.gifv$|\.mng$|\.avi$|\.mov$|\.qt$|\.wmv$|\.yuv$|\.rm$|\.rmvb$|/.asf$|\.amv$|\.mp4$|\.m4v$|\.mp*$|\.m?v$|\.svi$|\.3gp$|\.flv$|\.f4v$"

# retrieve video files modified (and so uploaded) during the last 24 hours
for file in $(find . -type f -and -not -name "*.small.*" | grep -E $formats)
do 
    echo "Compressing $file in mp4";
    (
        ffmpeg -y -loglevel error -i $file -vcodec h264 -acodec aac -crf 28 $file.small.mp4 &&\
        rm $file &&\
        ln -s $file.small.mp4 $file
    ) || rm -f $file.small.mp4
done

# retrieve gif files modified (and so uploaded) during the last 24 hours
for file in $(find . -type f -and -not -name "*.small.*" | grep -E "\.gif$")
do 
    echo "Compressing $file in webp";
    (
        ffmpeg -y -loglevel error -i $file -vcodec libwebp -lossless 0 -loop 0 -pix_fmt yuva420p -compression_level 8 $file.small.webp &&\
        rm $file &&\
        ln -s $file.small.webp $file
    ) || rm -f $file.small.webp
done

# Retrieve PNG files modified during the last 24 hours
for file in $(find . -type f -and -not -name "*.small.*" -mtime -1 | grep -E "\.png$")
do
    echo "Compressing $file to WebP";
    (
        ffmpeg -y -loglevel error -i "$file" -vcodec libwebp -lossless 0 -pix_fmt yuva420p -compression_level 8 "${file%.png}.small.webp" && \
        rm "$file" && \
        ln -s "${file%.png}.small.webp" "$file"
    ) || rm -f "${file%.png}.small.webp"
done

# Retrieve JPEG/JPG files modified during the last 24 hours
for file in $(find . -type f -and -not -name "*.small.*" -mtime -1 | grep -E "\.(jpeg|jpg)$")
do
    echo "Compressing $file to WebP";
    (
        ffmpeg -y -loglevel error -i "$file" -vcodec libwebp -lossless 0 -pix_fmt yuva420p -compression_level 8 "${file%.*}.small.webp" && \
        rm "$file" && \
        ln -s "${file%.*}.small.webp" "$file"
    ) || rm -f "${file%.*}.small.webp"
done

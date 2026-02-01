#!/bin/bash

maim -s |
  magick - -modulate 100,0 -resize 400% -set density 300 png:- |
  tesseract stdin stdout -l eng+pol --psm 3 |
  sed 's/'$(printf '%b' '\014')'//g;s/|/I/g' |
  xsel -bi

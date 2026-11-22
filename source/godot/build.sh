#!/bin/sh
# Setzt die Engine aus core/parts/*.gd zusammen
cd "$(dirname "$0")"
cat core/parts/*.gd > core/game.gd

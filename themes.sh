#!/usr/bin/env bash

# Select theme: gruvbox | monokai_octagon | tokyonight
THEME="${THEME:-tokyonight}"

case "$THEME" in
  gruvbox)
    # BAR_BG=0xdd282828
    BAR_BG=0x40000000
    BAR_BORDER=0xff3c3836
    BAR_FG=0xffebdbb2

    SPACE_BG=0xff3c3836
    SPACE_ACTIVE_BG=0xfffabd2f
    SPACE_FG=0xffebdbb2
    SPACE_ACTIVE_FG=0xff1d2021
    SPACE_ACTIVE_BORDER=0xfffe8019

    RIGHT_ICON=0xffebdbb2
    RIGHT_LABEL=0xffebdbb2
    ;;

  monokai_octagon)
    # BAR_BG=0xdd1e1f1c
    BAR_BG=0x40000000
    BAR_BG=0xdd1e1f1c
    BAR_BORDER=0xff2d2e27
    BAR_FG=0xfff8f8f2

    SPACE_BG=0xff2d2e27
    SPACE_ACTIVE_BG=0xfffc9867
    SPACE_FG=0xfff8f8f2
    SPACE_ACTIVE_FG=0xff1e1f1c
    SPACE_ACTIVE_BORDER=0xffffd866

    RIGHT_ICON=0xfff8f8f2
    RIGHT_LABEL=0xfff8f8f2
    ;;

  tokyonight|*)
    # BAR_BG=0xdd1a1b26
    BAR_BG=0x40000000
    BAR_BORDER=0xff24283b
    BAR_FG=0xffffffff

    SPACE_BG=0xff292e42
    SPACE_ACTIVE_BG=0xff7aa2f7
    SPACE_FG=0xffc0caf5
    SPACE_ACTIVE_FG=0xff1a1b26
    # SPACE_ACTIVE_BORDER=0xffbb9af7
    SPACE_ACTIVE_BORDER=0xff7aa2f7

    RIGHT_ICON=0xffc0caf5
    RIGHT_LABEL=0xffc0caf5
    ;;
esac

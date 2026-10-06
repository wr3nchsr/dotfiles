#!/bin/bash

# tmux configurations and plugins
TMUX_PLUGINS=.config/tmux/plugins
mkdir -p $TMUX_PLUGINS
git clone https://github.com/tmux-plugins/tpm $TMUX_PLUGINS/tpm

stow -v --ignore=setup.sh .

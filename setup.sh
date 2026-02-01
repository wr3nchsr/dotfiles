#!/bin/bash

# tmux configurations and plugins
mkdir -p ~/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

mkdir -p ~/.config

stow -t ~/.config config

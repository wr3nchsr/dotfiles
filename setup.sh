#!/bin/bash

SCRIPT_PATH=$(realpath "$0" | sed 's|\(.*\)/.*|\1|')

# tmux configurations and plugins
mkdir -p ~/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
ln -s ${SCRIPT_PATH}/configs/tmux/tmux.conf ~/.tmux.conf
ln -s ${SCRIPT_PATH}/configs/tmux/custom-status ~/.tmux/plugins/custom-status
mkdir -p ~/.config

# alacritty configurations and theme
ln -s ${SCRIPT_PATH}/configs/alacritty ~/.config/alacritty

# bat configurations and theme
ln -s ${SCRIPT_PATH}/configs/bat ~/.config/bat

# nvim configurations and plugins 
ln -s ${SCRIPT_PATH}/configs/nvim ~/.config/nvim


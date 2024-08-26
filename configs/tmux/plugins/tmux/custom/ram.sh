show_ram() {
  local index icon color text module

  index=$1
  icon=$(get_tmux_option "@catppuccin_ram_icon" "")
  color="$(get_tmux_option "@catppuccin_ram_color" "#{ram_bg_color}")"
  text="$(get_tmux_option "@catppuccin_ram_text" "#{ram_percentage}")"

  tmux set-option -g @ram_low_bg_color "$thm_yellow"    # background color when cpu is low
  tmux set-option -g @ram_medium_bg_color "$thm_orange" # background color when cpu is medium
  tmux set-option -g @ram_high_bg_color "$thm_red"      # background color when cpu is high

  module=$(build_status_module "$index" "$icon" "$color" "$text")

  echo "$module"
}

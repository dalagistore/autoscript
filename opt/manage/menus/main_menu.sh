# shellcheck shell=bash
# Main menu
# -------------------------
# Catatan maintainability:
# Beberapa target action di bawah ini masih diimplementasikan di manage.sh selama
# fase modularisasi transisi. Jangan menghapus handler lama sebelum logic benar-benar
# dipindah dan smoke test menu terkait lulus.
tools_warp_tier_menu() {
  local prev="${WARP_TIER_MENU_CONTEXT:-}"
  WARP_TIER_MENU_CONTEXT="tools"
  menu_run_isolated_report "WARP Tier" warp_tier_menu
  local rc=$?
  WARP_TIER_MENU_CONTEXT="${prev}"
  return "${rc}"
}

tools_menu() {
  local -a items=(
    "1|Telegram Bot"
    "2|WARP Tier"
    "3|Backup/Restore"
    "4|Uninstall"
    "0|Back"
  )
  while true; do
    ui_menu_screen_begin "15) Tools"
    ui_menu_render_options items 76
    hr
    if ! read -r -p "Pilih: " c; then
      echo
      break
    fi
    case "${c}" in
      1) run_action "Telegram Bot" install_telegram_bot_menu ;;
      2) tools_warp_tier_menu ;;
      3|backup|restore|backup-restore) run_action "Backup/Restore" backup_restore_menu ;;
      4|uninstall) autoscript_uninstall_menu ;;
      0|kembali|k|back|b) break ;;
      *) warn "Pilihan tidak valid" ; sleep 1 ;;
    esac
  done
}

main_menu_render_options() {
  # shellcheck disable=SC2034
  local -a items=(
    "1|Xray Users"
    "2|SSH Users"
    "3|WireGuard Users"
    "4|Shadowsocks Users"
    "5|Xray QAC"
    "6|SSH QAC"
    "7|Xray Network"
    "8|SSH Network"
    "9|Adblocker"
    "10|Domain Control"
    "11|Speedtest"
    "12|Security"
    "13|Maintenance"
    "14|Traffic"
    "15|Tools"
    "0|Keluar"
  )
  ui_menu_render_two_columns_fixed items
}


main_menu() {
  while true; do
    title
    main_menu_info_header_print
    main_menu_center_line "Main Menu"
    hr
    main_menu_render_options
    hr
    if ! read -r -p "Pilih: " c; then
      echo
      exit 0
    fi
    case "${c}" in
      1) run_action "Xray Users" user_menu ;;
      2|ssh) run_action "SSH Users" ssh_menu ;;
      3|wireguard|wg) 
        if declare -F wireguard_users_menu >/dev/null 2>&1; then
          run_action "WireGuard Users" wireguard_users_menu
        else
          warn "Modul WireGuard Users belum dipasang."
          sleep 2
        fi
        ;;
      4|shadowsocks|ss)
        if declare -F shadowsocks_users_menu >/dev/null 2>&1; then
          run_action "Shadowsocks Users" shadowsocks_users_menu
        else
          warn "Modul Shadowsocks Users belum dipasang."
          sleep 2
        fi
        ;;
      5|quota) run_action "Xray QAC" quota_menu ;;
      6|qac|ssh-qac) run_action "SSH QAC" ssh_quota_menu ;;
      7|network) run_action "Xray Network" network_menu ;;
      8|ssh-network|sshnet) run_action "SSH Network" ssh_network_menu ;;
      9|adblock|adblocker) run_action "Adblocker" adblock_menu ;;
      10|domain) run_action "Domain Control" domain_control_menu ;;
      11|speedtest|speed) run_action "Speedtest" speedtest_menu ;;
      12|security) run_action "Security" fail2ban_menu ;;
      13|maintenance|maint) run_action "Maintenance" maintenance_menu ;;
      14|analytics|traffic) run_action "Traffic" traffic_analytics_menu ;;
      15|tools) tools_menu ;;
      0|kembali|k|back|b) exit 0 ;;
      *) invalid_choice ;;
    esac
  done
}

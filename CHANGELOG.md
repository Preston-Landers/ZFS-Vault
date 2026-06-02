# Changelog for ZFS-Vault

- v0.2.0: Improve password-entry UX so boot output no longer obscures the
  prompt. The console loglevel is quieted during entry (`quiet_console`,
  default on) and restored afterward, and the prompt is shown in a whiptail
  dialog when available (`use_whiptail`, default on) or a clear text banner
  otherwise. The prompt text is customizable via `prompt_message`.

- v0.1.1: Fix unloading the vault key after unlock.

- v0.1.0: Initial release.

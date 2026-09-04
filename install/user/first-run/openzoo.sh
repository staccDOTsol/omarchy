# openzoo -- the agent, the bar widget and the ingest plugin, installed by
# openzoo.fun/omarchymax -- set up once at first login, in a floating terminal
# that the installer then hands over to the agent. Personal branch, not for
# upstream: it installs a third-party agent that mints its own wallet.
#
# Guarded so a --force rerun of first-run does not reinstall it; re-run the
# curl by hand to update, which is openzoo's own update path.
omarchy-done ensure openzoo-install || exit 0

omarchy-launch-floating-terminal-with-presentation \
  'curl -fsSL https://openzoo.fun/omarchymax | bash'

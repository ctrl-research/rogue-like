# The dedicated game server: an exported Godot headless binary, nothing more.
#
# The binary is built by CI (the "Server" export preset) and copied in, rather
# than built here — a Godot toolchain in the image would dwarf the game.
FROM debian:bookworm-slim

# Godot headless still links against these even with no display.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libfontconfig1 libfreetype6 ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Unprivileged: this listens on the internet, and it needs nothing root can do.
#
# The GID is pinned as well as the UID. --uid alone leaves the group
# auto-assigned (it came out as 999), which then disagrees with the
# runAsGroup/fsGroup the Kubernetes manifest declares — and fsGroup is what makes
# the mounted HOME writable. Matching them removes the discrepancy rather than
# relying on it not mattering.
RUN groupadd --system --gid 10001 abyssal \
 && useradd --system --create-home --uid 10001 --gid 10001 abyssal
WORKDIR /app
COPY --chown=abyssal:abyssal abyssal-server /app/abyssal-server
RUN chmod +x /app/abyssal-server
USER abyssal

# Godot writes its user:// data here; a writable HOME keeps it out of /.
ENV HOME=/home/abyssal
ENV PORT=9100
# Empty means an OPEN server: anyone who can reach it can join. Set this for
# anything publicly reachable.
ENV JOIN_PASSWORD=""
EXPOSE 9100

# --headless: no display. The `--` separates Godot's own args from the game's, and
# Net.is_dedicated() also keys off the export preset's dedicated_server feature, so
# --dedicated here is belt and braces for running the same binary interactively.
# stdbuf -oL -eL, because otherwise this container produces NO LOGS AT ALL.
#
# Godot writes through libc stdio, which block-buffers when stdout is a pipe rather
# than a terminal — and in a container it is always a pipe. The engine banner, the
# "listening on ws://..." line and whether a password is required all sat in a 4KB
# buffer instead of reaching kubectl logs, so a perfectly healthy server was
# indistinguishable from one that had silently failed to start.
ENTRYPOINT ["/bin/sh", "-c", "exec stdbuf -oL -eL /app/abyssal-server --headless -- --dedicated --port \"$PORT\""]

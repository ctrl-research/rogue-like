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
RUN useradd --system --create-home --uid 10001 abyssal
WORKDIR /app
COPY --chown=abyssal:abyssal abyssal-server /app/abyssal-server
RUN chmod +x /app/abyssal-server
USER abyssal

# Godot writes its user:// data here; a writable HOME keeps it out of /.
ENV HOME=/home/abyssal
ENV PORT=9100
EXPOSE 9100

# --headless: no display. The `--` separates Godot's own args from the game's, and
# Net.is_dedicated() also keys off the export preset's dedicated_server feature, so
# --dedicated here is belt and braces for running the same binary interactively.
ENTRYPOINT ["/bin/sh", "-c", "exec /app/abyssal-server --headless -- --dedicated --port \"$PORT\""]

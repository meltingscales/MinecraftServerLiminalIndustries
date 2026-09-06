#!/usr/bin/env python3
"""Minimal interactive Source RCON client (stdlib only, no mcrcon package needed)."""
import argparse
import getpass
import socket
import struct
import sys

try:
    import readline  # noqa: F401  (imported for input() line-editing side effects)
except ImportError:
    readline = None

SERVERDATA_AUTH = 3
SERVERDATA_AUTH_RESPONSE = 2
SERVERDATA_EXECCOMMAND = 2
SERVERDATA_RESPONSE_VALUE = 0


def send_packet(sock, request_id, packet_type, payload):
    body = struct.pack("<ii", request_id, packet_type) + payload.encode("utf-8") + b"\x00\x00"
    sock.sendall(struct.pack("<i", len(body)) + body)


def read_packet(sock):
    length = struct.unpack("<i", recv_exact(sock, 4))[0]
    body = recv_exact(sock, length)
    request_id, packet_type = struct.unpack("<ii", body[:8])
    payload = body[8:-2].decode("utf-8", errors="replace")
    return request_id, packet_type, payload


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("RCON connection closed unexpectedly")
        data += chunk
    return data


def main():
    parser = argparse.ArgumentParser(description="Interactive Minecraft RCON console")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=25575)
    parser.add_argument("--password-file", help="read password from file instead of prompting (for unattended/cron use)")
    parser.add_argument("command", nargs="*", help="run a single command and exit instead of an interactive REPL")
    args = parser.parse_args()

    if args.password_file:
        with open(args.password_file) as f:
            password = f.read().strip()
    else:
        password = getpass.getpass("RCON password: ")

    def connect():
        sock = socket.create_connection((args.host, args.port), timeout=10)
        send_packet(sock, 1, SERVERDATA_AUTH, password)
        # Minecraft sends an empty SERVERDATA_RESPONSE_VALUE before the real
        # SERVERDATA_AUTH_RESPONSE; skip it so it doesn't get mistaken for the
        # first command's output later.
        request_id, packet_type, _ = read_packet(sock)
        if packet_type != SERVERDATA_AUTH_RESPONSE:
            request_id, _, _ = read_packet(sock)
        if request_id == -1:
            sock.close()
            print("Authentication failed.", file=sys.stderr)
            sys.exit(1)
        return sock

    sock = connect()

    def run(cmd):
        send_packet(sock, 2, SERVERDATA_EXECCOMMAND, cmd)
        _, _, payload = read_packet(sock)
        print(payload)

    try:
        if args.command:
            run(" ".join(args.command))
            return

        print("Connected. Type commands, Ctrl-D to exit.")
        if readline is not None:
            print("  Up/Down: command history   Left/Right: move cursor   Ctrl-R: search history")
        while True:
            try:
                cmd = input("> ")
            except (EOFError, KeyboardInterrupt):
                print()
                break
            if not cmd.strip():
                continue
            try:
                run(cmd)
            except (ConnectionError, OSError):
                print("(connection dropped, reconnecting...)", file=sys.stderr)
                sock.close()
                sock = connect()
                run(cmd)
    finally:
        sock.close()


if __name__ == "__main__":
    main()

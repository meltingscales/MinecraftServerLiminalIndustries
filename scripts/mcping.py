#!/usr/bin/env python3
"""Minecraft Server List Ping client (stdlib only) - grabs the status banner
(MOTD, version, player count) that the vanilla client shows in the server
list, without needing a real client connection. Exits non-zero if the
handshake/status request fails, so this can be used as a liveness check."""
import argparse
import json
import socket
import struct
import sys


def write_varint(value):
    # Treat as unsigned 32-bit: the handshake sends protocol version -1 (don't
    # care) for a status ping, and Python's right-shift sign-extends negative
    # ints forever instead of terminating like Java/C's fixed-width shift would.
    value &= 0xFFFFFFFF
    out = b""
    while True:
        byte = value & 0x7F
        value >>= 7
        out += struct.pack("B", byte | (0x80 if value else 0))
        if not value:
            return out


def read_varint(sock):
    value = 0
    for i in range(5):
        byte = recv_exact(sock, 1)[0]
        value |= (byte & 0x7F) << (7 * i)
        if not (byte & 0x80):
            return value
    raise ValueError("VarInt too big")


def recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("connection closed unexpectedly")
        data += chunk
    return data


def write_string(s):
    encoded = s.encode("utf-8")
    return write_varint(len(encoded)) + encoded


def send_packet(sock, packet_id, payload):
    body = write_varint(packet_id) + payload
    sock.sendall(write_varint(len(body)) + body)


def read_packet(sock):
    length = read_varint(sock)
    body = recv_exact(sock, length)
    return body


def status(host, port, timeout):
    with socket.create_connection((host, port), timeout=timeout) as sock:
        # Handshake: protocol version -1 (unknown/don't-care for status), next state 1 (status)
        handshake = write_varint(-1) + write_string(host) + struct.pack(">H", port) + write_varint(1)
        send_packet(sock, 0x00, handshake)

        # Status request: empty body
        send_packet(sock, 0x00, b"")

        body = read_packet(sock)
        packet_id, offset = read_varint_from_bytes(body, 0)
        str_len, offset = read_varint_from_bytes(body, offset)
        json_str = body[offset:offset + str_len].decode("utf-8")
        return json.loads(json_str)


def read_varint_from_bytes(data, offset):
    value = 0
    for i in range(5):
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << (7 * i)
        if not (byte & 0x80):
            return value, offset
    raise ValueError("VarInt too big")


def main():
    parser = argparse.ArgumentParser(description="Query a Minecraft server's status (Server List Ping)")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=25565)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--json", action="store_true", help="print raw JSON instead of a summary")
    args = parser.parse_args()

    try:
        data = status(args.host, args.port, args.timeout)
    except (OSError, ValueError, ConnectionError) as e:
        print(f"ping failed: {e}", file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(data, indent=2))
        return

    version = data.get("version", {}).get("name", "?")
    players = data.get("players", {})
    online, maximum = players.get("online", "?"), players.get("max", "?")
    description = data.get("description", "")
    if isinstance(description, dict):
        description = description.get("text", "") or "".join(
            e.get("text", "") for e in description.get("extra", [])
        )
    print(f"{args.host}:{args.port} - {version} - {online}/{maximum} players")
    if description:
        print(description)


if __name__ == "__main__":
    main()

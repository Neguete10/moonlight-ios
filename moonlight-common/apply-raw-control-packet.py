#!/usr/bin/env python3
"""Insert LiSendRawControlStreamPacket into the pinned moonlight-common-c.

moonlight-stream/moonlight-common-c does not have this entry point at the
pinned commit, and this tree cannot publish a replacement commit. The Xcode
static-library target runs this before compiling. It is safe to run again:
a checkout that already contains the symbol is left untouched.
"""

import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "moonlight-common-c", "src")

HEADER_ANCHOR = (
    "bool LiGetEstimatedRttInfo(uint32_t* estimatedRtt, uint32_t* estimatedRttVariance);\n"
)
HEADER_INSERT = (
    "\n"
    "// Sends a caller-supplied packet on the encrypted ENet control stream.\n"
    "// payloadLength must be 251 or less: encryption copies a 4-byte header plus\n"
    "// the payload into a 256-byte buffer. Returns 0 on success. Returns -1 when\n"
    "// the control stream is down, is not encrypted, or the send fails.\n"
    "int LiSendRawControlStreamPacket(unsigned short packetType, const void* payload, unsigned short payloadLength);\n"
)

SOURCE_ANCHOR = (
    "static bool sendMessageAndDiscardReply(short ptype, short paylen, const void* payload, uint8_t channelId, uint32_t flags, bool moreData) {\n"
)
SOURCE_INSERT = (
    "int LiSendRawControlStreamPacket(unsigned short packetType, const void* payload, unsigned short payloadLength) {\n"
    "    static const unsigned char emptyByte = 0;\n"
    "\n"
    "    // sizeof(NVCTL_ENET_PACKET_HEADER_V2) + paylen must be strictly under 256.\n"
    "    if (payloadLength > 251) {\n"
    "        return -1;\n"
    "    }\n"
    "    if (payload == NULL) {\n"
    "        if (payloadLength != 0) {\n"
    "            return -1;\n"
    "        }\n"
    "        payload = &emptyByte;\n"
    "    }\n"
    "    if (!encryptedControlStream || peer == NULL || stopping ||\n"
    "            peer->state != ENET_PEER_STATE_CONNECTED) {\n"
    "        return -1;\n"
    "    }\n"
    "    if (!sendMessageAndForget((short)packetType, (short)payloadLength, payload,\n"
    "                              0, ENET_PACKET_FLAG_RELIABLE, false)) {\n"
    "        return -1;\n"
    "    }\n"
    "    return 0;\n"
    "}\n"
    "\n"
)

SYMBOL = "LiSendRawControlStreamPacket"


def rewrite(path, transform):
    with open(path, "r", encoding="utf-8", newline="") as handle:
        original = handle.read()
    updated = transform(original, path)
    if updated == original:
        return
    directory = os.path.dirname(path)
    fd, temporary = tempfile.mkstemp(dir=directory, prefix=".raw-control-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(updated)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def insert_header(text, path):
    if SYMBOL in text:
        return text
    if text.count(HEADER_ANCHOR) != 1:
        raise SystemExit("could not find the RTT declaration in %s" % path)
    return text.replace(HEADER_ANCHOR, HEADER_ANCHOR + HEADER_INSERT, 1)


def insert_source(text, path):
    if SYMBOL in text:
        return text
    if "sendMessageAndForget" not in text:
        raise SystemExit("sendMessageAndForget is missing from %s" % path)
    if text.count(SOURCE_ANCHOR) != 1:
        raise SystemExit("could not find sendMessageAndDiscardReply in %s" % path)
    return text.replace(SOURCE_ANCHOR, SOURCE_INSERT + SOURCE_ANCHOR, 1)


def main():
    header = os.path.join(SRC, "Limelight.h")
    source = os.path.join(SRC, "ControlStream.c")
    for path in (header, source):
        if not os.path.isfile(path):
            raise SystemExit("missing %s (run git submodule update --init)" % path)
    rewrite(header, insert_header)
    rewrite(source, insert_source)
    return 0


if __name__ == "__main__":
    sys.exit(main())

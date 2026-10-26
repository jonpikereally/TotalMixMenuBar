"""Pretend to be TotalMix in Global OSC mode, for ./test.sh.
Usage: python3 -I fake_totalmix.py <listen-port> <reply-port> <log-file>"""
import socket, struct, sys, time
def pad(b): return b + b'\0' * (4 - len(b) % 4)
def msg(addr, v):
    if isinstance(v, str): return pad(addr.encode()) + pad(b',s') + pad(v.encode())
    return pad(addr.encode()) + pad(b',f') + struct.pack('>f', v)
def bundle(msgs):
    out = pad(b'#bundle') + b'\0' * 8
    for m in msgs: out += struct.pack('>i', len(m)) + m
    return out
def addr_of(b): return b[:b.index(b'\0')].decode()
STATE = [
    ('/status/device', 'Fireface UCX II (24129057)'),
    ('/controlroom/mainout', 0.0), ('/controlroom/phones1', 6.0), ('/controlroom/phones2', -1.0),
    ('/output/0/name', 'AN 1/2'), ('/output/0/color', 3.0), ('/output/0/stereo', 1.0),
    ('/output/0/volume', -25.1), ('/output/0/mute', 0.0), ('/output/0/eq/enable', 1.0),
    ('/output/1/name', 'AN 2'), ('/output/1/color', 3.0),
    ('/output/6/name', 'PH 7/8'), ('/output/6/color', 3.0), ('/output/6/stereo', 1.0),
    ('/output/6/volume', -10.4), ('/output/6/mute', 0.0),
    ('/output/12/name', 'ADAT 1/2'), ('/output/12/color', 0.0), ('/output/12/stereo', 1.0),
    ('/input/0/name', 'Mic 1'), ('/input/0/color', 1.0), ('/input/0/48v', 1.0), ('/input/0/instrument', 0.0),
    ('/input/0/dynamics/enable', 1.0), ('/input/0/eq/enable', 0.0),
    ('/input/1/name', 'Mic 2'), ('/input/1/color', 1.0), ('/input/1/48v', 0.0), ('/input/1/instrument', 1.0),
    ('/input/2/name', 'Line 3'), ('/input/2/color', 1.0),
    ('/controlroom/dim', 0.0), ('/controlroom/mainmono', 1.0), ('/controlroom/speakerb', 0.0),
    ('/level/in/0', -12.5),
]
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(('127.0.0.1', int(sys.argv[1]))); s.settimeout(0.2)
dest = ('127.0.0.1', int(sys.argv[2]))
log = open(sys.argv[3], 'w', buffering=1)
end = time.time() + 20
while time.time() < end:
    try:
        d, _ = s.recvfrom(65536)
    except socket.timeout:
        s.sendto(msg('/status/connection', 1.0), dest)  # heartbeat
        continue
    a = addr_of(d)
    log.write(a + ' ' + repr(struct.unpack('>f', d[-4:])[0]) + '\n')
    if a == '/sendall':
        s.sendto(bundle([msg(k, v) for k, v in STATE]), dest)
    elif a != '/sendstate':
        s.sendto(d, dest)  # echo like "Re-send received"

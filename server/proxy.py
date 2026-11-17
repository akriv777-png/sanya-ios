#!/usr/bin/env python3
"""Sanya AI proxy: OpenAI-compatible /v1/chat/completions guarded by per-device app keys.
Upstream: Pollinations anonymous (no key) -> fallback Antigravity CLI (Gemini Flash).
No provider secrets live in the app. Keys are stored as sha256 hashes in keys.json."""
import json, hashlib, time, os, subprocess, threading, urllib.request, sys, secrets
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

HERE = os.path.dirname(os.path.abspath(__file__))
KEYS = os.path.join(HERE, 'keys.json')
LOG = os.path.join(HERE, 'proxy.log')
PORT = int(os.environ.get('SANYA_PORT', '8787'))
AGY = '/home/box/.local/bin/agy'
RATE = 30  # requests per minute per key
_hits = {}
_lock = threading.Lock()

def log(*a):
    with open(LOG, 'a') as f:
        f.write(time.strftime('%F %T ') + ' '.join(str(x) for x in a) + '\n')

def load_keys():
    try: return json.load(open(KEYS))
    except Exception: return {}

def check_key(k):
    if not k: return None
    h = hashlib.sha256(k.encode()).hexdigest()
    return load_keys().get(h)

def rate_ok(dev):
    now = time.time()
    with _lock:
        arr = [t for t in _hits.get(dev, []) if now - t < 60]
        if len(arr) >= RATE: _hits[dev] = arr; return False
        arr.append(now); _hits[dev] = arr; return True

def pollinations(messages, temperature, max_tokens):
    body = json.dumps({"model": "openai", "messages": messages, "temperature": temperature,
                       "max_tokens": max_tokens, "private": True}).encode()
    req = urllib.request.Request('https://text.pollinations.ai/openai', data=body,
                                 headers={'Content-Type': 'application/json', 'User-Agent': 'sanya-proxy/1'})
    with urllib.request.urlopen(req, timeout=60) as r:
        d = json.load(r)
    txt = d['choices'][0]['message'].get('content') or ''
    if not txt.strip(): raise RuntimeError('empty')
    return txt

def agy(messages):
    prompt = "\n\n".join(f"[{m.get('role')}]\n{m.get('content') if isinstance(m.get('content'), str) else json.dumps(m.get('content'), ensure_ascii=False)}" for m in messages)
    prompt += "\n\n[assistant]\nОтветь только текстом ответа ассистента, без пояснений и без инструментов."
    out = subprocess.run([AGY, '-p', prompt, '--model', 'gemini-3.8-flash-low', '--print-timeout', '90s',
                          '--disable-slash-commands'], capture_output=True, text=True, timeout=120, cwd='/tmp')
    txt = out.stdout.strip()
    if out.returncode != 0 or not txt or 'AGY_ERROR' in txt: raise RuntimeError('agy failed')
    return txt

class H(BaseHTTPRequestHandler):
    server_version = 'sanya-proxy'
    def _send(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code); self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith('/health'): return self._send(200, {"ok": True, "service": "sanya-ai", "v": 1})
        self._send(404, {"error": "not found"})
    def do_POST(self):
        auth = self.headers.get('Authorization', '')
        key = auth[7:] if auth.startswith('Bearer ') else ''
        dev = check_key(key)
        if not dev: return self._send(401, {"error": {"message": "bad app key"}})
        if not rate_ok(dev): return self._send(429, {"error": {"message": "slow down"}})
        if not self.path.rstrip('/').endswith('/chat/completions'): return self._send(404, {"error": "not found"})
        try:
            n = int(self.headers.get('Content-Length', '0'))
            if n > 200_000: return self._send(413, {"error": "too big"})
            req = json.loads(self.rfile.read(n) or b'{}')
            msgs = req.get('messages') or []
            temp = float(req.get('temperature', 0.8)); mt = min(int(req.get('max_tokens', 700)), 1500)
            t0 = time.time(); src = 'pollinations'
            try: txt = pollinations(msgs, temp, mt)
            except Exception as e:
                log('pollinations fail', type(e).__name__); src = 'agy'; txt = agy(msgs)
            log('ok', dev, src, f'{time.time()-t0:.1f}s', len(txt))
            self._send(200, {"id": "sanya-" + secrets.token_hex(6), "object": "chat.completion", "model": src,
                             "choices": [{"index": 0, "message": {"role": "assistant", "content": txt}, "finish_reason": "stop"}]})
        except Exception as e:
            log('error', dev, type(e).__name__)
            self._send(502, {"error": {"message": "upstream unavailable"}})

if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == 'newkey':
        k = 'sk-sanya-' + secrets.token_urlsafe(24)
        d = load_keys(); d[hashlib.sha256(k.encode()).hexdigest()] = sys.argv[2]
        json.dump(d, open(KEYS, 'w')); os.chmod(KEYS, 0o600)
        open(os.path.join(HERE, f'key_{sys.argv[2]}.txt'), 'w').write(k); os.chmod(os.path.join(HERE, f'key_{sys.argv[2]}.txt'), 0o600)
        print('key written to', f'key_{sys.argv[2]}.txt'); sys.exit()
    ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()

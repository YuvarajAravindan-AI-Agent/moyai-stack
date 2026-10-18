"""Create a Modal sandbox through Moyai's patched adapter and test egress (canary vs GitHub)."""
import asyncio, sys
from app.config import Settings
from app.sandboxes import provider
from app.modal_clients import ModalClients

CANARY = sys.argv[1]
FETCH = "import urllib.request as u, sys\ntry:\n print(u.urlopen(sys.argv[1], timeout=20).read().decode()[:80])\nexcept Exception as e:\n print('BLOCKED:', type(e).__name__, str(e)[:120])"

async def main():
    s = Settings()
    p = provider(s, 'modal', modal_clients=ModalClients())
    print('policy passed to Modal:', p._egress())
    sb = await p.create(name=None, timeout=600)
    try:
        for url in (CANARY, 'https://api.github.com/zen'):
            proc = await sb.exec.aio('python3', '-c', FETCH, url)
            out = await proc.stdout.read.aio()
            await proc.wait.aio()
            print(url.split('/')[2], '->', out.strip())
    finally:
        await sb.terminate.aio()
        print('sandbox terminated')

asyncio.run(main())

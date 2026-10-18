"""Local patch for Moyai (ai-agentic-enterprises, 2026-10-12).

Make the Modal adapter enforce the same outbound hostname allow-list as Substrate
(SUBSTRATE_EGRESS_HOSTS), using Modal's outbound_domain_allowlist. '*' keeps Modal open.
Run from the Moyai repo root. Idempotent.
"""
p = 'app/sandboxes/modal.py'
s = open(p).read()
if '_egress(self)' in s:
    print('already patched'); raise SystemExit
old = "            experimental_options={'vm_runtime': True} if self.settings.modal_vm_runtime else {})"
new = ("            experimental_options={'vm_runtime': True} if self.settings.modal_vm_runtime else {},\n"
       "            # Local patch: same outbound hostname allow-list as Substrate; '*' keeps Modal open.\n"
       "            **self._egress())\n"
       "\n"
       "    def _egress(self):\n"
       "        hosts = [h.strip() for h in self.settings.substrate_egress_hosts.split(',') if h.strip()]\n"
       "        return {} if not hosts or '*' in hosts else {'outbound_domain_allowlist': hosts}")
assert s.count(old) == 1, 'anchor not found'
open(p, 'w').write(s.replace(old, new))
print('patched')

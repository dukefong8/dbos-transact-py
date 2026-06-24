import os

import pysnooper

_DEPTH = int(os.environ.get("SNOOP_DEPTH", "0"))


class _NoopSnoop:
    def __call__(self, func=None):
        if func is not None:
            return func
        return self

    def __enter__(self):
        return None

    def __exit__(self, *args):
        pass


if _DEPTH < 1:
    snoop = _NoopSnoop()
else:
    snoop = pysnooper.snoop(depth=_DEPTH, color=False)

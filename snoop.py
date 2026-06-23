import inspect
import os
from collections.abc import Callable
from contextlib import ContextDecorator
from functools import wraps
from typing import Any, TypeVar

F = TypeVar("F", bound=Callable[..., object])


class _NullSnoop(ContextDecorator):
    def __enter__(self) -> "_NullSnoop":
        return self

    def __exit__(self, *exc: object) -> bool:
        return False

    def __call__(self, func: F) -> F:
        return func


class _Snoop(ContextDecorator):
    def __init__(self, label: str, depth: int):
        self.label = label
        self.depth = depth
        self._tracer: ContextDecorator | None = None

    def _new_tracer(self) -> ContextDecorator:
        import pysnooper

        return pysnooper.snoop(
            prefix=f"{self.label} ",
            depth=self.depth,
            thread_info=False,
            color=False,
        )

    def __enter__(self) -> ContextDecorator:
        self._tracer = self._new_tracer()
        return self._tracer.__enter__()

    def __exit__(self, *exc: object) -> bool:
        if self._tracer is None:
            return False
        return bool(self._tracer.__exit__(*exc))

    def __call__(self, func: F) -> F:
        if inspect.iscoroutinefunction(func):

            @wraps(func)
            async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
                with self._new_tracer():
                    return await func(*args, **kwargs)

            return async_wrapper  # type: ignore[return-value]

        return self._new_tracer()(func)  # type: ignore[return-value]


def _get_snoop_depth() -> int:
    try:
        return int(os.getenv("SNOOP_DEPTH", "0"))
    except ValueError:
        return 0


def snoop(label: str, depth: int | None = None) -> ContextDecorator:
    if depth is None:
        depth = _get_snoop_depth()
    if depth <= 0:
        return _NullSnoop()

    return _Snoop(label, depth)

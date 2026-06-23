import inspect
import os
from collections.abc import Callable
from contextlib import ContextDecorator
from typing import TypeVar

F = TypeVar("F", bound=Callable[..., object])


class _NullSnoop(ContextDecorator):
    def __enter__(self) -> "_NullSnoop":
        return self

    def __exit__(self, *exc: object) -> bool:
        return False

    def __call__(self, func: F) -> F:
        return func


class _Snoop(ContextDecorator):
    def __init__(self, label: str | None, depth: int, log_file: str | None = None):
        self.label = label
        self.depth = depth
        self.log_file = log_file
        self._tracer: ContextDecorator | None = None

    def _new_tracer(self) -> ContextDecorator:
        import pysnooper

        return pysnooper.snoop(
            output=self.log_file,
            prefix=f"{self.label} " if self.label else "",
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
            # pysnooper's tracer is sync-only; async functions emit coroutine
            # suspension "return" events and the tracer drops its frame state
            # before the coroutine actually finishes. That raises KeyError on
            # __exit__ when the wrapper unwinds after an await. Leave async
            # callables untouched so they stay runnable.
            return func

        return self._new_tracer()(func)  # type: ignore[return-value]


def _get_snoop_depth() -> int:
    try:
        return int(os.getenv("SNOOP_DEPTH", "0"))
    except ValueError:
        return 0


def snoop(
    _func: F | str | None = None,
    *,
    label: str | None = None,
    depth: int | None = None,
    log_file: str | None = None,
) -> ContextDecorator | F:
    if depth is None:
        depth = _get_snoop_depth()
    if depth <= 0:
        tracer: ContextDecorator = _NullSnoop()
    else:
        if log_file is not None:
            log_dir = os.path.dirname(log_file)
            if log_dir:
                os.makedirs(log_dir, exist_ok=True)
        tracer = _Snoop(label, depth, log_file=log_file)

    if _func is None:
        return tracer
    return tracer(_func)


def snoop_test(_func: F | None = None, *, depth: int | None = None):
    def decorator(func: F) -> F:
        return snoop(
            depth=depth,
            log_file=f"logs/{func.__name__}.log",
        )(func)

    if _func is None:
        return decorator
    return decorator(_func)

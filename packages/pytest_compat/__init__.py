"""
Minimal pytest compatibility for Zyth

This module provides stub implementations of pytest decorators
to allow test files to import pytest without crashing.
"""


def fixture(*args, **kwargs):
    """Decorator stub for pytest fixtures"""
    def decorator(func):
        return func

    # Handle both @fixture and @fixture()
    if len(args) == 1 and callable(args[0]) and not kwargs:
        return args[0]
    return decorator


class mark:
    """Stub implementation of pytest.mark"""

    @staticmethod
    def parametrize(*args, **kwargs):
        """Decorator stub for pytest.mark.parametrize"""
        def decorator(func):
            return func
        return decorator

    @staticmethod
    def skip(*args, **kwargs):
        """Decorator stub for pytest.mark.skip"""
        def decorator(func):
            return func
        return decorator

    @staticmethod
    def skipif(*args, **kwargs):
        """Decorator stub for pytest.mark.skipif"""
        def decorator(func):
            return func
        return decorator


# Export commonly used functions
__all__ = ['fixture', 'mark']

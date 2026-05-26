"""Project-specific exceptions."""


class OptionalDependencyError(RuntimeError):
    """Raised when an optional runtime dependency is required but missing."""

    def __init__(self, package: str, feature: str) -> None:
        super().__init__(
            f"{feature} requires optional dependency '{package}'. "
            f"Install the matching extra from pyproject.toml."
        )

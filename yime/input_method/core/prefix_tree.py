"""Reusable prefix tree for ordered string-key lookups."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Generic, TypeVar


T = TypeVar("T")


@dataclass
class _PrefixTreeNode(Generic[T]):
    children: dict[str, "_PrefixTreeNode[T]"] = field(default_factory=dict)
    values: list[T] = field(default_factory=list)


class PrefixTree(Generic[T]):
    """Store values under string keys and retrieve them by exact key or prefix."""

    def __init__(self) -> None:
        self._root: _PrefixTreeNode[T] = _PrefixTreeNode()
        self._key_count = 0
        self._value_count = 0

    @property
    def key_count(self) -> int:
        return self._key_count

    @property
    def value_count(self) -> int:
        return self._value_count

    def insert(self, key: str, value: T) -> None:
        if not key:
            raise ValueError("PrefixTree key must not be empty")

        node = self._root
        for char in key:
            node = node.children.setdefault(char, _PrefixTreeNode())

        if not node.values:
            self._key_count += 1
        node.values.append(value)
        self._value_count += 1

    def contains(self, key: str) -> bool:
        node = self._find_node(key)
        return bool(node and node.values)

    def has_prefix(self, prefix: str) -> bool:
        return self._find_node(prefix) is not None

    def get_exact(self, key: str) -> list[T]:
        node = self._find_node(key)
        if node is None:
            return []
        return list(node.values)

    def get_with_prefix(
        self,
        prefix: str,
        limit: int = 0,
    ) -> list[tuple[str, list[T]]]:
        node = self._find_node(prefix)
        if node is None:
            return []

        results: list[tuple[str, list[T]]] = []
        self._collect(node, prefix, results, limit)
        return results

    def _find_node(self, key: str) -> _PrefixTreeNode[T] | None:
        node = self._root
        for char in key:
            child = node.children.get(char)
            if child is None:
                return None
            node = child
        return node

    def _collect(
        self,
        node: _PrefixTreeNode[T],
        key: str,
        results: list[tuple[str, list[T]]],
        limit: int,
    ) -> None:
        if limit > 0 and len(results) >= limit:
            return

        if node.values:
            results.append((key, list(node.values)))

        for char, child in node.children.items():
            self._collect(child, f"{key}{char}", results, limit)

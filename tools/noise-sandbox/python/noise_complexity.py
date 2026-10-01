"""Offline view of the compiled noise program, to EXPLAIN the engine's number.

`tests/noise_engine_report.py` already gets the authoritative metric -- the
engine's own per-program report ("Entity noise program processed 7289
expressions (3349 unique) ... estimated complexity: 33732"), in about two
seconds. This module exists to answer the questions that number cannot:

  * how much of the program is deduplication the engine MISSED (same
    mathematics written in a form the compiler cannot see);
  * how the mod's territory masks share their work;
  * what the program is made of (per-primitive tally), and what a mod adds or
    removes relative to vanilla (`--compare`).

Its own counts are NOT the engine's counts: the root set here is an
over-approximation (every prototype with an autoplace block, including planets
that are not on the merged map), so it reported 2841 Entity operations where the
engine reported 928 on the vanilla program. Use it for structure and ranking;
never as the number a claim rests on -- that is `probe_noise_cost.py` (wall
clock) and `noise_engine_report.py` (the engine).

Usage:
    PYTHONPATH=tools/noise-sandbox/python python3 noise_complexity.py \\
        --dump <write-data>/script-output/data-raw-dump.json [--settings s.json] \\
        [--eon-only] [--compare baseline.json] [--top 25] [--json out.json]
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import threading
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from typing import Any, Iterable

from eon_expression import Catalog, Literal, Name, Unary, Binary, Call, ParseError, Parser

INF = math.inf
# See Graph.budget: a runaway walk must fail, not hang.
NODE_BUDGET = 40_000_000
# Nodes the engine gives their own operation (per-tile variables, builtins).
# Everything else (constants, named references) is folded or shared.
LEAF_OPS = {"x", "y", "map_seed", "map_seed_small", "map_seed_normalized"}

# Noise builtins that are per-tile primitives, with their (expensive) weight in
# the engine's own "estimated complexity" sense. The weights only matter for
# RANKING groups against each other; the absolute numbers are ours, not the
# engine's (the engine's report is unavailable for mod surfaces).
BUILTIN_COST = {
    "basis_noise": 1.0,
    "multioctave_noise": 2.5,
    "variable_persistence_multioctave_noise": 3.0,
    "quick_multioctave_noise": 2.5,
    "voronoi_spot_noise": 1.0,
    "voronoi_facet_noise": 1.0,
    "voronoi_pyramid_noise": 1.0,
    "voronoi_cell_id": 1.0,
    "spot_noise": 4.0,
    "multisample": 2.0,
    "random_penalty": 0.5,
    "distance_from_nearest_point": 0.5,
}
# Named noise functions in the mod: their bodies are inlined at every call site,
# so the function name is worth nothing on its own.
IDENTITY_FOLD_OPS = {"if": 0.05, "clamp": 0.05, "min": 0.05, "max": 0.05,
                     "abs": 0.02, "floor": 0.02, "ceil": 0.02, "sqrt": 0.02,
                     "log2": 0.02, "sin": 0.05, "cos": 0.05, "pow": 0.05,
                     "lerp": 0.05, "var": 0.0, "noise_layer_id": 0.0}

COMMUTATIVE = {"+", "*", "==", "!=", "min", "max"}
ASSOCIATIVE = {"+", "*"}


# --------------------------------------------------------------------------
# normalisation: the same mathematics, one key
# --------------------------------------------------------------------------

def _num(value: float):
    """Canonical number: 2 and 2.0 and 4/2 are the same constant."""
    if isinstance(value, str):  # string arguments (seed1 = "my-noise")
        return f'"{value}"'
    if value == INF:
        return "inf"
    if value == -INF:
        return "-inf"
    if value != value:  # NaN
        return "nan"
    rounded = round(value, 12)
    if rounded == int(rounded) and abs(rounded) < 1e15:
        return str(int(rounded))
    return repr(rounded)


# Nodes are interned with a cached content hash. A frozen dataclass hashes its
# whole subtree on every dict/set operation, which is quadratic on expressions
# this large (measured: 200M hash calls for 40 tile roots). One integer hash
# per node, computed from the children's hashes, makes the whole walk linear.
_NODES: dict[int, "Node"] = {}
_NEXT_NODE_ID = [0]


@dataclass(frozen=True, eq=False)
class Node:
    """A normalised expression node. Identity is the dedup key."""
    op: str
    args: tuple = ()
    value: Any = None
    sortkey: tuple = field(default=(), compare=False, repr=False)
    digest: int = field(default=0, compare=False, repr=False)
    key: int = field(default=0, compare=False, repr=False)

    def __hash__(self):
        return self.digest

    def __eq__(self, other):
        return isinstance(other, Node) and self.key == other.key

    def __lt__(self, other):
        return (self.digest, self.key) < (other.digest, other.key)


def _order(node: "Node") -> tuple:
    """A CONTENT-based order for commutative operands.

    Ordering by the interned id instead would be cheaper, but ids depend on the
    order the nodes were first seen, which makes the canonical form (and with it
    the missed-deduplication totals this tool reports) differ between runs of the
    same input. A budget gate cannot be allowed to flap, so the tie-break is
    derived from the node's own content.
    """
    return (node.digest, node.op, str(node.value), len(node.args))


def intern(op: str, args: tuple = (), value: Any = None) -> "Node":
    """Build (or reuse) the node for this content. O(degree), not O(subtree)."""
    if op in ("const", "var"):
        digest = hash((op, value))
    elif op == "neg":
        digest = hash(("neg", args[0].digest))
    elif op == "unary":
        digest = hash(("unary", args[0], args[1].digest))
    elif op == "bin":
        symbol, left, right = args
        if symbol in COMMUTATIVE and _order(right) < _order(left):
            left, right = right, left
        digest = hash(("bin", symbol, left.digest, right.digest))
    elif op == "call":
        name, call_args, kwargs = args
        digest = hash(("call", name, tuple(a.digest for a in call_args),
                       tuple((k, v.digest) for k, v in kwargs)))
    else:
        raise TypeError(op)
    existing = _NODES.get(digest)
    if existing is not None and existing.sortkey == (op, args, value):
        return existing
    node = Node(op, args, value, (op, args, value), digest, _NEXT_NODE_ID[0])
    _NODES[digest] = node
    _NEXT_NODE_ID[0] += 1
    return node


def node_sort_key(node: "Node") -> tuple:
    """Content-based ordering (see _order), with the interned id only as a
    last-resort tie-break so the result is a total order."""
    return _order(node) + (node.key,)


# --------------------------------------------------------------------------
# normalisation: the same mathematics, one node
# --------------------------------------------------------------------------
# Beyond the engine's own folding (see `engine_key`) this treats as equal the
# rewrites the compiler does NOT do: re-association, distributing a constant
# factor, x/2 vs x*0.5, a - b vs a + (-b). Two nodes that differ only in one of
# those are compiled twice and paid for twice.

def norm(node):
    """Normalise a raw AST (eon_expression nodes) into interned `Node`s."""
    if isinstance(node, Literal):
        return intern("const", value=_num(node.value))
    if isinstance(node, Name):
        return intern("var", value=node.name)
    if isinstance(node, Unary):
        inner = norm(node.value)
        if node.op == "+":
            return inner
        if node.op == "-":
            if inner.op == "const":
                return intern("const", value=_num(-float(inner.value)))
            return intern("neg", (inner,))
        return intern("unary", (node.op, inner))
    if isinstance(node, Binary):
        return norm_binary(node.op, norm(node.left), norm(node.right))
    if isinstance(node, Call):
        if node.name == "var" and node.args and isinstance(node.args[0], Literal):
            return intern("var", value=str(node.args[0].value))
        args = tuple(norm(a) for a in node.args)
        kwargs = tuple(sorted((k, norm(v)) for k, v in node.kwargs.items()))
        return intern("call", (node.name, args, kwargs))
    raise TypeError(f"unknown AST node {node!r}")


def _flatten(op: str, node: Node, out: list) -> None:
    if node.op == "bin" and node.args[0] == op:
        _flatten(op, node.args[1], out)
        _flatten(op, node.args[2], out)
    else:
        out.append(node)


COMPARISONS = {"<", "<=", ">", ">=", "==", "!="}


def norm_binary(op: str, left: Node, right: Node) -> Node:
    if left.op == "const" and right.op == "const":
        folded = _fold(op, float(left.value), float(right.value))
        if folded is not None:
            return intern("const", value=_num(folded))
    if op == "+":
        terms = []
        _flatten("+", left, terms)
        _flatten("+", right, terms)
        const = 0.0
        rest = []
        for term in terms:
            if term.op == "const":
                const += float(term.value)
            elif term.op == "neg":
                rest.append(("neg", term.args[0]))
            else:
                rest.append(("pos", term))
        positives = sorted((t for sign, t in rest if sign == "pos"), key=node_sort_key)
        negatives = sorted((t for sign, t in rest if sign == "neg"), key=node_sort_key)
        if len(negatives) == 2 and negatives[0] == negatives[1]:
            return intern("const", value="0")  # a - a
        if const:
            positives.insert(0, intern("const", value=_num(const)))
        positives = [p for p in positives if not (p.op == "const" and float(p.value) == 0.0)]
        positives = _combine_repeats(positives)
        if negatives:
            return intern("bin", ("-", positives[0], _sum(negatives))) if positives \
                else intern("neg", (_sum(negatives),))
        return _sum(positives)
    if op == "*":
        # `2 * (a + b)` and `a + a + b + b` are the same mathematics. The API
        # docs recommend the distributed spelling (so the parts get shared), so
        # that is the canonical form here too.
        for constant, other in ((left, right), (right, left)):
            if constant.op == "const" and other.op == "bin" and other.args[0] == "+":
                if float(constant.value) == 0:
                    return intern("const", value="0")
                if float(constant.value) == 1:
                    return other
                terms = []
                _flatten("+", other, terms)
                return norm_binary("+", _sum([norm_binary("*", constant, t) for t in terms]),
                                   intern("const", value="0"))
        factors = []
        _flatten("*", left, factors)
        _flatten("*", right, factors)
        for factor in factors:
            if factor.op == "const" and float(factor.value) == 0.0:
                return intern("const", value="0")
        const = 1.0
        rest = []
        for factor in factors:
            if factor.op == "const":
                const *= float(factor.value)
            else:
                rest.append(factor)
        rest = sorted(set(rest), key=node_sort_key)
        if not rest:
            return intern("const", value=_num(const))
        if len(rest) == 1:
            if const == -1.0:
                return intern("neg", (rest[0],))
            if const != 1.0:
                return intern("bin", ("*", intern("const", value=_num(const)), rest[0]))
            return rest[0]
        head = rest[0]
        if const != 1.0:
            head = intern("bin", ("*", intern("const", value=_num(const)), head))
        return intern("bin", ("*", head, _product(rest[1:])))
    if op == "-":
        return norm_binary("+", left, intern("neg", (right,)))
    if op in COMPARISONS:
        # the engine folds these too (1 == 1 is a constant condition), and a
        # constant condition makes the whole if() a constant as well
        if left.op == "const" and right.op == "const":
            return intern("const", value=_num(1.0 if _compare(op, float(left.value), float(right.value)) else 0.0))
        return intern("bin", (op, left, right))
    if op == "/":
        if right.op == "const" and float(right.value) != 0:
            return norm_binary("*", left, intern("const", value=_num(1.0 / float(right.value))))
        return intern("bin", ("/", left, right))
    if op == "^":
        if right.op == "const":
            exponent = float(right.value)
            if exponent == 0:
                return intern("const", value="1")
            if exponent == 1:
                return left
            if exponent == 0.5:
                return intern("call", ("sqrt", (left,), ()))
            if exponent == 2:
                return intern("bin", ("*", left, left))
        return intern("bin", ("^", left, right))
    if op in COMMUTATIVE:
        first, second = sorted((left, right), key=node_sort_key)
        return intern("bin", (op, first, second))
    return intern("bin", (op, left, right))


def _combine_repeats(items: list) -> list:
    """a + a + b is 2a + b: the same value, and the form the compiler sees twice
    when the same multiplier is written both as `a * 2` and as `a + a`."""
    counts = Counter(node_sort_key(item) for item in items)
    out, seen = [], Counter()
    for item in items:
        key = node_sort_key(item)
        seen[key] += 1
        if seen[key] > 1:
            continue
        if counts[key] > 1:
            out.append(intern("bin", ("*", intern("const", value=str(counts[key])), item)))
        else:
            out.append(item)
    return out


def _sum(items: list) -> Node:
    result = items[0]
    for item in items[1:]:
        result = intern("bin", ("+", result, item))
    return result


def _product(items: list) -> Node:
    result = items[0]
    for item in items[1:]:
        result = intern("bin", ("*", result, item))
    return result


def _compare(op: str, a: float, b: float) -> bool:
    return {"<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b,
            "==": a == b, "!=": a != b}[op]


def _fold(op: str, a: float, b: float):
    try:
        if op == "+":
            return a + b
        if op == "-":
            return a - b
        if op == "*":
            return a * b
        if op == "/":
            return a / b if b else None
        if op == "^":
            return a ** b
    except (ZeroDivisionError, OverflowError, ValueError):
        return None
    return None


# --------------------------------------------------------------------------
# rendering (reports only -- never on the hot path)
# --------------------------------------------------------------------------

def render(node: Node) -> str:
    op = node.op
    if op == "const":
        return node.value
    if op == "var":
        return node.value
    if op == "neg":
        return f"-({render(node.args[0])})"
    if op == "unary":
        return f"{node.args[0]}({render(node.args[1])})"
    if op == "bin":
        symbol, a, b = node.args
        if symbol in ("min", "max"):
            return f"{symbol}({render(a)}, {render(b)})"
        return f"({render(a)} {symbol} {render(b)})"
    if op == "call":
        name, args, kwargs = node.args
        parts = [render(a) for a in args]
        parts += [f"{k} = {render(v)}" for k, v in kwargs]
        return f"{name}{{{', '.join(parts)}}}"
    raise TypeError(op)


def size(node: Node, cache: dict) -> int:
    """Node count of a subtree (cache is per-graph, nodes are immutable)."""
    if node in cache:
        return cache[node]
    total = 1
    for arg in children(node):
        total += size(arg, cache)
    cache[node] = total
    return total


def children(node: Node) -> Iterable[Node]:
    if node.op in ("neg", "unary"):
        yield node.args[0]
    elif node.op == "bin":
        yield node.args[1]
        yield node.args[2]
    elif node.op == "call":
        _, args, kwargs = node.args
        for a in args:
            yield a
        for _, v in kwargs:
            yield v


def cost(node: Node) -> float:
    if node.op in ("const", "var"):
        return 0.0
    if node.op == "call":
        return BUILTIN_COST.get(node.args[0], IDENTITY_FOLD_OPS.get(node.args[0], 0.1))
    if node.op == "unary":
        return 0.02
    if node.op == "neg":
        return 0.01
    return 0.05  # arithmetic node


# --------------------------------------------------------------------------
# what the ENGINE deduplicates on
# --------------------------------------------------------------------------
# The engine parses each expression, inlines named references, then applies
# constant folding and a fixed list of arithmetic identities (API docs,
# "Constant folding"). Nodes equal after that are ONE operation. Everything the
# docs do NOT list -- re-association, distributing a constant factor,
# x/2 vs x*0.5 -- stays a second operation, which is what this module reports.

def _ecanon(value: float) -> float:
    if isinstance(value, str):
        return value
    if value in (INF, -INF) or value != value:
        return value
    return round(value, 12)


_ENGINE_INDEX: dict[tuple, int] = {}
_ENGINE_RAW: list = []


def engine_id(key):
    """Integer identity for an engine key: O(degree) to build, O(1) to hash."""
    if isinstance(key, int):  # already interned
        return key
    head = key[0]
    if head in ("const", "var"):
        ident = ("leaf", head, key[1])
    elif head == "neg":
        ident = ("neg", engine_id(key[1]))
    elif head == "unary":
        ident = ("unary", key[1], engine_id(key[2]))
    elif head == "bin":
        ident = ("bin", key[1], engine_id(key[2]), engine_id(key[3]))
    elif head == "call":
        ident = ("call", key[1], tuple(engine_id(a) for a in key[2]),
                 tuple((k, engine_id(v)) for k, v in key[3]))
    else:  # the min/max shape emitted for positional min/max
        ident = ("other", engine_id(key[1]), engine_id(key[2]))
    eid = _ENGINE_INDEX.get(ident)
    if eid is None:
        eid = len(_ENGINE_RAW)
        _ENGINE_RAW.append(key)
        _ENGINE_INDEX[ident] = eid
    return eid


# The engine key of a node is its identity for the engine's own deduplication.
# It is built from children ids and interned immediately, so every id is an
# integer and every hash is O(1).

def ek_const(value):
    value = _ecanon(value)
    eid = engine_id(("const", value))
    _ENGINE_CONST[eid] = value
    return eid


def ek_var(name):
    return engine_id(("var", name))


def ek_neg(child):
    return engine_id(("neg", child))


def ek_unary(op, child):
    return engine_id(("unary", op, child))


def ek_call(name, args, kwargs):
    """Every constant argument is folded by the engine, keyword arguments
    included -- (1/50)/(1/2) is 0.04 to the compiler, so two calls that only
    differ in how they spelled a constant parameter are ONE operation."""
    kwargs = tuple((k, ek_const(const_of(v)) if const_of(v) is not None else v)
                   for k, v in kwargs)  # already-folded constants stay as they are
    return engine_id(("call", name, tuple(args), kwargs))


def ek_bin(op, left, right):
    """The engine's own binary rules: fold constants, drop identities, sort
    commutative operands. This is the deduplication the engine gets for free."""
    if op in COMMUTATIVE:
        left, right = sorted((left, right))
    a, b = const_of(left), const_of(right)
    if a is not None and b is not None:
        folded = _fold(op, a, b)
        if folded is not None:
            return ek_const(folded)
    zero, one = ek_const(0.0), ek_const(1.0)
    if op == "+":
        if right == zero:
            return left
        if left == zero:
            return right
    if op == "-":
        if right == zero:
            return left
        if left == zero:
            return ek_neg(right)
    if op in ("*", "/"):
        # commutative: the constant may be on either side, so test both
        if left == one or right == one:
            return left if right == one else right
        if op == "*" and (left == zero or right == zero):
            return zero
        minus_one = ek_const(-1.0)
        if op in ("*", "/") and (left == minus_one or right == minus_one):
            return ek_neg(right if left == minus_one else left)
    if op in COMPARISONS and a is not None and b is not None:
        return ek_const(1.0 if _compare(op, a, b) else 0.0)
    if op == "^":
        if b == 0.0:
            return one
        if b == 1.0:
            return left
        if b == 0.5:
            return ek_call("sqrt", (left,), ())
        if b == 2.0:
            return ek_bin("*", left, left)
    return engine_id(("bin", op, left, right))


_ENGINE_CONST: dict[int, float] = {}


def _remember(eid, key):
    if key[0] == "const":
        _ENGINE_CONST[eid] = key[1]
    return eid


def const_of(eid):
    """The constant value of an engine node, or None if it is not a constant."""
    return _ENGINE_CONST.get(eid)


def ek_of(node, scope):
    raise NotImplementedError  # superseded by Graph._dispatch


# --------------------------------------------------------------------------
# the graph
# --------------------------------------------------------------------------
# One traversal, bottom-up, producing BOTH keys for every node:
#
#   engine_key  what the engine's own deduplication compares (its constant
#               folding and arithmetic identities, inlined named references)
#   math node   the same mathematics under a wider normalisation, so two nodes
#               that only DIFFER in a way the compiler cannot see land on one
#               node -- that pair is a missed deduplication.

Scope = tuple  # (subst, local_expressions, local_functions)


class Graph:
    def __init__(self, catalog: Catalog, constants: dict[str, float]):
        self.catalog = catalog
        self.constants = constants
        self.roots: list[tuple[str, Any]] = []
        self.engine_nodes: set = set()
        self.engine_cost: dict[Any, float] = {}
        self.math_nodes: set = set()
        self.math_keys: dict[Node, list] = defaultdict(list)
        self.total_nodes = 0
        self.subtree_cost: dict[Node, float] = {}
        self.subtree_size: dict[Node, int] = {}
        # Hard budget: this tool must fail loudly instead of hanging (a naive
        # normalisation once ran for an hour before the quadratic path above was
        # found). NODE_BUDGET is ~20x the largest measured program.
        self.budget = NODE_BUDGET
        # Analysis of a named reference / named-function call is memoised on the
        # ENGINE key of its arguments. Without this the walk re-inlines the same
        # mask chain once per call site: the mod's helpers are each instantiated
        # by ~150 decoratives, which is ~150x the work for an answer that is by
        # construction identical.
        self.origins: dict[Node, set] = {}
        self.engine_uses: Counter = Counter()
        self.engine_origins: dict[int, set] = defaultdict(set)
        # Nodes reached while inlining one of the mod's own named expressions.
        # The report needs the split: the program contains vanilla's expressions
        # too, and "what does the MOD cost" is a different question from "what
        # does the program cost".
        self.eon_depth = 0
        self.eon_nodes: set = set()
        self.eon_math: set = set()
        self.memo: dict[tuple, tuple] = {}
        self.memo_hits: Counter = Counter()

    # -- public ---------------------------------------------------------
    def add(self, origin: str, source: str):
        try:
            ast = Parser(str(source)).parse()
        except ParseError as error:
            raise SystemExit(f"{origin}: cannot parse {source!r}: {error}")
        self.roots.append((origin, ast))
        ekey, _ = self._analyze(ast, (dict(), {}, {}), origin)
        # Two roots that compile to the SAME graph (the engine deduplicates them)
        # contribute nothing new to the node sets; re-walking them only costs
        # time. Occurrence counts are read off the root list, not off the walk.
        self.roots[-1] = (origin, ast, ekey)

    # -- traversal ------------------------------------------------------
    def _analyze(self, node, scope: Scope, origin: str):
        """Return (engine_id, math_node) for `node`, recording both."""
        self.total_nodes += 1
        self.budget -= 1
        if self.budget < 0:
            raise SystemExit(
                f"noise_complexity: node budget ({NODE_BUDGET}) exhausted -- the walk "
                f"is not linear; this is a bug in the analyser, not a big mod")
        eid, mkey = self._dispatch(node, scope, origin)
        self.engine_nodes.add(eid)
        if self.eon_depth:
            self.eon_nodes.add(eid)
            self.eon_math.add(mkey)
        self.engine_uses[eid] += 1
        self.engine_origins[eid].add(origin)
        self.engine_cost.setdefault(eid, cost(mkey))
        self.math_nodes.add(mkey)
        self.math_keys[mkey].append(eid)
        self.origins.setdefault(mkey, set()).add(origin)
        if mkey not in self.subtree_size:
            self.subtree_size[mkey] = size(mkey, self.subtree_size)
            self.subtree_cost[mkey] = _tree_cost(mkey, self.subtree_cost)
        return eid, mkey

    def _dispatch(self, node, scope: Scope, origin: str):
        subst, local_expressions, local_functions = scope
        if isinstance(node, Literal):
            return ek_const(node.value), intern("const", value=_num(node.value))
        if isinstance(node, Name):
            return self._reference(node.name, scope, origin)
        if isinstance(node, Unary):
            ekey, mkey = self._analyze(node.value, scope, origin)
            if node.op == "+":
                return ekey, mkey
            if node.op == "-":
                value = const_of(ekey)
                if value is not None:
                    return ek_const(-value), intern("const", value=_num(-float(mkey.value)))
                return ek_neg(ekey), intern("neg", (mkey,))
            return ek_unary(node.op, ekey), intern("unary", (node.op, mkey))
        if isinstance(node, Binary):
            left = self._analyze(node.left, scope, origin)
            right = self._analyze(node.right, scope, origin)
            return (ek_bin(node.op, left[0], right[0]),
                    norm_binary(node.op, left[1], right[1]))
        if isinstance(node, Call):
            return self._call(node, scope, origin)
        raise TypeError(f"unknown AST node {node!r}")

    def _reference(self, name: str, scope: Scope, origin: str):
        subst, local_expressions, local_functions = scope
        if name in ("x", "y"):
            return ek_var(name), intern("var", value=name)
        if name in subst:
            return subst[name]
        if name in self.constants:
            value = self.constants[name]
            return ek_const(value), intern("const", value=_num(value))
        if name in local_expressions:
            key = ("local-expression", name, id(local_expressions[name][1]))
            if key not in self.memo:
                body, inner_scope = local_expressions[name]
                self.memo[key] = self._analyze(body, inner_scope, origin)
            self.memo_hits[key] += 1
            return self.memo[key]
        if name in self.catalog.expressions or name in self.catalog.functions:
            # A named expression / function without arguments is a fixed graph:
            # analyse it once per program.
            key = ("named", name)
            if key not in self.memo:
                self.eon_depth += 1 if name.startswith("eon_") else 0
                try:
                    self.memo[key] = self._analyze(self.catalog.parsed[name], (dict(), {}, {}), origin)
                finally:
                    if name.startswith("eon_"):
                        self.eon_depth -= 1
            self.memo_hits[key] += 1
            return self.memo[key]
        return ek_var(name), intern("var", value=name)

    def _call(self, node: Call, scope: Scope, origin: str):
        subst, local_expressions, local_functions = scope
        if node.name == "var" and node.args and isinstance(node.args[0], Literal):
            return self._reference(str(node.args[0].value), scope, origin)
        named = node.name in local_functions or node.name in self.catalog.functions
        if named:
            # Memoise on the engine keys of the arguments: two calls that give
            # the same arguments compile to the same graph.
            probe = (self._analyze(a, scope, origin) for a in node.args)
            args = tuple(a[0] for a in probe)
            kwargs = tuple(sorted((k, self._analyze(v, scope, origin)[0])
                                  for k, v in node.kwargs.items()))
            key = ("call", node.name, args, kwargs)
            if key in self.memo:
                self.memo_hits[key] += 1
                return self.memo[key]
            self.eon_depth += 1 if node.name.startswith("eon_") else 0
            try:
                if node.name in local_functions:
                    body, inner_scope, params = local_functions[node.name]
                    result = self._analyze(body, self._bind(node, body, params, scope, origin), origin)
                else:
                    record = self.catalog.functions[node.name]
                    result = self._analyze(
                        self.catalog.parsed[node.name],
                        self._bind(node, self.catalog.parsed[node.name],
                                   record.get("parameters", []), scope, origin),
                        origin)
            finally:
                if node.name.startswith("eon_"):
                    self.eon_depth -= 1
            self.memo[key] = result
            return result
        args = tuple(self._analyze(a, scope, origin) for a in node.args)
        kwargs = tuple(sorted((k, self._analyze(v, scope, origin)) for k, v in node.kwargs.items()))
        mkey = intern("call", (node.name, tuple(a[1] for a in args),
                               tuple((k, v[1]) for k, v in kwargs)))
        return ek_call(node.name, [a[0] for a in args], [(k, v[0]) for k, v in kwargs]), mkey

    def _bind(self, node: Call, body, params, scope: Scope, origin: str):
        """A named function call: bind parameters, then resolve its locals."""
        outer_subst, outer_ex, outer_fn = scope
        inner_subst = dict(outer_subst)
        for index, param in enumerate(params):
            if param in node.kwargs:
                inner_subst[param] = self._analyze(node.kwargs[param], scope, origin)
            elif index < len(node.args):
                inner_subst[param] = self._analyze(node.args[index], scope, origin)
        inner_scope = (inner_subst, dict(outer_ex), dict(outer_fn))

        # local_expressions / local_functions of the CALLED function are in its
        # own scope, and a local function's body sees them too.
        record = None
        if node.name in self.catalog.functions:
            record = self.catalog.functions[node.name]
        inner_ex = dict(inner_scope[1])
        for local_name in (record or {}).get("local_expressions", {}):
            inner_ex[local_name] = (self.catalog.parsed[(node.name, "local_expression", local_name)],
                                    inner_scope)
        inner_fn = dict(inner_scope[2])
        for local_name, definition in (record or {}).get("local_functions", {}).items():
            source = definition if isinstance(definition, dict) else {"expression": definition}
            inner_fn[local_name] = (self.catalog.parsed[(node.name, "local_function", local_name)],
                                    inner_scope, source.get("parameters", []))
        return (inner_subst, inner_ex, inner_fn)


def _tree_cost(node: Node, cache: dict) -> float:
    if node in cache:
        return cache[node]
    total = cost(node)
    for child in children(node):
        total += _tree_cost(child, cache)
    cache[node] = total
    return total


# --------------------------------------------------------------------------
# roots: which expressions a surface compiles
# --------------------------------------------------------------------------
# The engine splits the compiled graph into four programs (its own report:
# Cliff / Entity / Tile / Territory). Prototypes carry the autoplace
# expressions (resources, decoratives, trees, tiles); the surface carries the
# cliff and territory expressions. Decorative probability expressions are
# compiled into the Entity program -- they are autoplaced the same way.

AUTOPLACE_PROTOTYPE_TYPES = (
    "resource", "fish", "tree", "plant", "simple-entity", "turret", "unit-spawner",
    "lightning-attractor", "cliff", "optimized-decorative",
)

CLIFF_FIELDS = ("name", "control", "cliff_elevation_expression", "cliffiness_expression",
                "richness_expression", "cliff_elevation_0", "cliff_elevation_interval",
                "cliff_smoothing")
TERRITORY_FIELDS = ("territory_index_expression", "territory_variation_expression")


def surface_settings(data: dict, planet: str, settings: dict | None) -> dict:
    settings = settings or {}
    merged = dict(data["planet"][planet].get("map_gen_settings", {}))
    for key, value in settings.items():
        if key.startswith("_comment") or key == "seed":
            continue
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            deep = dict(merged[key])
            deep.update(value)
            merged[key] = deep
        else:
            merged[key] = value
    return merged


def surface_constants(settings: dict, controls: dict, seed: int) -> dict[str, float]:
    constants = {
        "map_width": float(settings.get("width", 0)),
        "map_height": float(settings.get("height", 0)),
        "map_seed": float(seed & 0xffffffff),
        "map_seed_small": float(seed & 0xffff),
        "map_seed_normalized": seed / 4294967296.0,
        "starting_area_radius": float(settings.get("starting_area", 0)) * 64,
        "peaceful_mode": float(bool(settings.get("peaceful_mode"))),
        "no_enemies_mode": float(bool(settings.get("no_enemies_mode"))),
    }
    cliff = settings.get("cliff_settings", {})
    for field in ("cliff_elevation_0", "cliff_elevation_interval", "cliff_smoothing"):
        if field in cliff:
            constants[field] = float(cliff[field])
    for name, control in controls.items():
        for key in ("frequency", "size", "richness"):
            constants[f"control:{name}:{key}"] = float(control.get(key, 1))
    return constants


def build_graphs(data: dict, planet: str = "nauvis", settings: dict | None = None,
                 seed: int = 12345) -> dict[str, Graph]:
    """One Graph per noise program: the engine deduplicates WITHIN a program,
    so a subtree shared by the cliff and tile programs is compiled twice."""
    merged = surface_settings(data, planet, settings)
    controls = merged.get("autoplace_controls", {})
    catalog = Catalog(data)
    constants = surface_constants(merged, controls, seed)
    roots: dict[str, list] = defaultdict(list)

    def add(program, origin, source):
        if isinstance(source, str) and source.strip():
            roots[program].append((origin, source))

    # -- entity program (resources, decoratives, trees, everything autoplaced)
    for proto_type in AUTOPLACE_PROTOTYPE_TYPES:
        for name, proto in sorted(data.get(proto_type, {}).items()):
            autoplace = proto.get("autoplace") or {}
            for field in ("probability_expression", "richness_expression"):
                add("Entity", f"{proto_type}:{name}:{field}", autoplace.get(field))
    for name, setting in sorted(_surface_autoplace(merged).get("entity", {}).items()):
        for field in ("probability_expression", "richness_expression"):
            add("Entity", f"entity:{name}:{field}", setting.get(field))

    # -- tile program
    for name, proto in sorted(data.get("tile", {}).items()):
        autoplace = proto.get("autoplace") or {}
        for field in ("probability_expression", "richness_expression"):
            add("Tile", f"tile:{name}:{field}", autoplace.get(field))
    for name, setting in sorted(_surface_autoplace(merged).get("tile", {}).items()):
        for field in ("probability_expression", "richness_expression"):
            add("Tile", f"tile-setting:{name}:{field}", setting.get(field))

    # -- cliff program
    for field in CLIFF_FIELDS:
        add("Cliff", f"cliff_settings:{field}", merged.get("cliff_settings", {}).get(field))

    # -- territory program
    for field in TERRITORY_FIELDS:
        add("Territory", f"territory_settings:{field}", merged.get("territory_settings", {}).get(field))

    graphs = {}
    for program, entries in roots.items():
        graph = Graph(catalog, constants)
        for origin, source in entries:
            graph.add(origin, source)
        graphs[program] = graph
    return graphs


def _surface_autoplace(settings: dict) -> dict:
    out = {}
    for group, table in (settings.get("autoplace_settings") or {}).items():
        if not isinstance(table, dict):
            continue
        entries = table.get("settings") or table
        collected = {}
        for name, setting in entries.items():
            if not isinstance(setting, dict):
                continue
            merged_setting = dict(setting)
            for holder in ("entity", "decorative"):
                inner = setting.get(holder)
                if isinstance(inner, dict):
                    for field in ("probability_expression", "richness_expression"):
                        if field in inner:
                            merged_setting[field] = inner[field]
            collected[name] = merged_setting
        out[group] = collected
    return out


# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------

def program_report(graph: Graph, top: int = 20, eon_only: bool = False) -> dict:
    """Two views of one program:

    1. what it actually costs -- the engine's own nodes (deduplication already
       applied), heaviest first, with the prototypes that pull them in;
    2. MISSED deduplication -- subtrees that are the same mathematics in more
       than one surface form, so the engine keeps one copy per form. The price
       of a group is the cost of the copies that a single canonical form would
       remove (all but the most expensive one), which is the only defensible
       estimate: after the rewrite exactly one form survives and we do not know
       which.
    """
    heavy = []
    texts = set()
    cost_by_text: dict[str, float] = defaultdict(float)
    for eid, weight in graph.engine_cost.items():
        text = _engine_text(eid, 400, [400])
        texts.add(text)
        cost_by_text[text] += weight
        if weight <= 0:
            continue
        heavy.append({
            "cost": round(weight, 3),
            "copies": graph.engine_uses.get(eid, 0),
            "text": _engine_text(eid, 400),
            "eon": eid in graph.eon_nodes,
            "origins": sorted(graph.engine_origins.get(eid, ()))[:4],
        })
    heavy.sort(key=lambda entry: -entry["cost"])

    missed = []
    for math_node, eids in graph.math_keys.items():
        if eon_only and math_node not in graph.eon_math:
            continue
        distinct = set(eids)
        if len(distinct) < 2:
            continue
        costs = sorted((graph.engine_cost.get(eid, 0.0) for eid in distinct), reverse=True)
        duplicate_cost = sum(costs[:-1])  # every copy but the heaviest one
        if duplicate_cost <= 0:
            continue
        missed.append({
            "duplicate_cost": round(duplicate_cost, 3),
            "forms": len(distinct),
            "uses": len(eids),
            "math": render(math_node)[:400],
            "forms_text": sorted({_engine_text(eid, 90) for eid in distinct})[:4],
            "origins": sorted(graph.origins.get(math_node, ()))[:5],
        })
    missed.sort(key=lambda entry: -entry["duplicate_cost"])
    eon_cost = round(sum(graph.engine_cost[eid] for eid in graph.eon_nodes), 1)
    masks = mask_sharing(graph)
    # Per-primitive tally of the UNIQUE operations: the expensive primitives are
    # the ones worth arguing about, and this is the list to attack.
    primitives: dict[str, dict] = defaultdict(lambda: {"ops": 0, "eon_ops": 0, "cost": 0.0})
    for eid, weight in graph.engine_cost.items():
        name = _engine_primitive(eid)
        entry = primitives[name]
        entry["ops"] += 1
        entry["cost"] += weight
        if eid in graph.eon_nodes:
            entry["eon_ops"] += 1
    return {
        "roots": len(graph.roots),
        "eon_unique_ops": len(graph.eon_nodes),
        "eon_cost": eon_cost,
        "nodes_visited": graph.total_nodes,
        "engine_unique_nodes": len(graph.engine_nodes),
        "math_unique_nodes": len(graph.math_nodes),
        "estimated_cost": round(sum(graph.engine_cost.values()), 1),
        "missed_dedup_total": round(sum(entry["duplicate_cost"] for entry in missed), 1),
        "masks": masks,
        "primitives": {name: {"ops": entry["ops"], "eon_ops": entry["eon_ops"],
                              "cost": round(entry["cost"], 1)}
                       for name, entry in sorted(primitives.items(),
                                                 key=lambda kv: -kv[1]["cost"])},
        "heaviest": heavy[:top],
        "texts": sorted(texts),
        "cost_by_text": dict(cost_by_text),
        "missed_dedup": missed[:top],
    }


def mask_sharing(graph: Graph) -> dict:
    """How the mod's territory masks share work.

    A mask is `if(condition, -inf, expression)`. The CONDITION is the expensive
    half (comparisons over a noise field) and the engine already shares it
    between every decorated prototype, so what is left per prototype is one
    `if` operation. This measures both halves, because the obvious "rewrite the
    mask chain as one shared 0/1 signal and multiply" idea only pays if the
    conditions are duplicated -- measured, they are not.
    """
    raw = _ENGINE_RAW

    def is_negative(eid):
        key = raw[eid]
        return key[0] == "const" and key[1] == -INF

    conditions, if_nodes = [], []
    for eid in graph.engine_nodes:
        key = raw[eid]
        if key[0] != "call" or key[1] != "if" or len(key[2]) != 3:
            continue
        condition, true_branch, false_branch = key[2]
        if is_negative(true_branch) or is_negative(false_branch):
            conditions.append(condition)
            if_nodes.append(eid)

    def nodes_of(eids):
        seen = set()
        stack = list(eids)
        while stack:
            eid = stack.pop()
            if eid in seen:
                continue
            seen.add(eid)
            key = raw[eid]
            if key[0] == "bin":
                stack += [key[2], key[3]]
            elif key[0] == "call":
                stack += list(key[2]) + [v for _, v in key[3]]
            elif key[0] in ("neg", "unary"):
                stack.append(key[1])
        return seen

    shared = nodes_of(set(conditions))
    return {
        "mask_ifs": len(if_nodes),
        "distinct_conditions": len(set(conditions)),
        "condition_nodes": len(shared),
        "per_prototype_cost": round(len(if_nodes) * cost_of_if(), 2),
        "note": "conditions are already shared; only the if() per prototype is per-use",
    }


def cost_of_if() -> float:
    return IDENTITY_FOLD_OPS["if"]


def _engine_primitive(eid: int) -> str:
    """Which builtin a node is (its own name, or 'node'/'const')."""
    key = _ENGINE_RAW[eid]
    if key[0] == "call":
        return key[1]
    if key[0] == "const":
        return "const"
    return key[0]


def _engine_text(eid: int, limit: int, budget: list = None) -> str:
    """Render an engine node back to a readable expression.

    Bounded on purpose: a fully inlined root can be two million nodes, and
    rendering one for every group in the report is what turns a 0.5 s analysis
    into an apparently hung one.
    """
    budget = budget if budget is not None else [400]
    budget[0] -= 1
    if budget[0] <= 0:
        return "<large subtree>"
    key = _ENGINE_RAW[eid]
    head = key[0]
    if head == "const":
        return _num(key[1])
    if head == "var":
        return key[1]
    if head == "neg":
        return f"-({_engine_text(key[1], limit, budget)})"
    if head == "unary":
        return f"{key[1]}({_engine_text(key[2], limit, budget)})"
    if head == "bin":
        symbol = key[1]
        left = _engine_text(key[2], limit, budget)
        right = _engine_text(key[3], limit, budget)
        if len(left) > limit or len(right) > limit:
            return f"(<{symbol} of {len(left)}+{len(right)} chars>)"
        return f"({left} {symbol} {right})"
    if head == "call":
        name = key[1]
        parts = [_engine_text(a, limit, budget) for a in key[2]]
        parts += [f"{k} = {_engine_text(v, limit, budget)}" for k, v in key[3]]
        text = f"{name}{{{', '.join(parts)}}}"
        return text if len(text) <= limit * 2 else f"{name}{{...}}"
    return f"<{head}>"


def build_report(graphs: dict[str, Graph], top: int = 20, eon_only: bool = False) -> dict:
    return {program: program_report(graph, top, eon_only) for program, graph in sorted(graphs.items())}


def diff_reports(before: dict, after: dict, top: int = 15) -> dict:
    """What the mod ADDS to each program, measured as a set difference of the
    compiled operations (not estimated from the mod's own expressions): an
    operation counts as added when the vanilla program does not contain it.

    Node identities are per-process, so the comparison is on rendered text with
    a node budget -- good enough to name operations, which is what the report
    is for. Anything bigger than the budget is reported as a shared "<large
    subtree>" bucket so the totals stay comparable.
    """
    out = {}
    for program, stats in after.items():
        base = before.get(program)
        if not base:
            continue
        base_texts = set(base["texts"])
        new_texts = set(stats["texts"])
        origins = {e["text"]: e.get("origins", []) for e in stats["heaviest"]}
        added = sorted(((round(cost, 3), text) for text, cost in stats["cost_by_text"].items()
                        if text not in base_texts), reverse=True)[:top]
        removed = sorted(((round(cost, 3), text) for text, cost in base["cost_by_text"].items()
                          if text not in new_texts), reverse=True)[:top]
        out[program] = {
            "ops_before": base["engine_unique_nodes"],
            "ops_after": stats["engine_unique_nodes"],
            "cost_before": base["estimated_cost"],
            "cost_after": stats["estimated_cost"],
            "cost_added": round(sum(a[0] for a in added), 1),
            "cost_removed": round(sum(r[0] for r in removed), 1),
            "added": [{"cost": a[0], "text": a[1], "origins": origins.get(a[1], [])} for a in added],
            "removed": [{"cost": r[0], "text": r[1]} for r in removed],
        }
    return out


def print_report(report: dict, top: int = 20, eon_heaviest: bool = False):
    for program, stats in report.items():
        print(f"\n{program} noise program: {stats['roots']} roots, {stats['nodes_visited']} nodes,"
              f" {stats['engine_unique_nodes']} unique ops (dedup"
              f" {stats['engine_unique_nodes'] / max(1, stats['nodes_visited']):.2f}),"
              f" estimated cost {stats['estimated_cost']}")
        if stats["primitives"]:
            top_prims = sorted(stats["primitives"].items(), key=lambda kv: -kv[1]["cost"])[:8]
            print("  primitives (unique ops / of those the mod's / cost): " + ", ".join(
                f"{name} {entry['ops']}/{entry['eon_ops']}/{entry['cost']}"
                for name, entry in top_prims))
        print(f"  of which the mod's own expressions: {stats['eon_unique_ops']} ops,"
              f" cost {stats['eon_cost']}"
              f" ({100 * stats['eon_cost'] / max(1e-9, stats['estimated_cost']):.0f}%)")
        print("  heaviest operations (what the program actually pays for)"
              + (", mod expressions only" if eon_heaviest else "") + ":")
        for entry in [e for e in stats["heaviest"] if e["eon"]][:top] if eon_heaviest \
                else stats["heaviest"][:top]:
            print(f"   {entry['cost']:7.2f} x{entry['copies']:<5} {entry['text']}")
            if entry["origins"]:
                print(f"            from {', '.join(entry['origins'])}")
        if stats["masks"]["mask_ifs"]:
            print(f"  territory masks: {stats['masks']['mask_ifs']} if()s over"
                  f" {stats['masks']['distinct_conditions']} shared conditions"
                  f" ({stats['masks']['condition_nodes']} nodes, all shared)")
        print(f"  missed dedup: {stats['missed_dedup_total']} of {stats['estimated_cost']}"
              f" ({100 * stats['missed_dedup_total'] / max(1e-9, stats['estimated_cost']):.0f}%),"
              f" top {min(top, len(stats['missed_dedup']))} groups:")
        for entry in stats["missed_dedup"][:top]:
            print(f"   {entry['duplicate_cost']:8.2f}  forms={entry['forms']:<3}"
                  f" uses={entry['uses']:<4} {entry['math'][:140]}")
            for form in entry["forms_text"][:3]:
                print(f"              form: {form}")
            if entry["origins"]:
                print(f"              from {', '.join(entry['origins'])}")


def _jsonable(value):
    """Sets become sorted lists and the working copies are dropped, so the file
    is a report and not a memory dump."""
    if isinstance(value, dict):
        return {k: _jsonable(v) for k, v in value.items()}
    if isinstance(value, (set, frozenset)):
        return sorted(_jsonable(v) for v in value)
    if isinstance(value, (list, tuple)):
        return [_jsonable(v) for v in value]
    return value


def print_diff(diff: dict, top: int = 15):
    for program, stats in diff.items():
        print(f"\n{program} noise program: {stats['ops_before']} -> {stats['ops_after']} ops,"
              f" cost {stats['cost_before']} -> {stats['cost_after']}")
        print(f"  added by the mod (of the heaviest {top}): {stats['cost_added']},"
              f" removed: {stats['cost_removed']}")
        for entry in stats["added"][:top]:
            print(f"   + {entry['cost']:7.2f} {entry['text'][:150]}")
            if entry["origins"]:
                print(f"          from {', '.join(entry['origins'])}")
        for entry in stats["removed"][:top]:
            print(f"   - {entry['cost']:7.2f} {entry['text'][:150]}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dump", required=True, help="data-raw-dump.json from --dump-data")
    parser.add_argument("--planet", default="nauvis")
    parser.add_argument("--settings", help="map-gen settings JSON to overlay")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--top", type=int, default=20)
    parser.add_argument("--eon-only", action="store_true",
                        help="only missed dedup inside the mod's own named expressions")
    parser.add_argument("--compare", help="a baseline report JSON (from --json) to diff against")
    parser.add_argument("--json", help="write the full report here")
    args = parser.parse_args()

    with open(args.dump, encoding="utf-8") as stream:
        data = json.load(stream)
    settings = None
    if args.settings:
        with open(args.settings, encoding="utf-8") as stream:
            settings = json.load(stream)
    graphs = build_graphs(data, args.planet, settings, args.seed)
    report = build_report(graphs, args.top, args.eon_only)
    print_report(report, args.top, args.eon_only)
    if args.compare:
        with open(args.compare, encoding="utf-8") as stream:
            baseline = json.load(stream)
        print_diff(diff_reports(baseline, report, args.top), args.top)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as stream:
            json.dump(_jsonable(report), stream, indent=2)
        print(f"\nwrote {args.json}")


def _run():
    # Node digests hash strings (operator symbols, parameter names), and Python
    # randomizes string hashes per process, which leaks into the canonical
    # ordering and made the missed-deduplication totals differ between runs of
    # the same input -- unacceptable for a budget gate. Pin the seed and re-exec
    # once; every number this tool prints is then reproducible.
    if os.environ.get("PYTHONHASHSEED") != "0":
        os.environ["PYTHONHASHSEED"] = "0"
        os.execv(sys.executable, [sys.executable] + sys.argv)
    # The mod's expressions nest hundreds of calls deep, and both the parser
    # and the graph walk recurse over them, so the default limits are not
    # enough. Run in a thread with a large stack rather than trusting the
    # process stack.
    sys.setrecursionlimit(200000)
    threading.stack_size(512 * 1024 * 1024)
    thread = threading.Thread(target=main)
    thread.start()
    thread.join()


if __name__ == "__main__":
    _run()

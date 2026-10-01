"""Factorio noise-expression parser/evaluator used by the active Python path."""
from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from eon_noise_oracle import RustNoiseOracle


class ParseError(ValueError):
    pass


@dataclass(frozen=True)
class Literal:
    value: Any


@dataclass(frozen=True)
class Name:
    name: str


@dataclass(frozen=True)
class Unary:
    op: str
    value: Any


@dataclass(frozen=True)
class Binary:
    op: str
    left: Any
    right: Any


@dataclass(frozen=True)
class Call:
    name: str
    args: tuple[Any, ...]
    kwargs: dict[str, Any]


TOKEN_RE = re.compile(
    r"\s*(?:(?P<string>\"[^\"]*\"|'[^']*')|(?P<number>0x[0-9a-fA-F]+|(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)|(?P<ident>[A-Za-z_][A-Za-z0-9_:]*)|(?P<op>==|!=|<=|>=|[-+*/%^<>&|~(),{}=]))"
)


def tokenize(source: str) -> list[tuple[str, str]]:
    tokens = []
    pos = 0
    while pos < len(source):
        match = TOKEN_RE.match(source, pos)
        if not match:
            if source[pos:].strip() == "":
                break
            raise ParseError(f"unexpected input at {pos}: {source[pos:pos+20]!r}")
        pos = match.end()
        kind = match.lastgroup
        value = match.group(kind)
        if kind == "number":
            value = str(int(value, 16)) if value.lower().startswith("0x") else value
        tokens.append((kind, value))
    tokens.append(("eof", ""))
    return tokens


class Parser:
    PRECEDENCE = {"==": 1, "!=": 1, "<": 1, "<=": 1, ">": 1, ">=": 1,
                  "+": 2, "-": 2, "&": 3, "|": 3, "~": 3,
                  "*": 4, "/": 4, "%": 4, "^": 5}

    def __init__(self, source: str):
        self.tokens = tokenize(str(source))
        self.index = 0

    def parse(self):
        node = self.expression()
        if self.current()[0] != "eof":
            raise ParseError(f"unexpected token {self.current()}")
        return node

    def current(self):
        return self.tokens[self.index]

    def take(self):
        value = self.current()
        self.index += 1
        return value

    def accept(self, kind: str, value: str | None = None):
        if self.current()[0] == kind and (value is None or self.current()[1] == value):
            return self.take()
        return None

    def expect(self, kind: str, value: str | None = None):
        token = self.accept(kind, value)
        if token is None:
            raise ParseError(f"expected {value or kind}, got {self.current()}")
        return token

    def expression(self, minimum: int = 0):
        left = self.unary()
        while self.current()[0] == "op" and self.PRECEDENCE.get(self.current()[1], -1) >= minimum:
            op = self.take()[1]
            right = self.expression(self.PRECEDENCE[op] if op == "^" else self.PRECEDENCE[op] + 1)
            left = Binary(op, left, right)
        return left

    def unary(self):
        if self.current() == ("op", "-") and self.tokens[self.index + 1] == ("ident", "inf"):
            self.take(); self.take()
            return Literal(-math.inf)
        if self.current()[0] == "op" and self.current()[1] in "+-~":
            op = self.take()[1]
            return Unary(op, self.unary())
        return self.primary()

    def primary(self):
        kind, value = self.current()
        if kind == "number":
            self.take()
            return Literal(float(value))
        if kind == "string":
            self.take()
            return Literal(value[1:-1])
        if kind == "ident":
            return self.identifier()
        if (kind, value) == ("op", "("):
            self.take(); node = self.expression(); self.expect("op", ")"); return node
        raise ParseError(f"expected value, got {self.current()}")

    def identifier(self):
        name = self.take()[1]
        if self.accept("op", "("):
            args = []
            if not self.accept("op", ")"):
                while True:
                    args.append(self.expression())
                    if not self.accept("op", ","):
                        break
                self.expect("op", ")")
            return Call(name, tuple(args), {})
        if self.accept("op", "{"):
            kwargs = {}
            if not self.accept("op", "}"):
                while True:
                    key = self.take()[1]
                    self.expect("op", "=")
                    kwargs[key] = self.expression()
                    if not self.accept("op", ","):
                        break
                self.expect("op", "}")
            return Call(name, (), kwargs)
        return Name(name)


class Catalog:
    def __init__(self, data: dict[str, Any]):
        self.version = data.get("factorio_version")
        self.expressions = data.get("noise-expression", {})
        self.functions = data.get("noise-function", {})
        self.parsed: dict[Any, Any] = {}
        for name, record in {**self.expressions, **self.functions}.items():
            self.parsed[name] = Parser(record["expression"]).parse()
            for local, source in record.get("local_expressions", {}).items():
                self.parsed[(name, "local_expression", local)] = Parser(source).parse()
            for local, definition in record.get("local_functions", {}).items():
                source = definition if isinstance(definition, dict) else {"expression": definition}
                self.parsed[(name, "local_function", local)] = Parser(source["expression"]).parse()

    @classmethod
    def load(cls, path: str | Path):
        with open(path, encoding="utf-8") as stream:
            return cls(json.load(stream))


class Settings:
    def __init__(self, data: dict[str, Any]):
        self.data = data

    @classmethod
    def load(cls, path: str | Path):
        with open(path, encoding="utf-8") as stream:
            return cls(json.load(stream))

    def get(self, name: str):
        parts = name.split(":")
        controls = self.data.get("autoplace_controls", {})
        if len(parts) == 3 and parts[0] == "control":
            return controls.get(parts[1], {}).get(parts[2], 1)
        return self.data.get(name)


BUILTINS = {"abs", "ceil", "clamp", "cos", "floor", "if", "lerp", "log2", "max", "min", "pow", "sin", "sqrt", "var"}


class Evaluator:
    def __init__(self, catalog: Catalog, settings: Settings, seed: int, oracle: RustNoiseOracle):
        self.catalog = catalog
        self.settings = settings
        self.seed = int(seed)
        self.oracle = oracle
        self.cache: dict[tuple[Any, ...], float] = {}

    def evaluate(self, name: str, x: float, y: float):
        key = (name, x, y)
        if key not in self.cache:
            env = {
                "x": x, "y": y, "map_seed": self.seed,
                "map_seed_small": self.seed & 0xffff,
                "map_seed_normalized": self.seed / 4_294_967_296.0,
                "starting_positions": [[0.0, 0.0]],
                "pi": math.pi, "e": math.e, "inf": math.inf,
            }
            record = self.catalog.expressions[name]
            for local_name in record.get("local_expressions", {}):
                env[f"local:{local_name}"] = True
            env["owner"] = name
            env["local_functions"] = record.get("local_functions", {})
            self.cache[key] = self.eval_node(self.catalog.parsed[name], env)
        return self.cache[key]

    def evaluate_ast(self, ast, x: float, y: float):
        env = {
            "x": x, "y": y, "map_seed": self.seed,
            "map_seed_small": self.seed & 0xffff,
            "map_seed_normalized": self.seed / 4_294_967_296.0,
            "starting_positions": [[0.0, 0.0]],
            "pi": math.pi, "e": math.e, "inf": math.inf,
        }
        return self.eval_node(ast, env)

    def eval_node(self, node, env):
        if isinstance(node, Literal): return node.value
        if isinstance(node, Name): return self.name(node.name, env)
        if isinstance(node, Unary):
            value = self.eval_node(node.value, env)
            return {"+": lambda: +value, "-": lambda: -value, "~": lambda: ~int(value)}[node.op]()
        if isinstance(node, Binary):
            return self.binary(node, env)
        if isinstance(node, Call): return self.call(node, env)
        raise TypeError(f"unknown AST node {node!r}")

    def name(self, name, env):
        if name in env: return env[name]
        if name.startswith("local:"):
            return self.eval_local(env, name.split(":", 1)[1])
        if env.get(f"local:{name}"):
            return self.eval_local(env, name)
        if name == "map_seed": return self.seed
        if name == "x" or name == "y": raise KeyError(name)
        if name.startswith("control:"): return self.settings.get(name)
        if name in self.catalog.expressions: return self.evaluate(name, env["x"], env["y"])
        raise KeyError(f"unknown reference {name}")

    def binary(self, node, env):
        left, right = self.eval_node(node.left, env), self.eval_node(node.right, env)
        if node.op == "+": return left + right
        if node.op == "-": return left - right
        if node.op == "*": return left * right
        if node.op == "/": return left / right
        if node.op == "%": return left % right
        if node.op == "^": return left ** right
        if node.op == "&": return int(left) & int(right)
        if node.op == "|": return int(left) | int(right)
        if node.op == "~": return int(left) ^ int(right)
        if node.op == "<": return int(left < right)
        if node.op == "<=": return int(left <= right)
        if node.op == ">": return int(left > right)
        if node.op == ">=": return int(left >= right)
        if node.op == "==": return int(left == right)
        if node.op == "!=": return int(left != right)
        raise ValueError(node.op)

    def eval_local(self, env, name):
        owner = env["owner"]
        return self.eval_node(self.catalog.parsed[(owner, "local_expression", name)], env)

    def _kw(self, node, key, env, default=None):
        value = node.kwargs.get(key)
        return default if value is None else self.eval_node(value, env)

    def spot_noise(self, node, env):
        x = self._kw(node, "x", env, env["x"])
        y = self._kw(node, "y", env, env["y"])
        region_size = max(1, int(self._kw(node, "region_size", env, 512)))
        seed0 = int(self._kw(node, "seed0", env, env["map_seed"]))
        seed1 = int(self._kw(node, "seed1", env, 0))
        span = max(1, int(self._kw(node, "skip_span", env, 1)))
        skip_offset = int(self._kw(node, "skip_offset", env, 0))
        count = int(self._kw(node, "candidate_spot_count", env, self._kw(node, "candidate_point_count", env, 1)))
        spacing = float(self._kw(node, "suggested_minimum_candidate_point_spacing", env, region_size))
        hard = bool(self._kw(node, "hard_region_target_quantity", env, False))
        basement = float(self._kw(node, "basement_value", env, 0))
        max_basement = float(self._kw(node, "maximum_spot_basement_radius", env, math.inf))
        half = region_size // 2
        rx, ry = math.floor((x + half) / region_size), math.floor((y + half) / region_size)
        radius_regions = max(1, math.ceil(max_basement / region_size)) if math.isfinite(max_basement) else 1
        density = node.kwargs.get("density_expression")
        quantity = node.kwargs.get("spot_quantity_expression")
        radius = node.kwargs.get("spot_radius_expression")
        favorability = node.kwargs.get("spot_favorability_expression")
        spots = []
        for dy in range(-radius_regions, radius_regions + 1):
            for dx in range(-radius_regions, radius_regions + 1):
                request = {"op": "spot_candidates", "seed0": seed0, "seed1": seed1,
                           "region_x": rx + dx, "region_y": ry + dy,
                           "region_size": region_size, "candidate_spot_count": count,
                           "skip_span": span, "skip_offset": skip_offset, "spacing": spacing}
                candidates = self.oracle.request(request)
                if not candidates:
                    continue
                candidate_values = {"density": [], "quantity": [], "radius": [], "favorability": []}
                for px, py in candidates:
                    candidate_env = env.copy(); candidate_env.update(x=px, y=py)
                    if density is not None: candidate_values["density"].append([px, py, self.eval_node(density, candidate_env)])
                    else: candidate_values["density"].append([px, py, 1.0])
                    if quantity is not None: candidate_values["quantity"].append([px, py, self.eval_node(quantity, candidate_env)])
                    else: candidate_values["quantity"].append([px, py, 0.0])
                    if radius is not None: candidate_values["radius"].append([px, py, self.eval_node(radius, candidate_env)])
                    else: candidate_values["radius"].append([px, py, 0.0])
                    if favorability is not None: candidate_values["favorability"].append([px, py, self.eval_node(favorability, candidate_env)])
                    else: candidate_values["favorability"].append([px, py, 1.0])
                selected = self.oracle.request({"op": "spot_select", "seed0": seed0, "seed1": seed1,
                    "region_x": rx + dx, "region_y": ry + dy, "region_size": region_size,
                    "candidate_spot_count": count, "skip_span": span, "skip_offset": skip_offset,
                    "spacing": spacing, "hard_region_target_quantity": hard, "points": candidates,
                    **candidate_values})
                spots.extend(selected)
        return self.oracle.request({"op": "spot_cone", "x": x, "y": y, "basement_value": basement,
                                     "maximum_spot_basement_radius": max_basement, "spots": spots})

    def call(self, node, env):
        if node.name == "spot_noise" and node.kwargs:
            return self.spot_noise(node, env)
        args = [self.eval_node(arg, env) for arg in node.args]
        kwargs = {key: self.eval_node(value, env) for key, value in node.kwargs.items()}
        if node.name in self.catalog.functions:
            record = self.catalog.functions[node.name]
            local = env.copy()
            for i, param in enumerate(record.get("parameters", [])):
                local[param] = kwargs[param] if param in kwargs else args[i]
            for local_name in record.get("local_expressions", {}):
                local[f"local:{local_name}"] = True
            local["owner"] = node.name
            local["local_functions"] = record.get("local_functions", {})
            return self.eval_node(self.catalog.parsed[node.name], local)
        if node.name in env.get("local_functions", {}):
            definition = env["local_functions"][node.name]
            local = env.copy()
            for i, param in enumerate(definition.get("parameters", [])):
                local[param] = kwargs[param] if param in kwargs else args[i]
            return self.eval_node(self.catalog.parsed[(env["owner"], "local_function", node.name)], local)
        if node.name == "if": return args[1] if args[0] > 0 else args[2]
        if node.name == "clamp": return min(max(args[0], args[1]), args[2])
        if node.name == "lerp": return args[0] + (args[1] - args[0]) * args[2]
        if node.name == "min": return min(args)
        if node.name == "max": return max(args)
        if node.name == "abs": return abs(args[0])
        if node.name == "sqrt": return math.sqrt(args[0])
        if node.name == "floor": return math.floor(args[0])
        if node.name == "ceil": return math.ceil(args[0])
        if node.name == "pow": return args[0] ** args[1]
        if node.name == "log2": return math.log2(args[0])
        if node.name == "sin": return math.sin(args[0])
        if node.name == "cos": return math.cos(args[0])
        if node.name == "var": return self.settings.get(args[0])
        if node.name == "distance_from_nearest_point":
            points = kwargs.get("points", args[2] if len(args) > 2 else [[0.0, 0.0]])
            px, py = kwargs.get("x", args[0] if args else env["x"]), kwargs.get("y", args[1] if len(args) > 1 else env["y"])
            return min(math.hypot(px - p[0], py - p[1]) for p in points)
        if node.name == "distance_from_nearest_point_x":
            points = kwargs.get("points", args[2] if len(args) > 2 else [[0.0, 0.0]])
            px, py = kwargs.get("x", args[0] if args else env["x"]), kwargs.get("y", args[1] if len(args) > 1 else env["y"])
            return min((px - p[0], (px - p[0]) ** 2 + (py - p[1]) ** 2) for p in points)[0]
        if node.name == "distance_from_nearest_point_y":
            points = kwargs.get("points", args[2] if len(args) > 2 else [[0.0, 0.0]])
            px, py = kwargs.get("x", args[0] if args else env["x"]), kwargs.get("y", args[1] if len(args) > 1 else env["y"])
            return min(((py - p[1]), (px - p[0]) ** 2 + (py - p[1]) ** 2) for p in points)[0]
        if node.name == "random_penalty_between":
            return args[0] + (args[1] - args[0]) * self.oracle.batch([{ "op": "random_penalty", "x": env["x"], "y": env["y"], "source": 1.0, "seed": args[2], "amplitude": 1.0 }])[0]
        if node.name == "range_select_base" or node.name == "range_select":
            if args[0] < args[1] or args[0] >= args[2]: return 0.0
            return args[3] + (args[0] - args[1]) / (args[2] - args[1]) * (args[4] - args[3])
        if node.name == "basis_noise":
            return self.oracle.basis_noise(kwargs.get("x", env["x"]), kwargs.get("y", env["y"]), int(kwargs.get("seed0", env.get("map_seed", 0))), int(kwargs["seed1"]), float(kwargs.get("input_scale", 1)), float(kwargs.get("output_scale", 1)))
        if node.name == "multioctave_noise":
            return self.oracle.batch([{ "op": "multioctave_noise", "x": kwargs.get("x", env["x"]), "y": kwargs.get("y", env["y"]), "seed0": int(kwargs.get("seed0", env.get("map_seed", 0))), "seed1": int(kwargs["seed1"]), "octaves": float(kwargs.get("octaves", 3)), "persistence": float(kwargs.get("persistence", .5)), "input_scale": float(kwargs.get("input_scale", 1)), "output_scale": float(kwargs.get("output_scale", 1)) }])[0]
        if node.name == "voronoi_cell_id":
            return self.oracle.batch([{ "op": "voronoi_cell_id", "x": kwargs.get("x", env["x"]), "y": kwargs.get("y", env["y"]), "seed0": int(kwargs.get("seed0", env.get("map_seed", 0))), "seed1": int(kwargs["seed1"]), "grid_size": float(kwargs["grid_size"]), "jitter": float(kwargs.get("jitter", .5)), "distance_type": kwargs.get("distance_type", "euclidean") }])[0]
        raise NotImplementedError(f"primitive/function not ported: {node.name}")

#!/usr/bin/env python3
"""Validate the durable invariants of the native gateway OpenAPI contract."""

from __future__ import annotations

import argparse
import copy
import re
import sys
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Any
from urllib.parse import unquote

import yaml
from jsonschema import Draft202012Validator
from jsonschema.exceptions import SchemaError


HTTP_METHODS = frozenset(
    {"get", "put", "post", "delete", "options", "head", "patch", "trace"}
)
OPENAPI_31_PATTERN = re.compile(r"^3\.1\.\d+$")
PATH_PARAMETER_PATTERN = re.compile(r"{([^{}]+)}")
JSON_POINTER_ESCAPE_PATTERN = re.compile(r"~(?:[^01]|$)")


class DuplicateKeyError(ValueError):
    """Raised when a YAML mapping contains the same key more than once."""


class UniqueKeyLoader(yaml.SafeLoader):
    """Safe YAML loader that rejects duplicate mapping keys."""


def _construct_unique_mapping(
    loader: UniqueKeyLoader,
    node: yaml.MappingNode,
    deep: bool = False,
) -> dict[Any, Any]:
    loader.flatten_mapping(node)
    mapping: dict[Any, Any] = {}
    key_marks: dict[Any, yaml.error.Mark] = {}

    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        try:
            duplicate = key in mapping
        except TypeError as error:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                "found an unhashable key",
                key_node.start_mark,
            ) from error

        if duplicate:
            first_mark = key_marks[key]
            raise DuplicateKeyError(
                f"duplicate YAML key {key!r} at "
                f"line {key_node.start_mark.line + 1}, "
                f"column {key_node.start_mark.column + 1}; "
                f"first declared at line {first_mark.line + 1}, "
                f"column {first_mark.column + 1}"
            )

        mapping[key] = loader.construct_object(value_node, deep=deep)
        key_marks[key] = key_node.start_mark

    return mapping


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
    _construct_unique_mapping,
)


@dataclass(frozen=True)
class ValidationResult:
    issues: tuple[str, ...]
    operations: int
    internal_refs: int
    component_schemas: int


def load_yaml(text: str) -> Any:
    """Parse YAML without accepting duplicate mapping keys."""

    return yaml.load(text, Loader=UniqueKeyLoader)


def _format_location(parts: Iterable[object]) -> str:
    rendered = "$"
    for part in parts:
        if isinstance(part, int):
            rendered += f"[{part}]"
        elif isinstance(part, str) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", part):
            rendered += f".{part}"
        else:
            rendered += f"[{part!r}]"
    return rendered


def _walk(value: Any, path: tuple[object, ...] = ()) -> Iterable[tuple[tuple[object, ...], Any]]:
    yield path, value
    if isinstance(value, Mapping):
        for key, child in value.items():
            yield from _walk(child, (*path, key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk(child, (*path, index))


def _resolve_json_pointer(document: Any, reference: str) -> Any:
    if reference == "#":
        return document
    if not reference.startswith("#/"):
        raise KeyError("only JSON Pointer fragments are supported")

    current = document
    for raw_token in reference[2:].split("/"):
        decoded_token = unquote(raw_token)
        if JSON_POINTER_ESCAPE_PATTERN.search(decoded_token):
            raise KeyError(f"invalid JSON Pointer escape in {raw_token!r}")
        token = decoded_token.replace("~1", "/").replace("~0", "~")
        if isinstance(current, Mapping):
            if token not in current:
                raise KeyError(token)
            current = current[token]
        elif isinstance(current, list):
            try:
                index = int(token)
            except ValueError as error:
                raise KeyError(f"{token!r} is not an array index") from error
            if index < 0 or index >= len(current):
                raise KeyError(f"array index {index} is out of bounds")
            current = current[index]
        else:
            raise KeyError(f"cannot descend through {type(current).__name__}")
    return current


def _anchor_index(document: Any) -> tuple[dict[str, Any], set[str]]:
    anchors: dict[str, Any] = {}
    duplicates: set[str] = set()
    for _, node in _walk(document):
        if not isinstance(node, Mapping):
            continue
        anchor = node.get("$anchor")
        if not isinstance(anchor, str):
            continue
        if anchor in anchors:
            duplicates.add(anchor)
        else:
            anchors[anchor] = node
    return anchors, duplicates


def _resolve_internal_ref(
    document: Any,
    reference: str,
    anchors: Mapping[str, Any],
) -> Any:
    if reference == "#" or reference.startswith("#/"):
        return _resolve_json_pointer(document, reference)
    anchor = unquote(reference[1:])
    if not anchor:
        return document
    if anchor not in anchors:
        raise KeyError(f"anchor {anchor!r} does not exist")
    return anchors[anchor]


def _dereference_object(
    document: Any,
    value: Any,
    anchors: Mapping[str, Any],
) -> Any:
    visited: set[str] = set()
    current = value
    while isinstance(current, Mapping):
        reference = current.get("$ref")
        if not isinstance(reference, str) or not reference.startswith("#"):
            break
        if reference in visited:
            raise KeyError(f"cyclic reference chain at {reference!r}")
        visited.add(reference)
        current = _resolve_internal_ref(document, reference, anchors)
    return current


def _as_mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _collect_capability_values(
    document: Any,
    schema: Any,
    anchors: Mapping[str, Any],
    visited_refs: set[str] | None = None,
) -> set[str]:
    values: set[str] = set()
    visited = set() if visited_refs is None else visited_refs

    if isinstance(schema, Mapping):
        reference = schema.get("$ref")
        if isinstance(reference, str) and reference.startswith("#") and reference not in visited:
            visited.add(reference)
            try:
                target = _resolve_internal_ref(document, reference, anchors)
            except KeyError:
                target = None
            values.update(_collect_capability_values(document, target, anchors, visited))

        for key in ("enum", "x-known-values"):
            candidates = schema.get(key)
            if isinstance(candidates, list):
                values.update(value for value in candidates if isinstance(value, str))

        for child in schema.values():
            if isinstance(child, (Mapping, list)):
                values.update(_collect_capability_values(document, child, anchors, visited))
    elif isinstance(schema, list):
        for child in schema:
            values.update(_collect_capability_values(document, child, anchors, visited))

    return values


def validate_document(document: Any) -> ValidationResult:
    issues: list[str] = []
    operation_count = 0
    internal_ref_count = 0
    component_schema_count = 0

    if not isinstance(document, Mapping):
        return ValidationResult(
            issues=("document root must be a mapping",),
            operations=0,
            internal_refs=0,
            component_schemas=0,
        )

    openapi_version = document.get("openapi")
    if not isinstance(openapi_version, str) or not OPENAPI_31_PATTERN.fullmatch(
        openapi_version
    ):
        issues.append(
            "$.openapi must declare a three-part OpenAPI 3.1 version "
            f"(found {openapi_version!r})"
        )

    anchors, duplicate_anchors = _anchor_index(document)
    for anchor in sorted(duplicate_anchors):
        issues.append(f"internal JSON Schema anchor {anchor!r} is declared more than once")

    for path, node in _walk(document):
        if not isinstance(node, Mapping) or "$ref" not in node:
            continue
        reference = node["$ref"]
        location = _format_location((*path, "$ref"))
        if not isinstance(reference, str):
            issues.append(f"{location} must be a string")
            continue
        if not reference.startswith("#"):
            continue
        internal_ref_count += 1
        try:
            _resolve_internal_ref(document, reference, anchors)
        except KeyError as error:
            issues.append(
                f"{location} cannot resolve internal reference {reference!r}: "
                f"{error.args[0]}"
            )

    components = _as_mapping(document.get("components"))
    component_schemas = _as_mapping(components.get("schemas"))
    component_schema_count = len(component_schemas)
    for schema_name, schema in component_schemas.items():
        try:
            Draft202012Validator.check_schema(schema)
        except SchemaError as error:
            relative_path = tuple(error.absolute_path)
            location = _format_location(
                ("components", "schemas", schema_name, *relative_path)
            )
            issues.append(
                f"{location} is not a valid Draft 2020-12 schema: {error.message}"
            )

    gateway_meta = component_schemas.get("GatewayMeta")
    try:
        gateway_meta = _dereference_object(document, gateway_meta, anchors)
    except KeyError as error:
        gateway_meta = None
        issues.append(f"GatewayMeta cannot be resolved: {error.args[0]}")

    gateway_meta_mapping = _as_mapping(gateway_meta)
    gateway_properties = _as_mapping(gateway_meta_mapping.get("properties"))
    capability_schema = gateway_properties.get("capabilities")
    if capability_schema is None:
        issues.append(
            "$.components.schemas.GatewayMeta.properties.capabilities is required "
            "as the capability advertisement schema"
        )
        advertised_capabilities: set[str] = set()
    else:
        advertised_capabilities = _collect_capability_values(
            document,
            capability_schema,
            anchors,
        )
        if not advertised_capabilities:
            issues.append(
                "$.components.schemas.GatewayMeta.properties.capabilities must "
                "advertise known values through enum or x-known-values"
            )

    security_schemes = _as_mapping(components.get("securitySchemes"))
    oauth_scopes_by_scheme: dict[str, set[str]] = {}
    resolved_security_schemes: dict[str, Mapping[str, Any]] = {}
    for scheme_name, raw_scheme in security_schemes.items():
        try:
            scheme = _dereference_object(document, raw_scheme, anchors)
        except KeyError as error:
            issues.append(
                f"$.components.securitySchemes[{scheme_name!r}] cannot be resolved: "
                f"{error.args[0]}"
            )
            continue
        if not isinstance(scheme, Mapping):
            continue
        resolved_security_schemes[str(scheme_name)] = scheme
        if scheme.get("type") != "oauth2":
            continue
        declared_scopes: set[str] = set()
        for flow in _as_mapping(scheme.get("flows")).values():
            declared_scopes.update(
                str(scope)
                for scope in _as_mapping(_as_mapping(flow).get("scopes")).keys()
            )
        oauth_scopes_by_scheme[str(scheme_name)] = declared_scopes

    def validate_security_requirements(value: Any, location: str) -> None:
        if not isinstance(value, list):
            issues.append(f"{location} must be an array")
            return
        for requirement_index, requirement in enumerate(value):
            requirement_location = f"{location}[{requirement_index}]"
            if not isinstance(requirement, Mapping):
                issues.append(f"{requirement_location} must be a mapping")
                continue
            for scheme_name, required_scopes in requirement.items():
                scheme_location = f"{requirement_location}[{scheme_name!r}]"
                if scheme_name not in resolved_security_schemes:
                    issues.append(
                        f"{scheme_location} names an undefined security scheme"
                    )
                    continue
                if not isinstance(required_scopes, list) or not all(
                    isinstance(scope, str) for scope in required_scopes
                ):
                    issues.append(f"{scheme_location} scopes must be an array of strings")
                    continue
                if scheme_name not in oauth_scopes_by_scheme:
                    continue
                unknown = sorted(
                    set(required_scopes) - oauth_scopes_by_scheme[scheme_name]
                )
                for scope in unknown:
                    issues.append(
                        f"{scheme_location} uses undefined OAuth scope {scope!r}"
                    )

    global_security = document.get("security")
    if global_security is not None:
        validate_security_requirements(global_security, "$.security")

    paths = document.get("paths")
    if not isinstance(paths, Mapping):
        issues.append("$.paths must be a mapping")
        paths = {}

    operation_ids: dict[str, str] = {}
    for route, raw_path_item in paths.items():
        path_location = f"$.paths[{route!r}]"
        if not isinstance(route, str) or not route.startswith("/"):
            issues.append(f"{path_location} must use an absolute path-template key")
            continue
        try:
            path_item = _dereference_object(document, raw_path_item, anchors)
        except KeyError as error:
            issues.append(f"{path_location} cannot be resolved: {error.args[0]}")
            continue
        if not isinstance(path_item, Mapping):
            issues.append(f"{path_location} must be a Path Item mapping")
            continue

        template_parameters = set(PATH_PARAMETER_PATTERN.findall(route))
        path_parameters = _as_list(path_item.get("parameters"))
        for method, operation in path_item.items():
            if method not in HTTP_METHODS:
                continue
            operation_count += 1
            operation_location = f"{path_location}.{method}"
            if not isinstance(operation, Mapping):
                issues.append(f"{operation_location} must be an Operation mapping")
                continue

            operation_id = operation.get("operationId")
            if not isinstance(operation_id, str) or not operation_id.strip():
                issues.append(f"{operation_location}.operationId must be a non-empty string")
            elif operation_id in operation_ids:
                issues.append(
                    f"{operation_location}.operationId {operation_id!r} duplicates "
                    f"{operation_ids[operation_id]}"
                )
            else:
                operation_ids[operation_id] = operation_location

            responses = operation.get("responses")
            if not isinstance(responses, Mapping) or not responses:
                issues.append(f"{operation_location}.responses must be a non-empty mapping")

            effective_parameters: dict[tuple[Any, Any], tuple[Mapping[str, Any], str]] = {}
            for source_name, parameters in (
                ("parameters", path_parameters),
                ("operation.parameters", _as_list(operation.get("parameters"))),
            ):
                for index, raw_parameter in enumerate(parameters):
                    parameter_location = (
                        f"{path_location}.{source_name}[{index}]"
                        if source_name == "parameters"
                        else f"{operation_location}.parameters[{index}]"
                    )
                    try:
                        parameter = _dereference_object(
                            document,
                            raw_parameter,
                            anchors,
                        )
                    except KeyError as error:
                        issues.append(
                            f"{parameter_location} cannot be resolved: {error.args[0]}"
                        )
                        continue
                    if not isinstance(parameter, Mapping):
                        issues.append(f"{parameter_location} must resolve to a Parameter")
                        continue
                    key = (parameter.get("name"), parameter.get("in"))
                    effective_parameters[key] = (parameter, parameter_location)

            declared_path_parameters: dict[str, tuple[Mapping[str, Any], str]] = {}
            for (name, location_type), parameter_and_location in effective_parameters.items():
                if location_type == "path" and isinstance(name, str):
                    declared_path_parameters[name] = parameter_and_location

            declared_names = set(declared_path_parameters)
            missing = sorted(template_parameters - declared_names)
            extra = sorted(declared_names - template_parameters)
            for name in missing:
                issues.append(
                    f"{operation_location} path template parameter {name!r} "
                    "is not declared"
                )
            for name in extra:
                parameter_location = declared_path_parameters[name][1]
                issues.append(
                    f"{parameter_location} declares path parameter {name!r}, "
                    "but the route template does not contain it"
                )
            for name in sorted(template_parameters & declared_names):
                parameter, parameter_location = declared_path_parameters[name]
                if parameter.get("required") is not True:
                    issues.append(
                        f"{parameter_location} path parameter {name!r} "
                        "must set required: true"
                    )

            operation_security = (
                operation["security"]
                if "security" in operation
                else global_security
            )
            if operation_security is not None:
                validate_security_requirements(
                    operation_security,
                    f"{operation_location}.security",
                )

            capability = operation.get("x-devcoordinator-capability")
            if capability is None:
                continue
            if not isinstance(capability, str) or not capability:
                issues.append(
                    f"{operation_location}.x-devcoordinator-capability "
                    "must be a non-empty string"
                )
                continue
            if operation.get("x-implementation-status") != "deferred":
                issues.append(
                    f"{operation_location} advertises capability {capability!r} "
                    "and must set x-implementation-status: deferred"
                )
            if capability not in advertised_capabilities:
                issues.append(
                    f"{operation_location} capability {capability!r} is not "
                    "advertised by GatewayMeta.capabilities"
                )

    return ValidationResult(
        issues=tuple(issues),
        operations=operation_count,
        internal_refs=internal_ref_count,
        component_schemas=component_schema_count,
    )


def _self_test_document() -> dict[str, Any]:
    return {
        "openapi": "3.1.0",
        "info": {"title": "Validator fixture", "version": "1.0.0"},
        "security": [{"oauth2": ["widgets:read"]}],
        "paths": {
            "/widgets/{widgetId}": {
                "parameters": [
                    {"$ref": "#/components/parameters/WidgetId"},
                ],
                "get": {
                    "operationId": "getWidget",
                    "x-devcoordinator-capability": "widgets.read",
                    "x-implementation-status": "deferred",
                    "responses": {"200": {"description": "Found."}},
                },
            },
            "/health": {
                "get": {
                    "operationId": "getHealth",
                    "security": [],
                    "responses": {"200": {"description": "Healthy."}},
                }
            },
        },
        "components": {
            "securitySchemes": {
                "oauth2": {
                    "type": "oauth2",
                    "flows": {
                        "authorizationCode": {
                            "authorizationUrl": "https://example.invalid/authorize",
                            "tokenUrl": "https://example.invalid/token",
                            "scopes": {"widgets:read": "Read widgets."},
                        }
                    },
                }
            },
            "parameters": {
                "WidgetId": {
                    "name": "widgetId",
                    "in": "path",
                    "required": True,
                    "schema": {"type": "string"},
                }
            },
            "schemas": {
                "GatewayMeta": {
                    "type": "object",
                    "required": ["capabilities"],
                    "properties": {
                        "capabilities": {
                            "type": "array",
                            "items": {
                                "type": "string",
                                "enum": ["widgets.read", "future.feature"],
                            },
                        }
                    },
                },
                "Widget": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {"id": {"type": "string"}},
                },
            },
        },
    }


def _mutated(
    mutate: Any,
) -> dict[str, Any]:
    document = copy.deepcopy(_self_test_document())
    mutate(document)
    return document


def run_self_tests() -> tuple[bool, int]:
    failures: list[str] = []
    executed = 0

    def expect_valid(name: str, document: Any) -> None:
        nonlocal executed
        executed += 1
        result = validate_document(document)
        if result.issues:
            failures.append(f"{name}: unexpectedly failed: {'; '.join(result.issues)}")

    def expect_issue(name: str, document: Any, fragment: str) -> None:
        nonlocal executed
        executed += 1
        result = validate_document(document)
        if not any(fragment in issue for issue in result.issues):
            failures.append(
                f"{name}: expected issue containing {fragment!r}; "
                f"found {list(result.issues)!r}"
            )

    expect_valid("valid contract and unused known future capability", _self_test_document())

    duplicate_yaml = """\
openapi: 3.1.0
info:
  title: First
  title: Duplicate
"""
    executed += 1
    try:
        load_yaml(duplicate_yaml)
    except DuplicateKeyError:
        pass
    else:
        failures.append("duplicate YAML key: loader accepted duplicate mapping key")

    expect_issue(
        "OpenAPI 3.1 version",
        _mutated(lambda document: document.__setitem__("openapi", "3.0.3")),
        "OpenAPI 3.1",
    )
    expect_issue(
        "unresolved internal ref",
        _mutated(
            lambda document: document["components"]["schemas"].__setitem__(
                "Broken",
                {"$ref": "#/components/schemas/Absent"},
            )
        ),
        "cannot resolve internal reference",
    )
    expect_issue(
        "duplicate operationId",
        _mutated(
            lambda document: document["paths"]["/health"]["get"].__setitem__(
                "operationId",
                "getWidget",
            )
        ),
        "duplicates",
    )
    expect_issue(
        "missing responses",
        _mutated(
            lambda document: document["paths"]["/health"]["get"].pop("responses")
        ),
        ".responses must be a non-empty mapping",
    )
    expect_issue(
        "missing path parameter",
        _mutated(
            lambda document: document["paths"].__setitem__(
                "/missing/{missingId}",
                {
                    "get": {
                        "operationId": "getMissing",
                        "responses": {"200": {"description": "Found."}},
                    }
                },
            )
        ),
        "path template parameter 'missingId' is not declared",
    )
    expect_issue(
        "extra path parameter",
        _mutated(
            lambda document: document["paths"].__setitem__(
                "/widgets",
                document["paths"].pop("/widgets/{widgetId}"),
            )
        ),
        "route template does not contain it",
    )
    expect_issue(
        "path parameter required",
        _mutated(
            lambda document: document["components"]["parameters"]["WidgetId"].__setitem__(
                "required",
                False,
            )
        ),
        "must set required: true",
    )
    expect_issue(
        "undefined OAuth scope",
        _mutated(
            lambda document: document.__setitem__(
                "security",
                [{"oauth2": ["widgets:delete"]}],
            )
        ),
        "uses undefined OAuth scope 'widgets:delete'",
    )
    expect_issue(
        "undefined security scheme",
        _mutated(
            lambda document: document.__setitem__(
                "security",
                [{"missingScheme": []}],
            )
        ),
        "names an undefined security scheme",
    )
    expect_issue(
        "capability status",
        _mutated(
            lambda document: document["paths"]["/widgets/{widgetId}"]["get"].__setitem__(
                "x-implementation-status",
                "implemented",
            )
        ),
        "must set x-implementation-status: deferred",
    )
    expect_issue(
        "unadvertised capability",
        _mutated(
            lambda document: document["paths"]["/widgets/{widgetId}"]["get"].__setitem__(
                "x-devcoordinator-capability",
                "widgets.write",
            )
        ),
        "is not advertised by GatewayMeta.capabilities",
    )
    expect_issue(
        "invalid Draft 2020-12 component schema",
        _mutated(
            lambda document: document["components"]["schemas"].__setitem__(
                "Broken",
                {"type": "not-a-json-schema-type"},
            )
        ),
        "is not a valid Draft 2020-12 schema",
    )

    if failures:
        print("SELF-TEST FAIL", file=sys.stderr)
        for failure in failures:
            print(f"  - {failure}", file=sys.stderr)
        return False, executed

    print(f"SELF-TEST PASS: {executed} validator scenarios")
    return True, executed


def validate_file(path: Path) -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        print(f"FAIL {path}: cannot read file: {error}", file=sys.stderr)
        return False

    try:
        document = load_yaml(text)
    except (DuplicateKeyError, yaml.YAMLError) as error:
        print(f"FAIL {path}: {error}", file=sys.stderr)
        return False

    result = validate_document(document)
    if result.issues:
        print(f"FAIL {path}", file=sys.stderr)
        for issue in result.issues:
            print(f"  - {issue}", file=sys.stderr)
        return False

    print(
        f"PASS {path}: OpenAPI 3.1; {result.operations} operations; "
        f"{result.internal_refs} internal refs; "
        f"{result.component_schemas} component schemas"
    )
    return True


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run embedded positive and must-fail regression scenarios",
    )
    parser.add_argument(
        "contracts",
        nargs="*",
        type=Path,
        help="OpenAPI YAML files to validate",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    if not args.self_test and not args.contracts:
        print("error: provide --self-test and/or at least one contract", file=sys.stderr)
        return 2

    passed = True
    if args.self_test:
        self_tests_passed, _ = run_self_tests()
        passed = self_tests_passed and passed
    for contract in args.contracts:
        passed = validate_file(contract) and passed
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())

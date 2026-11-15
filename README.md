# json

[![Package Version](https://img.shields.io/hexpm/v/pooka_json?style=for-the-badge&color=75618E)](https://hex.pm/packages/pooka_json)
[![Hex Docs](https://img.shields.io/website?url=https%3A%2F%2Fpooka-json.hexdocs.pm%2F&style=for-the-badge&label=hex&up_message=docs&up_color=FF891F&down_message=not%20found&down_color=lightgrey)](https://pooka-json.hexdocs.pm/)
[![Tests](https://img.shields.io/github/actions/workflow/status/pooka-lang/json/test.yml?style=for-the-badge&label=tests)](https://github.com/pooka-lang/json/actions/workflows/test.yml)

Typed JSON values and checked application decoders for Pooka.

```sh
pooka add pooka_json
```

```pooka
import pooka/json/decode

let count = decode.field("count", decode.int())
assert decode.read("{\"count\":3}", count) == Ok(3)
```

Parsing uses Erlang’s native JSON parser. Objects preserve order and duplicate keys; field lookup uses the first occurrence. `pooka/json/decode` checks the typed JSON tree and reports field paths. Use bounded decoding for untrusted input.

See the [API documentation](https://pooka-json.hexdocs.pm/) for the rest.

## Licence

Licensed under the [Apache License, Version 2.0](LICENSE).

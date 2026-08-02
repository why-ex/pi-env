# Item-matched tests

Executable scripts under this directory verify coordination items by filename
stem. The script name, without `.sh`, should match the coordination item `id`.
Use the canonical project-local `.pi-en/coordination` layout in fixtures.

Issue tests live under:

```text
tests/items/issues/<item-id>.sh
```

Requirement tests live under:

```text
tests/items/requirements/<item-id>.sh
```

Keep scripts as plain bash and make each script executable. Use `tests/run.sh`
to run the standard suite plus any item-matched scripts.

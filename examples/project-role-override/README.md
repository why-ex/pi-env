# Project role override example

This directory shows how a project can add role-manager roles without changing
`pi-en`'s bundled base role package.

The example role lives at:

```text
.pi/roles/domain-architect.md
```

When the role-manager package is enabled from this project, `/role
domain-architect` becomes available in addition to the bundled base roles. A
project can also override a bundled role by adding a `.pi/roles/*.md` file whose
frontmatter uses the same `name` as the bundled role.

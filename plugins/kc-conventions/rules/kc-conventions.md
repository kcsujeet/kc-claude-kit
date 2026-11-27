---
paths:
  - "**/*.{ts,tsx,js,jsx,mjs,cjs,rb,py,go,swift,kt,java,php,cs,rs}"
  - "**/{package.json,Gemfile,pnpm-workspace.yaml,requirements.txt,pyproject.toml,go.mod,Cargo.toml,Package.swift}"
---
# Conventions: load the skill before you do the thing

- Naming or renaming anything -> kc-conventions:kc-naming
- Adding a helper, component, prop or abstraction -> kc-conventions:kc-simplicity
- Adding, moving or exporting a file, function, hook or type -> kc-conventions:kc-structure
- Writing tests or fixing a bug -> kc-conventions:kc-testing
- Dates, times or timezones -> kc-conventions:kc-datetime
- Translation keys or `t()` calls -> kc-conventions:kc-i18n
- Handlers, auth, request input, secrets -> kc-conventions:kc-security
- React components, hooks, forms, queries -> kc-conventions:kc-react
- Rails models, controllers, jobs, migrations, specs -> kc-conventions:kc-rails
- Queries, list endpoints, long lists, images -> kc-conventions:kc-performance
- Conditions, loops, state, boundary data, bug hunting -> kc-conventions:kc-correctness
- Ternaries, comments, casts, dense expressions -> kc-conventions:kc-clarity
- Typed code that casts, silences a type error or parses input -> kc-conventions:kc-type-safety
- Code that throws, catches, logs or returns an error -> kc-conventions:kc-error-handling
- Adding, upgrading or removing a dependency -> kc-conventions:kc-dependencies

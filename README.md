# dls is a LSP for D (WIP)


- Supports templates (with my fork of DCD)
- Fast to compile
- Lower memory footprint
- Faster due to using DCD as a library directly



# Build

```
make build-dcd
make build-dls
```

# Editors

- VSCode:

```
make build-vscode
```

```json
    "dls.server.path":  "/home/ryuukk/dev/dls/bin/dls",
    "dls.server.imports": [
      "/home/you/project_b/",
      "projects_a/", // relative to opened folder
    ],
```

- Sublime Text:
    - install sublime's LSP extension
```json
        "dls": {
            "enabled": true,
            "command": ["/home/ryuukk/dev/dls/bin/dls"],
            "selector": "source.d",
            "settings": {
                "dls.server.imports": [
                  "/home/you/project_b/",
                  "projects_a/", // relative to opened folder
                ],
            },
        },
```
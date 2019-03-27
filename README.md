[lsp-mode](https://github.com/emacs-lsp/lsp-mode) client leveraging [PowerShellEditorServices](https://github.com/PowerShell/PowerShellEditorServices)

# Installation
## Recommended
Using [straight.el](https://github.com/raxod502/straight.el)

``` emacs-lisp
(use-package lsp-pwsh
  :straight (lsp-pwsh
             :host github
             :repo "kiennq/lsp-powershell"
             :files (:defaults "bin"))
  :hook (powershell-mode . (lambda () (require 'lsp-pwsh) (lsp)))
  :defer t)
```

You can customize `lsp-pwsh-dir` and `lsp-pwsh-cache-dir` as you see fit.

## Manual

# Debug
Comming soon...

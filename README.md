[lsp-mode](https://github.com/emacs-lsp/lsp-mode) client leveraging [PowerShellEditorServices](https://github.com/PowerShell/PowerShellEditorServices)

# Installation

## Linux/macOS Pre-requisite

Ensure you have installed [PowerShell
Core](https://github.com/PowerShell/PowerShell) before continuing - PowerShell is required to download and run the language server.

## Recommended
Using [straight.el](https://github.com/raxod502/straight.el)

``` emacs-lisp
(use-package lsp-pwsh
  :straight (lsp-pwsh
             :host github
             :repo "kiennq/lsp-powershell")
  :hook (powershell-mode . (lambda () (require 'lsp-pwsh) (lsp)))
  :defer t)
```

## Alternatives

Using [quelpa](https://framagit.org/steckerhalter/quelpa)

``` emacs-lisp
(quelpa '(lsp-pwsh :fetcher github :url "kinneq/lsp-powershell"))
```

You can customize `lsp-pwsh-dir` and `lsp-pwsh-cache-dir` as you see fit.

To redownload the latest version of [PowerShellEditorServices](https://github.com/PowerShell/PowerShellEditorServices),
use `C-u M-x lsp-pwsh-setup`.

## Manual

# Debug
Comming soon...

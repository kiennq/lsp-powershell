***Depercated***

**Development has been moved to [lsp-mode](https://github.com/emacs-lsp/lsp-mode).**


[lsp-mode](https://github.com/emacs-lsp/lsp-mode) client leveraging [PowerShellEditorServices](https://github.com/PowerShell/PowerShellEditorServices)

# Installation

## Optional Pre-requisite

You may need [powershell-mode](https://github.com/jschaf/powershell.el) for syntax highlighting.
The installation instructions bellow assumes that you've already have that.

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

Using [quelpa](https://framagit.org/steckerhalter/quelpa) with [quelpa-use-package](https://framagit.org/steckerhalter/quelpa-use-package).

``` emacs-lisp
(use-package lsp-pwsh
  :quelpa (lsp-pwsh :fetcher github :repo "kiennq/lsp-powershell")
  :hook (powershell-mode . (lambda () (require 'lsp-pwsh) (lsp-deferred)))
  :defer t)
```
## Customization

You can customize `lsp-pwsh-dir` and `lsp-pwsh-cache-dir` as you see fit.

To redownload the latest version of [PowerShellEditorServices](https://github.com/PowerShell/PowerShellEditorServices),
use `C-u M-x lsp-pwsh-setup`.

## Manual

# Debug
Supported via [dap-mode](https://github.com/emacs-lsp/dap-mode).

`lsp-pwsh` provided `dap-pwsh`, which's an extension for `dap-mode`.

;;; lsp-pwsh.el --- lsp-mode client for PowerShellEditorServices  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Kien Nguyen

;; Author: kien.n.quang@gmail.com
;; URL: https://github.com/kiennq/lsp-powershell
;; Keywords: languages
;; Package-Requires: ((emacs "25.1") (lsp-mode "6.1") (s "1.12.0") (dap-mode "0.2"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:

(require 'lsp-mode)
(require 's)
(require 'f)
(require 'cl-lib)
(require 'dap-utils)

(defgroup lsp-pwsh nil
  "LSP support for PowerShell, using the PowerShellEditorServices."
  :group 'lsp-mode
  :package-version '(lsp-mode . "6.1"))

;; PowerShell vscode flags
(defcustom lsp-pwsh-help-completion "BlockComment"
  "Controls the comment-based help completion behavior triggered by typing '##'.
Set the generated help style with 'BlockComment' or 'LineComment'.
Disable the feature with 'Disabled'."
  :type
  '(choice
    (:tag "Disabled" "BlockComment" "LineComment"))
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-script-analysis-enable t
  "Enables real-time script analysis from PowerShell Script Analyzer.
Uses the newest installed version of the PSScriptAnalyzer module or the version bundled with this extension, if it is newer."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-script-analysis-settings-path ""
  "Specifies the path to a PowerShell Script Analyzer settings file.
To override the default settings for all projects, enter an absolute path, or enter a path relative to your workspace."
  :type 'string
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-folding-enable t
  "Enables syntax based code folding.
When disabled, the default indentation based code folding is used."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-folding-show-last-line t
  "Shows the last line of a folded section similar to the default VSCode folding style.
When disabled, the entire folded region is hidden."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-preset "Custom"
  "Sets the codeformatting options to follow the given indent style in a way that is compatible with PowerShell syntax.
For more information about the brace styles please refer to https://github.com/PoshCode/PowerShellPracticeAndStyle/issues/81."
  :type
  '(choice
    (:tag "Custom" "Allman" "OTBS" "Stroustrup"))
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-open-brace-on-same-line t
  "Places open brace on the same line as its associated statement."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-new-line-after-open-brace t
  "Adds a newline (line break) after an open brace."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-new-line-after-close-brace t
  "Adds a newline (line break) after a closing brace."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-pipeline-indentation-style "NoIndentation"
  "Multi-line pipeline style settings."
  :type
  '(choice
    (:tag "IncreaseIndentationForFirstPipeline" "IncreaseIndentationAfterEveryPipeline" "NoIndentation"))
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-whitespace-before-open-brace t
  "Adds a space between a keyword and its associated scriptblock expression."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-whitespace-before-open-paren t
  "Adds a space between a keyword (if, elseif, while, switch, etc) and its associated conditional expression."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-whitespace-around-operator t
  "Adds spaces before and after an operator ('=', '+', '-', etc.)."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-whitespace-after-separator t
  "Adds a space after a separator (',' and ';')."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-whitespace-inside-brace t
  "Adds a space after an opening brace ('{') and before a closing brace ('}')."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-whitespace-around-pipe t
  "Adds a space before and after the pipeline operator ('|')."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-ignore-one-line-block t
  "Does not reformat one-line code blocks, such as \"if (...) {...} else {...}\"."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-align-property-value-pairs t
  "Align assignment statements in a hashtable or a DSC Configuration."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-code-formatting-use-correct-casing nil
  "Use correct casing for cmdlets."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-developer-editor-services-log-level "Normal"
  "Sets the logging verbosity level for the PowerShell Editor Services host executable.
Valid values are 'Diagnostic', 'Verbose', 'Normal', 'Warning', and 'Error'"
  :type
  '(choice
    (:tag "Diagnostic" "Verbose" "Normal" "Warning" "Error"))
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-developer-editor-services-wait-for-debugger nil
  "Launches the language service with the /waitForDebugger flag to force it to wait for a .NET debugger to attach before proceeding."
  :type 'boolean
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-developer-feature-flags nil
  "An array of strings that enable experimental features in the PowerShell extension."
  :type
  '(repeat string)
  :group 'lsp-pwsh)

;; lsp-pwsh custom variables
(defcustom lsp-pwsh-ext-path (expand-file-name "vscode/ms-vscode.PowerShell"
                                               dap-utils-extension-path)
  "The path to powershell vscode extension."
  :group 'lsp-pwsh
  :type 'string)

(defcustom lsp-pwsh-exe (or (executable-find "pwsh") (executable-find "powershell"))
  "PowerShell executable."
  :type 'string
  :group 'lsp-pwsh)

(defcustom lsp-pwsh-dir (expand-file-name "extension/modules" lsp-pwsh-ext-path)
  "Path to PowerShellEditorServices without last slash."
  :type 'string
  :group 'lsp-pwsh)

(defvar lsp-pwsh-cache-dir (expand-file-name ".lsp-pwsh" user-emacs-directory)
  "Path to directory where server will write cache files.
Must not nil.")

(defvar lsp-pwsh--sess-id (emacs-pid))

(defun lsp-pwsh--command ()
  "Return the command to start server."
  `(,lsp-pwsh-exe "-NoProfile" "-NonInteractive" "-NoLogo"
                  ,@(if (eq system-type 'windows-nt) '("-ExecutionPolicy" "Bypass"))
                  "-OutputFormat" "Text"
                  "-File"
                  ,(f-join lsp-pwsh-dir "PowerShellEditorServices/Start-EditorServices.ps1")
                  "-HostName" "'Emacs Host'"
                  "-HostProfileId" "'Emacs.LSP'"
                  "-HostVersion" "0.1"
                  "-LogPath" ,(f-join lsp-pwsh-cache-dir "log.txt")
                  "-LogLevel" ,lsp-pwsh-developer-editor-services-log-level
                  "-SessionDetailsPath"
                  ,(format "%s/sess-%d.json" lsp-pwsh-cache-dir lsp-pwsh--sess-id)
                  ;; "-AdditionalModules" "@('PowerShellEditorServices.VSCode')"
                  "-Stdio"
                  "-BundledModulesPath" ,lsp-pwsh-dir
                  "-FeatureFlags" "@(' ')"
                  ))

(defun lsp-pwsh--extra-init-params ()
  "Return form describing parameters for language server."
  )

(defvar lsp-pwsh--major-modes '(powershell-mode))

(defun lsp-pwsh--force-post-completion (&rest _args)
  (not (memq major-mode lsp-pwsh--major-modes)))

(if (fboundp 'company-lsp)
    (advice-add 'company-tng--supress-post-completion
                :after-while
                'lsp-pwsh--force-post-completion))

(lsp-register-custom-settings
 '(("powershell.developer.featureFlags" lsp-pwsh-developer-feature-flags)
   ("powershell.developer.editorServicesWaitForDebugger" lsp-pwsh-developer-editor-services-wait-for-debugger t)
   ("powershell.codeFormatting.useCorrectCasing" lsp-pwsh-code-formatting-use-correct-casing t)
   ("powershell.codeFormatting.alignPropertyValuePairs" lsp-pwsh-code-formatting-align-property-value-pairs t)
   ("powershell.codeFormatting.ignoreOneLineBlock" lsp-pwsh-code-formatting-ignore-one-line-block t)
   ("powershell.codeFormatting.whitespaceAroundPipe" lsp-pwsh-code-formatting-whitespace-around-pipe t)
   ("powershell.codeFormatting.whitespaceInsideBrace" lsp-pwsh-code-formatting-whitespace-inside-brace t)
   ("powershell.codeFormatting.whitespaceAfterSeparator" lsp-pwsh-code-formatting-whitespace-after-separator t)
   ("powershell.codeFormatting.whitespaceAroundOperator" lsp-pwsh-code-formatting-whitespace-around-operator t)
   ("powershell.codeFormatting.whitespaceBeforeOpenParen" lsp-pwsh-code-formatting-whitespace-before-open-paren t)
   ("powershell.codeFormatting.whitespaceBeforeOpenBrace" lsp-pwsh-code-formatting-whitespace-before-open-brace t)
   ("powershell.codeFormatting.pipelineIndentationStyle" lsp-pwsh-code-formatting-pipeline-indentation-style)
   ("powershell.codeFormatting.newLineAfterCloseBrace" lsp-pwsh-code-formatting-new-line-after-close-brace t)
   ("powershell.codeFormatting.newLineAfterOpenBrace" lsp-pwsh-code-formatting-new-line-after-open-brace t)
   ("powershell.codeFormatting.openBraceOnSameLine" lsp-pwsh-code-formatting-open-brace-on-same-line t)
   ("powershell.codeFormatting.preset" lsp-pwsh-code-formatting-preset)
   ("powershell.codeFolding.showLastLine" lsp-pwsh-code-folding-show-last-line t)
   ("powershell.codeFolding.enable" lsp-pwsh-code-folding-enable t)
   ("powershell.scriptAnalysis.settingsPath" lsp-pwsh-script-analysis-settings-path)
   ("powershell.scriptAnalysis.enable" lsp-pwsh-script-analysis-enable t)
   ("powershell.helpCompletion" lsp-pwsh-help-completion)))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection #'lsp-pwsh--command)
  :major-modes lsp-pwsh--major-modes
  :server-id 'pwsh-ls
  :priority 1
  :initialization-options #'lsp-pwsh--extra-init-params
  :notification-handlers (lsp-ht ("powerShell/executionStatusChanged" 'ignore))
  :initialized-fn (lambda (w)
                    (with-lsp-workspace w
                      (lsp--set-configuration
                       (lsp-configuration-section "powershell"))))
  ))

(defun lsp-pwsh--filter-cr (str)
  "Filter CR entities from STR."
  (when (and (eq system-type 'windows-nt) str)
    (replace-regexp-in-string "\r" "" str)))

(advice-add 'lsp-ui-doc--extract :filter-return #'lsp-pwsh--filter-cr)
(advice-add 'lsp-ui-sideline--format-info :filter-return #'lsp-pwsh--filter-cr)

(add-to-list 'lsp-language-id-configuration '(powershell-mode . "powershell"))
;;; Utils

(dap-utils-vscode-setup-function "lsp-pwsh" "ms-vscode" "PowerShell"
                                 lsp-pwsh-ext-path)

;; Download vscode extension
(lsp-pwsh-setup)

(provide 'lsp-pwsh)
;;; lsp-pwsh.el ends here

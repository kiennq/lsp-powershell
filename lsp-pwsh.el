;;; lsp-pwsh.el --- lsp-mode client for PowerShellEditorServices  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Kien Nguyen

;; Author: kien.n.quang@gmail.com
;; Keywords: languages
;; Package-Requires: ((emacs "25.1") (lsp-mode "6.0") (dash))

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

(defvar lsp-pwsh-exe (if (executable-find "pwsh") "pwsh" "powershell")
  "PowerShell executable.")

(defvar lsp-pwsh-dir (concat (file-name-directory (or load-file-name buffer-file-name))
                             "modules/")
  "Path to PowerShellEditorServices.")

(defvar lsp-pwsh-cache-dir (expand-file-name (locate-user-emacs-file ".lsp-pwsh/"))
  "Path to directory where server will write cache files.
Must not nil.")

(defvar lsp-pwsh--sess-id 0)

(defun lsp-pwsh--command ()
  "Return the command to start server."
  `(,lsp-pwsh-exe "-NoProfile"
    ,@(if (eq system-type 'windows-nt) '("-ExecutionPolicy" "Bypass"))
    ,lsp-pwsh-exe "-NoProfile" "-NonInteractive"
    "-Command"
    ,(format "\"%s\""
             (s-join " "
                     `(,(format "& '%s/PowerShellEditorServices/Start-EditorServices.ps1'" lsp-pwsh-dir)
                       "-HostName" "'Emacs Host'"
                       "-HostProfileId" "'Emacs.LSP'"
                       "-HostVersion" "0.1"
                       "-LogPath" ,(format "'%s/log.txt'" lsp-pwsh-cache-dir)
                       "-LogLevel" "Normal"
                       "-SessionDetailsPath"
                       ,(format "'%s/sess-%d.json'" lsp-pwsh-cache-dir (incf lsp-pwsh--sess-id))
                       "-AdditionalModules" "@('PowerShellEditorServices.VSCode')"
                       "-Stdio"
                       "-BundledModulesPath" ,(format "'%s'" lsp-pwsh-dir)
                       "-FeatureFlags" "@()")))
    ))

(defun lsp-pwsh--extra-init-params ()
  "Return form describing parameters for language server."
  )

(defun lsp-pwsh--force-post-completion (&rest _args)
  (advice-remove 'company-tng--supress-post-completion 'lsp-pwsh--force-post-completion)
  nil)

(defvar lsp-pwsh--major-modes '(powershell-mode))

(if (fboundp 'company-lsp)
    (advice-add 'company-tng-frontend
                :after
                #'(lambda (command)
                    (when (and (eq command 'pre-command)
                               (memq major-mode lsp-pwsh--major-modes))
                      (advice-add 'company-tng--supress-post-completion
                                  :after-while
                                  'lsp-pwsh--force-post-completion)))))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection 'lsp-pwsh--command)
  :major-modes lsp-pwsh--major-modes
  :server-id 'pwsh-ls
  :priority 1
  :initialization-options 'lsp-pwsh--extra-init-params
  :notification-handlers (lsp-ht ("powerShell/executionStatusChanged" 'ignore))
  ))

(provide 'lsp-pwsh)
;;; lsp-pwsh.el ends here

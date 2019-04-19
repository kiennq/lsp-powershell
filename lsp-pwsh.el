;;; lsp-pwsh.el --- lsp-mode client for PowerShellEditorServices  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Kien Nguyen

;; Author: kien.n.quang@gmail.com
;; URL: https://github.com/kiennq/lsp-powershell
;; Package-Version: 20190411.1904
;; Keywords: languages
;; Package-Requires: ((emacs "25.1") (lsp-mode "6.0") (dash) (s))

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

(defvar lsp-pwsh-exe (or (executable-find "pwsh") (executable-find "powershell"))
  "PowerShell executable.")

(defvar lsp-pwsh-dir (expand-file-name ".extension/pwsh/PowerShellEditorServices" user-emacs-directory)
  "Path to PowerShellEditorServices without last slash.")

(defvar lsp-pwsh-cache-dir (expand-file-name ".lsp-pwsh" user-emacs-directory)
  "Path to directory where server will write cache files.
Must not nil.")

(defvar lsp-pwsh--sess-id 0)

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
    "-LogLevel" "Normal"
    "-SessionDetailsPath"
    ,(format "%s/sess-%d.json" lsp-pwsh-cache-dir (incf lsp-pwsh--sess-id))
    "-AdditionalModules" "@('PowerShellEditorServices.VSCode')"
    "-Stdio"
    "-BundledModulesPath" ,lsp-pwsh-dir
    "-FeatureFlags" "@(' ')"
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

(defun lsp-pwsh--filter-cr (str)
  "Filter CR entities from STR."
  (when (and (eq system-type 'windows-nt) str)
      (replace-regexp-in-string "\r" "" str)))
(advice-add 'lsp-ui-doc--extract :filter-return #'lsp-pwsh--filter-cr)
(advice-add 'lsp-ui-sideline--extract-info :filter-return #'lsp-pwsh--filter-cr)

;;; Utils
(defconst lsp-pwsh-unzip-script "powershell -noprofile -noninteractive \
-nologo -ex bypass Expand-Archive -path '%s' -dest '%s'"
  "Powershell script to unzip vscode extension package file.")

(defcustom lsp-pwsh-github-asset-url
  "https://github.com/%s/%s/releases/latest/download/%s"
  "GitHub latest asset template url."
  :group 'lsp-pwsh
  :type 'string)

(defun lsp-pwsh--get-extension (url dest)
  "Get extension from URL and extract to DEST."
  (let ((temp-file (make-temp-file "ext" nil ".zip")))
    (url-copy-file url temp-file 'overwrite)
    (if (file-exists-p dest) (delete-directory dest 'recursive))
    (shell-command (format lsp-pwsh-unzip-script temp-file dest))))

(defun lsp-pwsh-setup (&optional forced)
  "Downloading PowerShellEditorServices to `lsp-pwsh-dir'.
FORCED if specified."
  (interactive "P")
  (let ((parent-dir (file-name-directory lsp-pwsh-dir)))
    (unless (and (not forced) (file-exists-p parent-dir))
      (lsp-pwsh--get-extension
       (format lsp-pwsh-github-asset-url "PowerShell" "PowerShellEditorServices" "PowerShellEditorServices.zip")
       parent-dir)
      (message "lsp-pwsh: Downloading done!")))
  )

(lsp-pwsh-setup)

(provide 'lsp-pwsh)
;;; lsp-pwsh.el ends here

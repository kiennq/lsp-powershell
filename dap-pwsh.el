;;; dap-pwsh.el --- Debug Adapter Protocol mode for Pwsh      -*- lexical-binding: t; -*-

;; Copyright (C) 2019  Kien Nguyen

;; Author: Kien Nguyen <kien.n.quang@gmail.com>
;; Keywords: languages

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

;; URL: https://github.com/yyoncho/dap-mode
;; Package-Requires: ((emacs "25.1") (lsp-mode "4.0") (dap-mode "0.2"))
;; Version: 0.2

;;; Code:

(require 'dap-mode)
(require 'lsp-pwsh)
(require 'f)
(require 'dash)

(defcustom lsp-pwsh-ext-program `("node"
                                    ,(f-join lsp-pwsh-ext-path "extension/out/src/debugAdapter.js"))
  "The path to the pwsh debugger."
  :group 'dap-pwsh
  :type '(repeat string))

(defun dap-pwsh--populate-start-file-args (conf)
  "Populate CONF with the required arguments."
  (-> conf
      (dap--put-if-absent :dap-server-path lsp-pwsh-ext-program)
      (dap--put-if-absent :type "PowerShell")
      (dap--put-if-absent :cwd default-directory)
      (dap--put-if-absent :program (read-file-name "Select the file to run:" nil (buffer-file-name) t))
      (dap--put-if-absent :name "PowerShell Debug")))

(dap-register-debug-provider "powershell" #'dap-pwsh--populate-start-file-args)

(dap-register-debug-template "PowerShell Run Configuration"
                             (list :type "PowerShell"
                                   :cwd nil
                                   :request "launch"
                                   :program nil
                                   :name "PowerShell::Run"))

(provide 'dap-pwsh)
;;; dap-pwsh.el ends here

;;; flycheck-grammalecte.el --- Integrate Grammalecte with Flycheck -*- lexical-binding: t; -*-

;; Copyright (C) 2018 Étienne Deparis
;; Copyright (C) 2017 Guilhem Doulcier

;; Maintener: Étienne Deparis <etienne@depar.is>
;; Author: Guilhem Doulcier <guilhem.doulcier@espci.fr>
;;         Étienne Deparis <etienne@depar.is>
;; Created: 21 February 2017
;; Version: 1.5
;; Package-Requires: ((emacs "26.1") (flycheck "26"))
;; Keywords: i18n, text
;; Homepage: https://git.umaneti.net/flycheck-grammalecte/

;;; Commentary:

;; Adds support for Grammalecte (a french grammar checker) to flycheck.

;;; License:

;; This file is not part of GNU Emacs.
;; However, it is distributed under the same license.

;; GNU Emacs is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.

;;; Code:

(require 'flycheck)
(require 'grammalecte)

;; Make the compile happy about grammalecte lib
(declare-function grammalecte--version "grammalecte")
(declare-function grammalecte--augment-pythonpath-if-needed "grammalecte")
(eval-when-compile
  (defvar grammalecte--site-directory)
  (defvar grammalecte-python-package-directory))

;;;; Configuration options:

(defgroup flycheck-grammalecte nil
  "Flycheck Grammalecte options"
  :group 'flycheck-options
  :group 'grammalecte)

(defcustom flycheck-grammalecte-report-spellcheck nil
  "Report spellcheck errors if non-nil.
Default is nil.  You should use `flyspell' instead."
  :type 'boolean
  :package-version "0.2"
  :group 'flycheck-grammalecte)

(defcustom flycheck-grammalecte-report-grammar t
  "Report grammar errors if non-nil.
Default is t."
  :type 'boolean
  :package-version "0.2"
  :group 'flycheck-grammalecte)

(defcustom flycheck-grammalecte-report-apos t
  "Report apostrophe errors if non-nil.
Default is t."
  :type 'boolean
  :package-version "0.2"
  :group 'flycheck-grammalecte)

(defcustom flycheck-grammalecte-report-nbsp t
  "Report non-breakable spaces errors if non-nil.
Default is t."
  :type 'boolean
  :package-version "0.2"
  :group 'flycheck-grammalecte)

(defcustom flycheck-grammalecte-report-esp t
  "Report useless spaces and tabs errors if non-nil.
Default is t."
  :type 'boolean
  :package-version "0.6"
  :group 'flycheck-grammalecte)

(defcustom flycheck-grammalecte-enabled-modes
  '(latex-mode
    mail-mode
    markdown-mode
    message-mode
    mu4e-compose-mode
    org-mode
    text-mode)
  "Major modes for which `flycheck-grammalecte' should be enabled.

Sadly, flycheck does not use `derived-mode-p' to check if it must
be enabled or not in the current buffer.  Thus, be sure to set up
a comprehensive mode list for your own usage.

Default modes are `latex-mode', `mail-mode', `markdown-mode',
`message-mode', `mu4e-compose-mode', `org-mode' and `text-mode'."
  :type '(repeat (function :tag "Mode"))
  :package-version "0.2"
  :group 'flycheck-grammalecte)

(defcustom flycheck-grammalecte-filters
  '("(?m)^# ?-*-.+$")
  "Patterns for which errors in matching texts are ignored.

As these patterns will be used by the underlying python script,
they must be python Regular Expressions (See URL
`https://docs.python.org/3.5/library/re.html#regular-expression-syntax').

Escape character `\\' must be doubled twice: one time for Emacs
and one time for python.  For example, to exclude LaTeX math
formulas, one can use :

    (setq flycheck-grammalecte-filters
          '(\"\\$.*?\\$\"
            \"(?s)\\\\begin{equation}.*?\\\\end{equation}\"))

For simple use case, you can try to use the function
`flycheck-grammalecte--convert-elisp-rx-to-python'.

Filters are applied sequentially.  In practice all characters of
the matching pattern are replaced by `█', which are ignored by
grammalecte.

This patterns are always sent to Grammalecte.  See the variable
`flycheck-grammalecte-filters-by-mode' for mode-related patterns."
  :type '(repeat string)
  :package-version "1.1"
  :group 'flycheck-grammalecte)

(defcustom flycheck-grammalecte-filters-by-mode
  '((latex-mode "\\\\(?:title|(?:sub)*section){([^}]+)}"
                "\\\\\\w+(?:\\[[^]]+\\])?(?:{[^}]*})?")
    (org-mode "(?ims)^[ \t]*#\\+begin_src.+#\\+end_src"
              "(?im)^[ \t]*#\\+begin[_:].+$"
              "(?im)^[ \t]*#\\+end[_:].+$"
              "(?m)^[ \t]*(?:DEADLINE|SCHEDULED):.+$"
              "(?m)^\\*+ .*[ \t]*(:[\\w:@]+:)[ \t]*$"
              "(?im)^[ \t]*#\\+(?:caption|description|keywords|(?:sub)?title):"
              "(?im)^[ \t]*#\\+(?!caption|description|keywords|(?:sub)?title)\\w+:.*$")
    (message-mode "(?m)^[ \t]*(?:[\\w_.]+>|[]>|]).*"))
  "Filtering patterns by mode.

Each element has the form (MODE PATTERNS...), where MODE must be
a valid major mode and PATTERNS must be a list of regexp as
described in the variable `flycheck-grammalecte-filters'.

Contrary to flycheck, we will use `derived-mode-p' to check if a
filters list must be activated or not.  Thus you are not obliged
to list all possible modes, as soon as one is an ancestor of
another.

Patterns defined here will be added after the ones defined in
`flycheck-grammalecte-filters' when their associated mode matches
the current buffer major mode, or is an ancestor of it.  This
operation is only done once when the function
`flycheck-grammalecte-setup' is run."
  :type '(alist :key-type (function :tag "Mode")
                :value-type (repeat string))
  :package-version "1.1"
  :group 'flycheck-grammalecte)

(defcustom flycheck-grammalecte-borders-by-mode
  '((latex-mode . "^\\\\begin{document}$")
    (mail-mode . "^--text follows this line--")
    (message-mode . "^--text follows this line--"))
  "Line patterns before which proofing must not occur for given mode.

Each element is a cons-cell (MODE . PATTERN), where MODE must be
a valid major mode and PATTERN must be a regexp as described in
the variable `flycheck-grammalecte-filters'.

For the given MODE, the corresponding PATTERN should match a line in the
file being proofed.  All lines before this match will be ignored by the
process.  This variable is used for example to avoid proofing mail
headers or LaTeX documents header.

Contrary to flycheck, we will use `derived-mode-p' to check if a
border must be activated or not.  Thus you are not obliged to
list all possible modes, as soon as one is an ancestor of
another.  This activation is only done once when the function
`flycheck-grammalecte-setup' is run."
  :type '(repeat string)
  :package-version "1.1"
  :group 'flycheck-grammalecte)

(defvar flycheck-grammalecte--debug-mode nil
  "Display some debug messages when non-nil.")



;;;; Helper methods:

(defun flycheck-grammalecte--convert-elisp-rx-to-python (regexp)
  "Convert the given elisp REGEXP to a python 3 regular expression.

For example, given the following REGEXP

   \\\\(?:title\\|\\(?:sub\\)*section\\){\\([^}]+\\)}\\)

This function will return

    \\\\(?:title|(?:sub)*section){([^}]+)})

See URL
`https://docs.python.org/3.5/library/re.html#regular-expression-syntax'
and Info node `(elisp)Syntax of Regular Expressions'."
  (let ((convtable '(("\\\\(" . "(")
                     ("\\\\)" . ")")
                     ("\\\\|" . "|")
                     ("\\\\" . "\\\\")
                     ("\\[:alnum:\\]" . "\\w")
                     ("\\[:space:\\]" . "\\s")
                     ("\\[:blank:\\]" . "\\s")
                     ("\\[:digit:\\]" . "\\d")
                     ("\\[:word:\\]" . "\\w"))))
    (when (and (string-match "\\[:\\([a-z]+\\):\\]" regexp)
               (not (string= "digit" (match-string 1 regexp)))
               (not (string= "word" (match-string 1 regexp))))
      (signal 'invalid-regexp
              (list (format
                     "%s is not supported by python regular expressions"
                     (match-string 0 regexp)))))
    (dolist (convpattern convtable)
      (setq regexp
            (replace-regexp-in-string (car convpattern)
                                      (cdr convpattern)
                                      regexp t t)))
    regexp))

(defun flycheck-grammalecte--split-error-message (err)
  "Split ERR message between actual message and suggestions."
  (when err
    (let* ((err-msg (split-string (flycheck-error-message err) "⇨" t " "))
           (suggestions (split-string (or (cadr err-msg) "") "," t " ")))
      (cons (car err-msg) suggestions))))

(defun flycheck-grammalecte--fix-error (err repl &optional region)
  "Replace the wrong REGION of ERR by REPL."
  (when repl
    (unless region
      (setq region (flycheck-error-region-for-mode err major-mode)))
    (when region
      (delete-region (car region) (cdr region)))
    (insert repl)))



;;;; Public methods:

(defun flycheck-grammalecte-correct-error-at-point (pos)
  "Correct the first error encountered at POS.

This method replace the word at POS by the first suggestion coming from
flycheck, if any."
  (interactive "d")
  (let ((first-err (car-safe (flycheck-overlay-errors-at pos))))
    (when first-err
      (flycheck-grammalecte--fix-error
       first-err
       (cadr (flycheck-grammalecte--split-error-message first-err))))))

(defun flycheck-grammalecte-correct-error-at-click (event)
  "Popup a menu to help correct error under mouse pos defined in EVENT."
  (interactive "e")
  (save-excursion
    (mouse-set-point event)
    (let ((first-err (car-safe (flycheck-overlay-errors-at (point)))))
      (when first-err
        (let* ((region (flycheck-error-region-for-mode first-err major-mode))
               (word (buffer-substring-no-properties (car region) (cdr region)))
               (splitted-err (flycheck-grammalecte--split-error-message first-err))
               (repl-menu (mapcar
                           #'(lambda (repl) (list repl repl))
                           (cdr splitted-err))))
          ;; Add a reminder of the error message
          (push (car splitted-err) repl-menu)
          (flycheck-grammalecte--fix-error
           first-err
           (car-safe
            (x-popup-menu
             event
             (list
              (format "Corrections pour %s" word)
              (cons "Suggestions de Grammalecte" repl-menu))))
           region))))))

(defun flycheck-grammalecte--download-grammalecte-if-needed (&optional force)
  "Install Grammalecte python package if it's required.

This method checks if the python package is already installed and
if the current buffer major mode is present in the
`flycheck-grammalecte-enabled-modes' list.

If optional argument FORCE is non-nil, verification will occurs
even when current buffer major mode is not in
`flycheck-grammalecte-enabled-modes'."
  (when (or force (memq major-mode flycheck-grammalecte-enabled-modes))
    (grammalecte--download-grammalecte-if-needed)))

(add-hook 'flycheck-mode-hook
          #'flycheck-grammalecte--download-grammalecte-if-needed)



;;;; Checker definition:

;;;###autoload
(defun flycheck-grammalecte-setup ()
  "Build the flycheck checker, matching your taste."
  (flycheck-def-executable-var 'grammalecte "python3")
  (let ((cmdline '(source))
        (filters (mapcan #'(lambda (filter) (list "-f" filter))
                         flycheck-grammalecte-filters))
        (grammalecte-bin (expand-file-name
                          "flycheck-grammalecte.py"
                          grammalecte--site-directory))
        (flycheck-version-number (string-to-number (flycheck-version nil)))
        flycheck-grammalecte--error-patterns)

    (pcase-dolist (`(,mode . ,patterns) flycheck-grammalecte-filters-by-mode)
      (when (derived-mode-p mode)
        (dolist (filter patterns)
          (nconc filters (list "-f" filter)))))
    (pcase-dolist (`(,mode . ,border) flycheck-grammalecte-borders-by-mode)
      (when (derived-mode-p mode)
        (nconc filters (list "-b" border))))
    (unless flycheck-grammalecte-report-spellcheck (push "-S" cmdline))
    (unless flycheck-grammalecte-report-grammar (push "-G" cmdline))
    (unless flycheck-grammalecte-report-apos (push "-A" cmdline))
    (unless flycheck-grammalecte-report-nbsp (push "-N" cmdline))
    (unless flycheck-grammalecte-report-esp (push "-W" cmdline))
    (setq cmdline (nconc (list "python3" grammalecte-bin) filters cmdline))

    (setq flycheck-grammalecte--error-patterns
          (if (< flycheck-version-number 32)
              '((warning line-start "grammaire|" (message) "|" line "|"
                         (1+ digit) "|" column "|" (1+ digit) line-end)
                (info line-start "orthographe|" (message) "|" line "|"
                      (1+ digit) "|" column "|" (1+ digit) line-end))
            '((warning line-start "grammaire|" (message) "|" line "|" end-line
                       "|" column "|" end-column line-end)
              (info line-start "orthographe|" (message) "|" line "|" end-line
                    "|" column "|" end-column line-end))))

    (when flycheck-grammalecte--debug-mode
      (let ((grammalecte-version (grammalecte--version))
            (checker-path (expand-file-name
                           "grammar_checker.py"
                           grammalecte-python-package-directory)))
        (if (file-exists-p checker-path)
            (display-warning 'flycheck-grammalecte
                             (format "Version %s found in %s"
                                     grammalecte-version checker-path)
                             :debug)
          (display-warning 'flycheck-grammalecte "NOT FOUND")))
      (display-warning 'flycheck-grammalecte
                       (format "Detected mode: %s" major-mode)
                       :debug)
      (display-warning
       'flycheck-grammalecte
       (format "Checker command: %s"
               (mapconcat
                #'(lambda (item)
                    (cond ((symbolp item) (format "'%s" (symbol-name item)))
                          ((stringp item) item)))
                cmdline " "))
       :debug)
      (display-warning 'flycheck-grammalecte
                       (format "Flycheck error-patterns %s"
                               flycheck-grammalecte--error-patterns)
                       :debug))

    ;; Be sure grammalecte python module is accessible
    (grammalecte--augment-pythonpath-if-needed)

    ;; Now that we have all our variables, we can create the custom
    ;; checker.
    (flycheck-define-command-checker 'grammalecte
      "Grammalecte syntax checker for french language
See URL `https://grammalecte.net/'."
      :command cmdline
      :error-patterns flycheck-grammalecte--error-patterns
      :modes flycheck-grammalecte-enabled-modes)
    (add-to-list 'flycheck-checkers 'grammalecte)

    (if (< flycheck-version-number 32)
        (let ((warn-user-about-flycheck
               #'(lambda (_arg)
                   (display-warning
                    'flycheck-grammalecte
                    (format "Le remplacement des erreurs ne fonctionne qu'avec flycheck >= 32 (vous utilisez la version %s)."
                            flycheck-version-number)))))
          ;; Desactivate corrections methods
          (advice-add 'flycheck-grammalecte-correct-error-at-click
                      :override
                      warn-user-about-flycheck)
          (advice-add 'flycheck-grammalecte-correct-error-at-point
                      :override
                      warn-user-about-flycheck))
      ;; Add our fixers to right click and C-c ! g
      (define-key flycheck-mode-map (kbd "<mouse-3>")
        #'flycheck-grammalecte-correct-error-at-click)
      (define-key flycheck-command-map "g"
        #'flycheck-grammalecte-correct-error-at-point))))

(add-hook 'after-change-major-mode-hook
          #'(lambda ()
              (when (memq major-mode flycheck-grammalecte-enabled-modes)
                (flycheck-grammalecte-setup))))

(provide 'flycheck-grammalecte)
;;; flycheck-grammalecte.el ends here

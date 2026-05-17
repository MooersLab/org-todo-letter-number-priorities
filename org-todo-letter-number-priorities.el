;;; org-todo-letter-number-priorities.el --- Letter+number TODO priorities for Org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; Maintainer: Blaine Mooers <blaine-mooers@ou.edu>
;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1") (org "9.3"))
;; Keywords: outlines, calendar, convenience, org
;; URL: https://github.com/blaine-mooers/org-todo-letter-number-priorities

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This package provides letter+number priority cookies for Org-mode
;; TODOs.  A prioritized headline takes the form
;;
;;     ** TODO [A1] task description :tag:
;;
;; A single space is required between the keyword `TODO' and the left
;; square bracket of the priority cookie.  X is an uppercase letter
;; that names a priority group and Y is a non-negative integer that
;; ranks the item inside the group; smaller Y means higher priority.
;;
;; The package is self-contained.  It does not depend on howm-todo;
;; the relevant region-and-text logic, the SQLite project lookup, and
;; the tag sanitization helpers are inlined.
;;
;; The package supports:
;;   - `oltp-prioritize-region' marks every `**+' headline in the
;;     region with `TODO [XY]'.  Blank lines separate priority groups,
;;     so the first contiguous block of headlines gets letter A, the
;;     next block gets B, and so on.
;;   - `oltp-strip-region' removes `[XY]' cookies from headlines.
;;     The `TODO' keyword is preserved.
;;   - `oltp-sort-region' sorts `**+' subtrees in the region by `[XY]'
;;     priority.  Each subtree moves as a unit so SCHEDULED lines and
;;     body text follow their headline.  Level-1 `*' headlines act as
;;     section boundaries and stay in place.
;;   - `oltp-add-project-tag' reads a project name from the SQLite
;;     database referenced by `oltp-db-path' and adds it as an Org
;;     tag on the current headline.
;;   - `oltp-tag-region' prompts once per `**+' headline.
;;   - `oltp-init-tasks-file' scaffolds `tasks.org' with eleven
;;     top-level section headlines.
;;   - `oltp-schedule-tasks-file' walks `tasks.org' and adds a
;;     SCHEDULED line under each `** TODO' based on its parent `*'
;;     section.

;;; Code:

(require 'org)
(require 'cl-lib)
(require 'subr-x)
(require 'sqlite nil t)

;;; ---------------------------------------------------------------------------
;;; Customization
;;; ---------------------------------------------------------------------------

(defgroup org-todo-letter-number-priorities nil
  "Letter+number priority cookies for Org-mode TODOs."
  :group 'org
  :prefix "oltp-")

(defcustom oltp-tasks-file
  (expand-file-name "tasks.org" (or (getenv "HOME") "~"))
  "Absolute path to the tasks.org file managed by this package.
Both the directory and the file name are part of this option, so
you can keep tasks.org wherever you like.  For example:

  (setq oltp-tasks-file \"~/org/tasks.org\")"
  :type 'file
  :group 'org-todo-letter-number-priorities)

(defcustom oltp-tasks-file-headlines
  '("Do it today"
    "Do it this week"
    "Do it next week"
    "Do it later this month"
    "Do it next month"
    "Do it in two months"
    "Do it in three months"
    "Do it in four months"
    "Do it in five months"
    "Do it in six months"
    "Do it next year")
  "Top-level headlines written by `oltp-init-tasks-file'.
The order is significant.  Each entry should have a corresponding
entry in `oltp-section-date-functions' so that
`oltp-schedule-tasks-file' can pick a SCHEDULED date for the
TODOs under it."
  :type '(repeat string)
  :group 'org-todo-letter-number-priorities)

(defcustom oltp-org-todo-keyword "TODO"
  "Org keyword used in front of the priority cookie."
  :type 'string
  :group 'org-todo-letter-number-priorities)

(defcustom oltp-db-path
  (expand-file-name "60003TimeTracking/cb/tenKprojects.db"
                    (or (getenv "HOME") "~"))
  "Absolute path to the SQLite database that holds project metadata."
  :type 'file
  :group 'org-todo-letter-number-priorities)

(defcustom oltp-db-table nil
  "Table inside `oltp-db-path' that holds project rows.
When nil, the package walks every table in the database and
chooses the first one that has a column named by `oltp-db-column'."
  :type '(choice (const :tag "Auto-detect" nil) string)
  :group 'org-todo-letter-number-priorities)

(defcustom oltp-db-column "ProjectDirectory"
  "Column in the projects table that holds the project identifier."
  :type 'string
  :group 'org-todo-letter-number-priorities)

(defcustom oltp-tag-use-basename t
  "When non-nil, use the basename of the project path as the Org tag.
When nil, sanitize the full path.  Org tag characters are limited
to letters, digits, underscore, at-sign, and percent.  Other
characters are replaced with an underscore."
  :type 'boolean
  :group 'org-todo-letter-number-priorities)

;;; ---------------------------------------------------------------------------
;;; Date helpers
;;; ---------------------------------------------------------------------------

(defun oltp--days-hence (n)
  "Return a time value N days from today."
  (time-add (current-time) (days-to-time n)))

(defun oltp--months-hence (n)
  "Return a time value N months from today.
The day-of-month is clamped to 28 so that February and other
short months do not overflow.  `current-time' is consulted
through its Lisp binding so callers can rebind it for testing."
  (let* ((now (decode-time (current-time)))
         (sec   (nth 0 now))
         (min   (nth 1 now))
         (hour  (nth 2 now))
         (day   (nth 3 now))
         (month (nth 4 now))
         (year  (nth 5 now))
         (total (+ month n))
         (year-offset (/ (1- total) 12))
         (new-month (1+ (mod (1- total) 12)))
         (new-year (+ year year-offset))
         (new-day (min day 28)))
    (encode-time sec min hour new-day new-month new-year)))

(defun oltp--end-of-current-month ()
  "Return a time value for the last day of the current month.
`current-time' is consulted through its Lisp binding so callers
can rebind it for testing."
  (let* ((now (decode-time (current-time)))
         (month (nth 4 now))
         (year  (nth 5 now))
         (next-month (if (= month 12) 1 (1+ month)))
         (next-year  (if (= month 12) (1+ year) year))
         (first-of-next (encode-time 0 0 0 1 next-month next-year)))
    (time-subtract first-of-next (days-to-time 1))))

(defun oltp--first-of-next-month ()
  "Return a time value for the first day of next month.
`current-time' is consulted through its Lisp binding so callers
can rebind it for testing."
  (let* ((now (decode-time (current-time)))
         (month (nth 4 now))
         (year  (nth 5 now))
         (next-month (if (= month 12) 1 (1+ month)))
         (next-year  (if (= month 12) (1+ year) year)))
    (encode-time 0 0 0 1 next-month next-year)))

(defun oltp--first-of-next-year ()
  "Return a time value for January 1 of next year.
`current-time' is consulted through its Lisp binding so callers
can rebind it for testing."
  (let ((year (1+ (nth 5 (decode-time (current-time))))))
    (encode-time 0 0 0 1 1 year)))

(defcustom oltp-section-date-functions
  `(("Do it today"            . ,(lambda () (current-time)))
    ("Do it this week"        . ,(lambda () (oltp--days-hence 6)))
    ("Do it next week"        . ,(lambda () (oltp--days-hence 13)))
    ("Do it later this month" . ,(lambda () (oltp--end-of-current-month)))
    ("Do it next month"       . ,(lambda () (oltp--first-of-next-month)))
    ("Do it in two months"    . ,(lambda () (oltp--months-hence 2)))
    ("Do it in three months"  . ,(lambda () (oltp--months-hence 3)))
    ("Do it in four months"   . ,(lambda () (oltp--months-hence 4)))
    ("Do it in five months"   . ,(lambda () (oltp--months-hence 5)))
    ("Do it in six months"    . ,(lambda () (oltp--months-hence 6)))
    ("Do it next year"        . ,(lambda () (oltp--first-of-next-year))))
  "Alist mapping a section headline name to a function returning a time.
Each function takes no arguments and returns an Emacs time value.
`oltp-schedule-tasks-file' uses the returned time as the
SCHEDULED date for every TODO under the matching section."
  :type '(alist :key-type string :value-type function)
  :group 'org-todo-letter-number-priorities)

(defun oltp--date-for-section (section)
  "Return a time value for SECTION, or nil when no mapping exists."
  (let ((entry (assoc section oltp-section-date-functions)))
    (when entry (funcall (cdr entry)))))

;;; ---------------------------------------------------------------------------
;;; Headline parsing
;;; ---------------------------------------------------------------------------

(defun oltp--headline-rx ()
  "Return a regex that matches an org headline with optional TODO and cookie.
Match groups:
  1. The leading stars.
  2. The TODO keyword, if present.
  3. The priority letter X, if a cookie is present.
  4. The priority number Y, if a cookie is present.
  5. The remainder of the line after the cookie."
  (concat "^\\(\\*+\\)[ \t]+"
          "\\(?:\\("
          (regexp-quote oltp-org-todo-keyword)
          "\\)\\b[ \t]+\\)?"
          "\\(?:\\[\\([A-Z]\\)\\([0-9]+\\)\\][ \t]+\\)?"
          "\\(.*\\)$"))

(defun oltp--at-headline-p ()
  "Return non-nil when point is on an org headline line."
  (save-excursion
    (beginning-of-line)
    (looking-at "^\\*+[ \t]+")))

(defun oltp--current-headline-priority ()
  "Return (LETTER . NUMBER) for the current headline, or nil when absent."
  (save-excursion
    (beginning-of-line)
    (when (looking-at (oltp--headline-rx))
      (let ((letter (match-string 3))
            (number (match-string 4)))
        (when (and letter number)
          (cons letter (string-to-number number)))))))

(defun oltp--rewrite-current-headline (letter number)
  "Replace the current headline with one carrying TODO [LETTER NUMBER]."
  (save-excursion
    (beginning-of-line)
    (when (looking-at (oltp--headline-rx))
      (let* ((stars (match-string 1))
             (rest  (match-string 5))
             (new   (format "%s %s [%s%d] %s"
                            stars
                            oltp-org-todo-keyword
                            letter number rest)))
        (delete-region (line-beginning-position) (line-end-position))
        (insert new)))))

(defun oltp--strip-cookie-on-current-headline ()
  "Remove the [XY] cookie from the current headline, keeping TODO if any."
  (save-excursion
    (beginning-of-line)
    (when (looking-at (oltp--headline-rx))
      (let* ((stars   (match-string 1))
             (keyword (match-string 2))
             (letter  (match-string 3))
             (rest    (match-string 5)))
        (when letter
          (let ((new (if keyword
                         (format "%s %s %s" stars keyword rest)
                       (format "%s %s" stars rest))))
            (delete-region (line-beginning-position) (line-end-position))
            (insert new)))))))

;;; ---------------------------------------------------------------------------
;;; Region commands: prioritize, strip, sort
;;; ---------------------------------------------------------------------------

;;;###autoload
(defun oltp-strip-region (beg end)
  "Remove `[XY]' cookies from every org headline in the region.
The TODO keyword is preserved."
  (interactive "r")
  (let ((end-marker (copy-marker end t)))
    (save-excursion
      (goto-char beg)
      (while (< (point) (marker-position end-marker))
        (when (oltp--at-headline-p)
          (oltp--strip-cookie-on-current-headline))
        (forward-line 1))
      (set-marker end-marker nil))))

;;;###autoload
(defun oltp-prioritize-region (beg end)
  "Add `TODO [XY]' cookies to every `*' headline in the region.
Blank lines start a new priority group, so the first contiguous
block of headlines becomes A1, A2, A3, the next block becomes
B1, B2, and so on.  Non-headline content lines between headlines
do not break a group and do not consume a slot.  Existing cookies
are stripped before the new ones are added, so the command is
idempotent."
  (interactive "r")
  (let ((end-marker (copy-marker end t)))
    (oltp-strip-region beg end-marker)
    (save-excursion
      (save-restriction
        (narrow-to-region beg (marker-position end-marker))
        (goto-char (point-min))
        (let ((group-index 0)
              (item-index 0)
              (in-group nil))
          (while (not (eobp))
            (cond
             ((looking-at "^[ \t]*$")
              (when in-group
                (setq group-index (1+ group-index))
                (setq item-index 0)
                (setq in-group nil)))
             ((oltp--at-headline-p)
              (setq item-index (1+ item-index))
              (setq in-group t)
              (oltp--rewrite-current-headline
               (char-to-string (+ ?A group-index))
               item-index))
             (t nil))
            (forward-line 1)))))
    (set-marker end-marker nil)))

(defun oltp--priority-sort-cmp (a b)
  "Return a negative, zero, or positive integer comparing keys A and B.
A and B are conses of the form (LETTER . NUMBER), or nil."
  (cond
   ((and (null a) (null b)) 0)
   ((null a) 1)
   ((null b) -1)
   ((string< (car a) (car b)) -1)
   ((string= (car a) (car b))
    (cond ((< (cdr a) (cdr b)) -1)
          ((> (cdr a) (cdr b)) 1)
          (t 0)))
   (t 1)))

(defun oltp--render-sorted-subtrees (subtrees)
  "Sort SUBTREES by priority key and concatenate their text.
Each element of SUBTREES is a list (KEY ORIG-IDX TEXT).  Sorting
is stable: subtrees that share a key keep their original order."
  (let ((sorted (sort (copy-sequence subtrees)
                      (lambda (a b)
                        (let ((c (oltp--priority-sort-cmp
                                  (nth 0 a) (nth 0 b))))
                          (if (zerop c)
                              (< (nth 1 a) (nth 1 b))
                            (< c 0)))))))
    (mapconcat (lambda (s) (nth 2 s)) sorted "")))

(defun oltp--read-region-chunks ()
  "Walk from point to EOB, returning a list of (TYPE . TEXT) chunks.
TYPE is one of: `preamble', `section' (a `*' headline and its
body, up to the next `*' or `**+' headline), `subtree' (a `**+'
headline and its body, up to the next `*' or `**+' headline)."
  (let ((chunks nil)
        (cur-type 'preamble)
        (cur-text ""))
    (while (not (eobp))
      (let* ((bol (line-beginning-position))
             (line-end (min (1+ (line-end-position)) (point-max)))
             (line (buffer-substring-no-properties bol line-end))
             (new-type (cond
                        ((looking-at "^\\* ") 'section)
                        ((looking-at "^\\*\\*+ ") 'subtree)
                        (t nil))))
        (when new-type
          (unless (string-empty-p cur-text)
            (push (cons cur-type cur-text) chunks))
          (setq cur-type new-type)
          (setq cur-text ""))
        (setq cur-text (concat cur-text line))
        (goto-char line-end)))
    (unless (string-empty-p cur-text)
      (push (cons cur-type cur-text) chunks))
    (nreverse chunks)))

(defun oltp--chunk-priority (chunk-text)
  "Return the priority cons for the headline that starts CHUNK-TEXT, or nil."
  (let ((first-line (car (split-string chunk-text "\n"))))
    (when (string-match (oltp--headline-rx) first-line)
      (let ((letter (match-string 3 first-line))
            (number (match-string 4 first-line)))
        (when (and letter number)
          (cons letter (string-to-number number)))))))

;;;###autoload
(defun oltp-sort-region (beg end)
  "Sort `**' (and deeper) subtrees in the region by `[XY]' priority.
`*' level-1 headlines act as section boundaries and stay in
place; only the `**+' subtrees inside each section move.  Each
subtree, from its `**+' line up to (but not including) the next
`*' or `**+' headline, moves as a unit, so SCHEDULED lines and
body text follow their headline.  Text that appears before the
first headline in the region stays in place.  Subtrees that lack
a `[XY]' cookie sort to the end of their section in their
original relative order."
  (interactive "r")
  (save-excursion
    (save-restriction
      (narrow-to-region beg end)
      (goto-char (point-min))
      (let* ((chunks (oltp--read-region-chunks))
             (output "")
             (pending nil)
             (idx 0))
        (dolist (chunk chunks)
          (pcase (car chunk)
            ('preamble
             (setq output (concat output (cdr chunk))))
            ('section
             (setq output (concat output
                                  (oltp--render-sorted-subtrees
                                   (nreverse pending))))
             (setq pending nil)
             (setq idx 0)
             (setq output (concat output (cdr chunk))))
            ('subtree
             (push (list (oltp--chunk-priority (cdr chunk))
                         idx
                         (cdr chunk))
                   pending)
             (setq idx (1+ idx)))))
        (setq output (concat output
                             (oltp--render-sorted-subtrees
                              (nreverse pending))))
        (delete-region (point-min) (point-max))
        (insert output)))))

;;; ---------------------------------------------------------------------------
;;; SQLite project lookup
;;; ---------------------------------------------------------------------------

(defun oltp--sqlite-builtin-rows (sql)
  "Run SQL against `oltp-db-path' through the built-in sqlite library.
Return a list of rows; each row is a list of strings."
  (let ((db (sqlite-open oltp-db-path)))
    (unwind-protect
        (mapcar (lambda (row)
                  (mapcar (lambda (v) (if v (format "%s" v) "")) row))
                (sqlite-select db sql))
      (sqlite-close db))))

(defun oltp--sqlite-shell-rows (sql)
  "Run SQL against `oltp-db-path' through the sqlite3 shell.
Return a list of rows; each row is a list of strings."
  (with-temp-buffer
    (let ((status (call-process "sqlite3" nil t nil
                                "-readonly"
                                "-noheader"
                                "-list"
                                "-separator" "\x1f"
                                (expand-file-name oltp-db-path)
                                sql)))
      (unless (eq status 0)
        (user-error "sqlite3 query failed (status %s) for %s"
                    status oltp-db-path)))
    (mapcar (lambda (line) (split-string line "\x1f"))
            (split-string (string-trim (buffer-string)) "\n" t))))

(defun oltp--sqlite-rows (sql)
  "Run SQL against `oltp-db-path' and return rows as lists of strings.
Uses the built-in sqlite library when available; otherwise falls
back to the sqlite3 command-line shell."
  (unless (file-readable-p oltp-db-path)
    (user-error "SQLite database not readable: %s" oltp-db-path))
  (cond
   ((and (fboundp 'sqlite-available-p)
         (sqlite-available-p)
         (fboundp 'sqlite-open))
    (oltp--sqlite-builtin-rows sql))
   ((executable-find "sqlite3")
    (oltp--sqlite-shell-rows sql))
   (t (user-error
       "No SQLite backend available; install sqlite3 or build Emacs with sqlite"))))

(defun oltp--safe-identifier (name)
  "Return NAME stripped of characters that are unsafe in a SQL identifier."
  (replace-regexp-in-string "[^A-Za-z0-9_]" "" name))

(defun oltp--detect-table ()
  "Return the name of a table in the database that has the project column."
  (let* ((tables (mapcar #'car
                         (oltp--sqlite-rows
                          "SELECT name FROM sqlite_master WHERE type='table';")))
         (col oltp-db-column)
         (match (cl-find-if
                 (lambda (tbl)
                   (let* ((safe (oltp--safe-identifier tbl))
                          (rows (oltp--sqlite-rows
                                 (format "PRAGMA table_info(\"%s\");" safe))))
                     (cl-some (lambda (r) (string= (nth 1 r) col)) rows)))
                 tables)))
    (or match
        (user-error
         "No table in %s has a column named %s"
         oltp-db-path oltp-db-column))))

(defun oltp--project-names ()
  "Return a sorted, de-duplicated list of project names from the database."
  (let* ((table (or oltp-db-table (oltp--detect-table)))
         (safe-table (oltp--safe-identifier table))
         (safe-col (oltp--safe-identifier oltp-db-column))
         (sql (format
               (concat "SELECT DISTINCT \"%s\" FROM \"%s\" "
                       "WHERE \"%s\" IS NOT NULL AND \"%s\" <> '' "
                       "ORDER BY \"%s\";")
               safe-col safe-table safe-col safe-col safe-col)))
    (mapcar #'car (oltp--sqlite-rows sql))))

(defun oltp--read-project ()
  "Read a project name with `completing-read'."
  (let ((names (oltp--project-names)))
    (unless names
      (user-error "No projects found in %s" oltp-db-path))
    (completing-read "Project: " names nil t)))

(defun oltp--sanitize-tag (name)
  "Sanitize NAME so it can be used as an Org tag.
Org tag characters are limited to letters, digits, underscore,
at-sign, and percent.  Other characters become an underscore."
  (replace-regexp-in-string "[^A-Za-z0-9_@%]" "_" name))

(defun oltp--project-to-tag (project)
  "Convert PROJECT into an Org-safe tag.
When `oltp-tag-use-basename' is non-nil, only the file-name
portion of PROJECT is used."
  (let ((raw (if oltp-tag-use-basename
                 (file-name-nondirectory (directory-file-name project))
               project)))
    (oltp--sanitize-tag raw)))

;;; ---------------------------------------------------------------------------
;;; Tagging
;;; ---------------------------------------------------------------------------

;;;###autoload
(defun oltp-add-project-tag ()
  "Append a project tag to the current Org headline.
The project name is read from the SQLite database referenced by
`oltp-db-path' through `completing-read', sanitized into an
Org-compatible tag, and added through `org-set-tags' so that the
existing tag alignment and tag block formatting are respected."
  (interactive)
  (unless (oltp--at-headline-p)
    (user-error "Not on an org headline"))
  (let* ((project (oltp--read-project))
         (tag (and project
                   (not (string-empty-p project))
                   (oltp--project-to-tag project))))
    (when (and tag (not (string-empty-p tag)))
      (save-excursion
        (org-back-to-heading t)
        (let ((existing (org-get-tags nil t)))
          (unless (member tag existing)
            (org-set-tags (append existing (list tag)))))))))

;;;###autoload
(defun oltp-tag-region (beg end)
  "Walk the region and prompt for a project tag once per `**+' headline.
Lines that are not headlines are skipped."
  (interactive "r")
  (let ((end-marker (copy-marker end t)))
    (save-excursion
      (goto-char beg)
      (while (< (point) (marker-position end-marker))
        (when (oltp--at-headline-p)
          (oltp-add-project-tag))
        (forward-line 1))
      (set-marker end-marker nil))))

;;; ---------------------------------------------------------------------------
;;; tasks.org management
;;; ---------------------------------------------------------------------------

;;;###autoload
(defun oltp-init-tasks-file (&optional force)
  "Create the tasks.org file at `oltp-tasks-file'.
The file is written with the top-level headlines from
`oltp-tasks-file-headlines' in order.  With prefix arg FORCE, an
existing file is overwritten; otherwise the command signals an
error if the file already exists."
  (interactive "P")
  (let ((file (expand-file-name oltp-tasks-file)))
    (when (and (file-exists-p file) (not force))
      (user-error "Tasks file already exists: %s (call with prefix to overwrite)"
                  file))
    (let ((dir (file-name-directory file)))
      (when dir
        (make-directory dir t)))
    (with-temp-file file
      (insert "#+TITLE: Tasks\n")
      (insert "#+STARTUP: showall\n")
      (insert "#+LaTeX_HEADER: \\usepackage[margin=0.5in]{geometry}\n")
      (insert "\n")
      (dolist (hl oltp-tasks-file-headlines)
        (insert "* " hl "\n\n")))
    (message "Wrote %s" file)
    file))

(defun oltp--schedule-current-heading (time)
  "Set SCHEDULED on the current heading to TIME, replacing any prior schedule."
  (save-excursion
    (org-back-to-heading t)
    (org-schedule nil time)))

;;;###autoload
(defun oltp-schedule-tasks-file ()
  "Walk `oltp-tasks-file' and add a SCHEDULED line under each `** TODO'.
The SCHEDULED date comes from the function associated with the
parent `*' section in `oltp-section-date-functions'.  Sections
that do not have a function mapping are skipped silently.
Existing SCHEDULED lines are replaced so the command is safe to
re-run."
  (interactive)
  (let ((file (expand-file-name oltp-tasks-file)))
    (unless (file-readable-p file)
      (user-error "Tasks file not readable: %s" file))
    (with-current-buffer (find-file-noselect file)
      (save-excursion
        (goto-char (point-min))
        (let ((current-section nil))
          (while (re-search-forward "^\\(\\*+\\)[ \t]+\\(.*\\)$" nil t)
            (let* ((stars (match-string 1))
                   (title (match-string 2))
                   (level (length stars)))
              (cond
               ((= level 1)
                (setq current-section
                      (replace-regexp-in-string "[ \t]+\\'" "" title)))
               ((and (= level 2)
                     current-section
                     (string-match-p
                      (concat "\\`"
                              (regexp-quote oltp-org-todo-keyword)
                              "\\b")
                      title))
                (let ((date (oltp--date-for-section current-section)))
                  (when date
                    (oltp--schedule-current-heading date)))))))))
      (save-buffer))
    (message "Scheduled TODOs in %s" file)))

;;;###autoload
(defun oltp-prioritize-and-schedule-tasks-file ()
  "Convenience command that schedules every TODO in `oltp-tasks-file'.
Prioritization remains a manual, region-based operation because
priority groups follow blank-line breaks rather than the parent
section.  This command only assigns SCHEDULED dates."
  (interactive)
  (oltp-schedule-tasks-file))

(provide 'org-todo-letter-number-priorities)
;;; org-todo-letter-number-priorities.el ends here

;;; org-todo-letter-number-priorities-tests.el --- ERT tests -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Blaine Mooers

;; Author: Blaine Mooers <blaine-mooers@ou.edu>
;; Keywords: tests
;; Package-Requires: ((emacs "27.1") (org "9.3"))

;;; Commentary:

;; Comprehensive ERT tests for org-todo-letter-number-priorities.
;;
;; Run with:
;;
;;   make test
;;
;; or directly:
;;
;;   emacs -Q --batch -L . \
;;       -l org-todo-letter-number-priorities.el \
;;       -l org-todo-letter-number-priorities-tests.el \
;;       -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'org)

(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name "." dir)))

(require 'org-todo-letter-number-priorities)

;;; -------------------------- helpers ---------------------------------------

(defmacro oltp-tests--with-buffer (input &rest body)
  "Insert INPUT into a temp buffer in `org-mode', run BODY, return string."
  (declare (indent 1) (debug t))
  `(with-temp-buffer
     (delay-mode-hooks (org-mode))
     (insert ,input)
     (goto-char (point-min))
     ,@body
     (buffer-substring-no-properties (point-min) (point-max))))

(defun oltp-tests--reference-time ()
  "Return a fixed Emacs time for date-helper tests: 2026-05-16."
  (encode-time 0 0 12 16 5 2026))

(defmacro oltp-tests--at-reference-time (&rest body)
  "Run BODY with `current-time' returning a fixed test moment."
  (declare (indent 0) (debug t))
  `(cl-letf (((symbol-function 'current-time)
              #'oltp-tests--reference-time))
     ,@body))

(defun oltp-tests--sqlite-available-p ()
  "Return non-nil when any SQLite backend can be used."
  (or (and (fboundp 'sqlite-available-p)
           (sqlite-available-p)
           (fboundp 'sqlite-open))
      (executable-find "sqlite3")))

(defun oltp-tests--make-project-db (path)
  "Create a tiny projects database at PATH."
  (when (file-exists-p path) (delete-file path))
  (cond
   ((and (fboundp 'sqlite-available-p)
         (sqlite-available-p)
         (fboundp 'sqlite-open))
    (let ((db (sqlite-open path)))
      (unwind-protect
          (progn
            (sqlite-execute
             db
             (concat "CREATE TABLE projects ("
                     "id INTEGER PRIMARY KEY, "
                     "ProjectDirectory TEXT);"))
            (dolist (val '("/p/zeta" "/p/alpha" "/p/beta" "/p/alpha"))
              (sqlite-execute
               db
               "INSERT INTO projects(ProjectDirectory) VALUES (?);"
               (list val))))
        (sqlite-close db))))
   ((executable-find "sqlite3")
    (call-process
     "sqlite3" nil nil nil path
     (concat "CREATE TABLE projects ("
             "id INTEGER PRIMARY KEY, "
             "ProjectDirectory TEXT);"
             "INSERT INTO projects(ProjectDirectory) VALUES "
             "('/p/zeta'),"
             "('/p/alpha'),"
             "('/p/beta'),"
             "('/p/alpha');")))
   (t (error "No SQLite backend"))))

;;; -------------------------- strip -----------------------------------------

(ert-deftest oltp-test-strip-removes-cookie-keeps-todo ()
  (should
   (equal
    (oltp-tests--with-buffer "** TODO [A1] task one\n** TODO [B2] task two"
      (oltp-strip-region (point-min) (point-max)))
    "** TODO task one\n** TODO task two")))

(ert-deftest oltp-test-strip-removes-cookie-without-todo ()
  (should
   (equal
    (oltp-tests--with-buffer "** [A1] task"
      (oltp-strip-region (point-min) (point-max)))
    "** task")))

(ert-deftest oltp-test-strip-noop-when-no-cookie ()
  (let ((input "** TODO plain\n** another plain"))
    (should
     (equal
      (oltp-tests--with-buffer input
        (oltp-strip-region (point-min) (point-max)))
      input))))

(ert-deftest oltp-test-strip-preserves-non-headline-lines ()
  (should
   (equal
    (oltp-tests--with-buffer
        "** TODO [A1] task\nSCHEDULED: <2026-05-16>\nbody text"
      (oltp-strip-region (point-min) (point-max)))
    "** TODO task\nSCHEDULED: <2026-05-16>\nbody text")))

(ert-deftest oltp-test-strip-handles-three-star ()
  (should
   (equal
    (oltp-tests--with-buffer "*** TODO [C44] deep"
      (oltp-strip-region (point-min) (point-max)))
    "*** TODO deep")))

(ert-deftest oltp-test-strip-empty-region ()
  (should
   (equal
    (oltp-tests--with-buffer ""
      (oltp-strip-region (point-min) (point-max)))
    "")))

(ert-deftest oltp-test-strip-removes-asterisks-with-cookie ()
  "Asterisks live inside the cookie, so strip removes them too."
  (should
   (equal
    (oltp-tests--with-buffer
        "** TODO [A1***] urgent\n** TODO [B2*] less urgent"
      (oltp-strip-region (point-min) (point-max)))
    "** TODO urgent\n** TODO less urgent")))

;;; -------------------------- prioritize ------------------------------------

(ert-deftest oltp-test-prioritize-single-group ()
  (should
   (equal
    (oltp-tests--with-buffer "** first\n** second\n** third"
      (oltp-prioritize-region (point-min) (point-max)))
    "** TODO [A1] first\n** TODO [A2] second\n** TODO [A3] third")))

(ert-deftest oltp-test-prioritize-multiple-groups ()
  (should
   (equal
    (oltp-tests--with-buffer
        "** first\n** second\n\n** third\n\n** fourth"
      (oltp-prioritize-region (point-min) (point-max)))
    (concat "** TODO [A1] first\n"
            "** TODO [A2] second\n"
            "\n"
            "** TODO [B1] third\n"
            "\n"
            "** TODO [C1] fourth"))))

(ert-deftest oltp-test-prioritize-preserves-body-lines ()
  "SCHEDULED and body lines do not break or consume a priority slot."
  (should
   (equal
    (oltp-tests--with-buffer
        "** first\nSCHEDULED: <2026-05-16>\n** second"
      (oltp-prioritize-region (point-min) (point-max)))
    (concat "** TODO [A1] first\n"
            "SCHEDULED: <2026-05-16>\n"
            "** TODO [A2] second"))))

(ert-deftest oltp-test-prioritize-idempotent ()
  (let* ((input "** first\n** second\n\n** third")
         (once (oltp-tests--with-buffer input
                 (oltp-prioritize-region (point-min) (point-max))))
         (twice (oltp-tests--with-buffer once
                  (oltp-prioritize-region (point-min) (point-max)))))
    (should (equal once twice))))

(ert-deftest oltp-test-prioritize-replaces-existing-cookies ()
  (should
   (equal
    (oltp-tests--with-buffer
        "** TODO [Z9] stale\n** TODO [Z8] stale two"
      (oltp-prioritize-region (point-min) (point-max)))
    "** TODO [A1] stale\n** TODO [A2] stale two")))

(ert-deftest oltp-test-prioritize-adds-todo-when-missing ()
  (should
   (equal
    (oltp-tests--with-buffer
        "** plain task\n** TODO already keyword"
      (oltp-prioritize-region (point-min) (point-max)))
    "** TODO [A1] plain task\n** TODO [A2] already keyword")))

(ert-deftest oltp-test-prioritize-three-star ()
  (should
   (equal
    (oltp-tests--with-buffer "*** sub one\n*** sub two"
      (oltp-prioritize-region (point-min) (point-max)))
    "*** TODO [A1] sub one\n*** TODO [A2] sub two")))

(ert-deftest oltp-test-prioritize-preserves-asterisks ()
  "Existing asterisks survive renumbering."
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "** TODO [Z9**] urgent thing\n"
                "** TODO [Z8] normal thing\n"
                "** TODO [Z7***] very urgent thing")
      (oltp-prioritize-region (point-min) (point-max)))
    (concat "** TODO [A1**] urgent thing\n"
            "** TODO [A2] normal thing\n"
            "** TODO [A3***] very urgent thing"))))

(ert-deftest oltp-test-prioritize-preserves-asterisks-across-groups ()
  "Asterisks survive renumbering across blank-line group boundaries."
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "** TODO [X1*] one\n"
                "** TODO [X2**] two\n"
                "\n"
                "** TODO [Y1***] three")
      (oltp-prioritize-region (point-min) (point-max)))
    (concat "** TODO [A1*] one\n"
            "** TODO [A2**] two\n"
            "\n"
            "** TODO [B1***] three"))))

(ert-deftest oltp-test-prioritize-does-not-invent-asterisks ()
  "A headline without asterisks does not gain any."
  (should
   (equal
    (oltp-tests--with-buffer "** plain one\n** plain two"
      (oltp-prioritize-region (point-min) (point-max)))
    "** TODO [A1] plain one\n** TODO [A2] plain two")))

;;; -------------------------- headline parsing ------------------------------

(ert-deftest oltp-test-current-headline-priority-cookie ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "** TODO [A1] task")
    (goto-char (point-min))
    (should (equal (oltp--current-headline-priority) '("A" 0 1)))))

(ert-deftest oltp-test-current-headline-priority-bare ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "** TODO task")
    (goto-char (point-min))
    (should (null (oltp--current-headline-priority)))))

(ert-deftest oltp-test-current-headline-priority-three-star ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "*** TODO [C44] deep")
    (goto-char (point-min))
    (should (equal (oltp--current-headline-priority) '("C" 0 44)))))

(ert-deftest oltp-test-current-headline-priority-with-asterisks ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "** TODO [A1**] urgent task")
    (goto-char (point-min))
    (should (equal (oltp--current-headline-priority) '("A" 2 1)))))

(ert-deftest oltp-test-current-headline-asterisks ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "** TODO [A1***] task")
    (goto-char (point-min))
    (should (equal (oltp--current-headline-asterisks) "***"))))

(ert-deftest oltp-test-current-headline-asterisks-empty ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "** TODO [A1] task")
    (goto-char (point-min))
    (should (equal (oltp--current-headline-asterisks) ""))))

;;; -------------------------- priority compare ------------------------------

(ert-deftest oltp-test-priority-sort-cmp-basic ()
  (should (< (oltp--priority-sort-cmp '("A" 0 1) '("A" 0 2)) 0))
  (should (= (oltp--priority-sort-cmp '("A" 0 1) '("A" 0 1)) 0))
  (should (> (oltp--priority-sort-cmp '("B" 0 1) '("A" 0 99)) 0))
  (should (< (oltp--priority-sort-cmp '("A" 0 99) '("B" 0 1)) 0))
  (should (> (oltp--priority-sort-cmp nil '("A" 0 1)) 0))
  (should (< (oltp--priority-sort-cmp '("A" 0 1) nil) 0))
  (should (= (oltp--priority-sort-cmp nil nil) 0)))

(ert-deftest oltp-test-priority-sort-cmp-asterisks-outrank-plain ()
  "Asterisk-bearing cookies outrank same-letter cookies without."
  (should (< (oltp--priority-sort-cmp '("A" 1 9) '("A" 0 1)) 0))
  (should (< (oltp--priority-sort-cmp '("A" 3 5) '("A" 0 1)) 0))
  (should (> (oltp--priority-sort-cmp '("A" 0 1) '("A" 1 9)) 0)))

(ert-deftest oltp-test-priority-sort-cmp-more-asterisks-win ()
  "More asterisks outrank fewer asterisks within the same letter."
  (should (< (oltp--priority-sort-cmp '("A" 3 1) '("A" 2 1)) 0))
  (should (< (oltp--priority-sort-cmp '("A" 2 1) '("A" 1 1)) 0))
  (should (> (oltp--priority-sort-cmp '("A" 1 1) '("A" 2 1)) 0)))

(ert-deftest oltp-test-priority-sort-cmp-letter-beats-asterisks ()
  "A letter difference always dominates the asterisk count."
  (should (< (oltp--priority-sort-cmp '("A" 0 1) '("B" 5 1)) 0))
  (should (> (oltp--priority-sort-cmp '("B" 5 1) '("A" 0 1)) 0)))

(ert-deftest oltp-test-priority-sort-cmp-number-tiebreaks-equal-asterisks ()
  "Within the same letter and asterisk count, smaller number wins."
  (should (< (oltp--priority-sort-cmp '("A" 1 1) '("A" 1 2)) 0))
  (should (> (oltp--priority-sort-cmp '("A" 1 10) '("A" 1 2)) 0)))

;;; -------------------------- sort ------------------------------------------

(ert-deftest oltp-test-sort-moves-subtrees-as-units ()
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "** TODO [B1] beta\nbody of beta\n"
                "** TODO [A1] alpha\nbody of alpha\n")
      (oltp-sort-region (point-min) (point-max)))
    (concat "** TODO [A1] alpha\nbody of alpha\n"
            "** TODO [B1] beta\nbody of beta\n"))))

(ert-deftest oltp-test-sort-handles-multi-digit-y ()
  (should
   (equal
    (oltp-tests--with-buffer
        "** TODO [C10] ten\n** TODO [C2] two\n** TODO [C100] hundred"
      (oltp-sort-region (point-min) (point-max)))
    "** TODO [C2] two\n** TODO [C10] ten\n** TODO [C100] hundred")))

(ert-deftest oltp-test-sort-keeps-section-headlines-in-place ()
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "* Do it today\n"
                "** TODO [A2] today two\n"
                "** TODO [A1] today one\n"
                "* Do it this week\n"
                "** TODO [B2] week two\n"
                "** TODO [B1] week one\n")
      (oltp-sort-region (point-min) (point-max)))
    (concat "* Do it today\n"
            "** TODO [A1] today one\n"
            "** TODO [A2] today two\n"
            "* Do it this week\n"
            "** TODO [B1] week one\n"
            "** TODO [B2] week two\n"))))

(ert-deftest oltp-test-sort-uncookied-go-last-stable ()
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "** plain one\n"
                "** TODO [A2] alpha two\n"
                "** TODO [A1] alpha one\n"
                "** plain two\n")
      (oltp-sort-region (point-min) (point-max)))
    (concat "** TODO [A1] alpha one\n"
            "** TODO [A2] alpha two\n"
            "** plain one\n"
            "** plain two\n"))))

(ert-deftest oltp-test-sort-keeps-preamble ()
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "* Top section\n"
                "some intro\n"
                "** TODO [B1] beta\n"
                "** TODO [A1] alpha\n")
      (oltp-sort-region (point-min) (point-max)))
    (concat "* Top section\n"
            "some intro\n"
            "** TODO [A1] alpha\n"
            "** TODO [B1] beta\n"))))

(ert-deftest oltp-test-sort-more-asterisks-go-first-within-letter ()
  "Within group A, more asterisks comes first."
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "** TODO [A1] plain\n"
                "** TODO [A2*] one star\n"
                "** TODO [A3***] three stars\n"
                "** TODO [A4**] two stars\n")
      (oltp-sort-region (point-min) (point-max)))
    (concat "** TODO [A3***] three stars\n"
            "** TODO [A4**] two stars\n"
            "** TODO [A2*] one star\n"
            "** TODO [A1] plain\n"))))

(ert-deftest oltp-test-sort-asterisk-items-outrank-plain-same-letter ()
  "Any asterisk-bearing A item sorts above every plain A item."
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "** TODO [A1] plain one\n"
                "** TODO [A2] plain two\n"
                "** TODO [A99*] urgent low rank\n")
      (oltp-sort-region (point-min) (point-max)))
    (concat "** TODO [A99*] urgent low rank\n"
            "** TODO [A1] plain one\n"
            "** TODO [A2] plain two\n"))))

(ert-deftest oltp-test-sort-letter-still-dominates-asterisks ()
  "A letter difference dominates asterisk count."
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "** TODO [B1***] b with stars\n"
                "** TODO [A1] plain a\n")
      (oltp-sort-region (point-min) (point-max)))
    (concat "** TODO [A1] plain a\n"
            "** TODO [B1***] b with stars\n"))))

(ert-deftest oltp-test-sort-number-tiebreaks-equal-asterisks ()
  "Same letter, same asterisk count: smaller number first."
  (should
   (equal
    (oltp-tests--with-buffer
        (concat "** TODO [A5**] five\n"
                "** TODO [A1**] one\n"
                "** TODO [A3**] three\n")
      (oltp-sort-region (point-min) (point-max)))
    (concat "** TODO [A1**] one\n"
            "** TODO [A3**] three\n"
            "** TODO [A5**] five\n"))))

;;; -------------------------- date helpers ----------------------------------

(ert-deftest oltp-test-days-hence ()
  (oltp-tests--at-reference-time
    (let* ((d (oltp--days-hence 6))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2026))
      (should (= (nth 4 dec) 5))
      (should (= (nth 3 dec) 22)))))

(ert-deftest oltp-test-months-hence-simple ()
  (oltp-tests--at-reference-time
    (let* ((d (oltp--months-hence 2))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2026))
      (should (= (nth 4 dec) 7))
      (should (= (nth 3 dec) 16)))))

(ert-deftest oltp-test-months-hence-crosses-year ()
  (oltp-tests--at-reference-time
    (let* ((d (oltp--months-hence 8))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2027))
      (should (= (nth 4 dec) 1))
      (should (= (nth 3 dec) 16)))))

(ert-deftest oltp-test-months-hence-clamps-day ()
  "January 31 + 1 month clamps to February 28 to avoid overflow."
  (cl-letf (((symbol-function 'current-time)
             (lambda () (encode-time 0 0 12 31 1 2026))))
    (let* ((d (oltp--months-hence 1))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2026))
      (should (= (nth 4 dec) 2))
      (should (= (nth 3 dec) 28)))))

(ert-deftest oltp-test-end-of-current-month-may ()
  (oltp-tests--at-reference-time
    (let* ((d (oltp--end-of-current-month))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2026))
      (should (= (nth 4 dec) 5))
      (should (= (nth 3 dec) 31)))))

(ert-deftest oltp-test-end-of-current-month-feb-leap ()
  (cl-letf (((symbol-function 'current-time)
             (lambda () (encode-time 0 0 12 5 2 2024))))
    (let* ((d (oltp--end-of-current-month))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2024))
      (should (= (nth 4 dec) 2))
      (should (= (nth 3 dec) 29)))))

(ert-deftest oltp-test-first-of-next-month ()
  (oltp-tests--at-reference-time
    (let* ((d (oltp--first-of-next-month))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2026))
      (should (= (nth 4 dec) 6))
      (should (= (nth 3 dec) 1)))))

(ert-deftest oltp-test-first-of-next-month-december-wraps ()
  (cl-letf (((symbol-function 'current-time)
             (lambda () (encode-time 0 0 12 16 12 2026))))
    (let* ((d (oltp--first-of-next-month))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2027))
      (should (= (nth 4 dec) 1))
      (should (= (nth 3 dec) 1)))))

(ert-deftest oltp-test-first-of-next-year ()
  (oltp-tests--at-reference-time
    (let* ((d (oltp--first-of-next-year))
           (dec (decode-time d)))
      (should (= (nth 5 dec) 2027))
      (should (= (nth 4 dec) 1))
      (should (= (nth 3 dec) 1)))))

(ert-deftest oltp-test-date-for-section-known ()
  (oltp-tests--at-reference-time
    (should (oltp--date-for-section "Do it today"))
    (should (oltp--date-for-section "Do it next year"))))

(ert-deftest oltp-test-date-for-section-unknown ()
  (should (null (oltp--date-for-section "Nonexistent section"))))

;;; -------------------------- init tasks file -------------------------------

(ert-deftest oltp-test-init-tasks-file-creates ()
  (let* ((tmpdir (make-temp-file "oltp-test-" t))
         (path (expand-file-name "tasks.org" tmpdir)))
    (unwind-protect
        (let ((oltp-tasks-file path))
          (oltp-init-tasks-file)
          (should (file-readable-p path))
          (let ((contents (with-temp-buffer
                            (insert-file-contents path)
                            (buffer-string))))
            (dolist (hl oltp-tasks-file-headlines)
              (should (string-match-p
                       (concat "^\\* " (regexp-quote hl) "$")
                       contents)))
            (should (string-match-p "#\\+TITLE: Tasks" contents))))
      (when (file-exists-p path) (delete-file path))
      (delete-directory tmpdir t))))

(ert-deftest oltp-test-init-tasks-file-errors-when-present ()
  (let* ((tmpdir (make-temp-file "oltp-test-" t))
         (path (expand-file-name "tasks.org" tmpdir)))
    (unwind-protect
        (let ((oltp-tasks-file path))
          (write-region "" nil path)
          (should-error (oltp-init-tasks-file) :type 'user-error))
      (when (file-exists-p path) (delete-file path))
      (delete-directory tmpdir t))))

(ert-deftest oltp-test-init-tasks-file-overwrites-with-force ()
  (let* ((tmpdir (make-temp-file "oltp-test-" t))
         (path (expand-file-name "tasks.org" tmpdir)))
    (unwind-protect
        (let ((oltp-tasks-file path))
          (write-region "stale content" nil path)
          (oltp-init-tasks-file t)
          (let ((contents (with-temp-buffer
                            (insert-file-contents path)
                            (buffer-string))))
            (should-not (string-match-p "stale content" contents))
            (should (string-match-p "Do it today" contents))))
      (when (file-exists-p path) (delete-file path))
      (delete-directory tmpdir t))))

;;; -------------------------- tag helpers -----------------------------------

(ert-deftest oltp-test-sanitize-tag ()
  (should (equal (oltp--sanitize-tag "my-project") "my_project"))
  (should (equal (oltp--sanitize-tag "fine_tag_42") "fine_tag_42"))
  (should (equal (oltp--sanitize-tag "spaces and / slashes")
                 "spaces_and___slashes"))
  (should (equal (oltp--sanitize-tag "ok@user%name") "ok@user%name")))

(ert-deftest oltp-test-project-to-tag-basename ()
  (let ((oltp-tag-use-basename t))
    (should (equal (oltp--project-to-tag "/home/blaine/4585orgTodoLNP")
                   "4585orgTodoLNP"))
    (should (equal (oltp--project-to-tag "/home/blaine/4585orgTodoLNP/")
                   "4585orgTodoLNP"))))

(ert-deftest oltp-test-project-to-tag-full-path ()
  (let ((oltp-tag-use-basename nil))
    (should (equal (oltp--project-to-tag "/home/blaine/projA")
                   "_home_blaine_projA"))))

;;; -------------------------- SQLite project lookup -------------------------

(ert-deftest oltp-test-sqlite-project-names-sorted-and-deduped ()
  (skip-unless (oltp-tests--sqlite-available-p))
  (let ((db (make-temp-file "oltp-test-" nil ".db")))
    (unwind-protect
        (progn
          (oltp-tests--make-project-db db)
          (let ((oltp-db-path db)
                (oltp-db-table nil)
                (oltp-db-column "ProjectDirectory"))
            (should (equal (oltp--project-names)
                           '("/p/alpha" "/p/beta" "/p/zeta")))))
      (when (file-exists-p db) (delete-file db)))))

(ert-deftest oltp-test-sqlite-detect-table ()
  (skip-unless (oltp-tests--sqlite-available-p))
  (let ((db (make-temp-file "oltp-test-" nil ".db")))
    (unwind-protect
        (progn
          (oltp-tests--make-project-db db)
          (let ((oltp-db-path db)
                (oltp-db-table nil)
                (oltp-db-column "ProjectDirectory"))
            (should (equal (oltp--detect-table) "projects"))))
      (when (file-exists-p db) (delete-file db)))))

(ert-deftest oltp-test-sqlite-explicit-table-overrides-detection ()
  (skip-unless (oltp-tests--sqlite-available-p))
  (let ((db (make-temp-file "oltp-test-" nil ".db")))
    (unwind-protect
        (progn
          (oltp-tests--make-project-db db)
          (let ((oltp-db-path db)
                (oltp-db-table "projects")
                (oltp-db-column "ProjectDirectory"))
            (should (equal (oltp--project-names)
                           '("/p/alpha" "/p/beta" "/p/zeta")))))
      (when (file-exists-p db) (delete-file db)))))

(ert-deftest oltp-test-sqlite-missing-database-signals ()
  (let ((oltp-db-path "/nonexistent/path/oltp-missing.db"))
    (should-error (oltp--project-names) :type 'user-error)))

;;; -------------------------- add-project-tag -------------------------------

(ert-deftest oltp-test-add-project-tag-errors-outside-headline ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "no headline here")
    (goto-char (point-min))
    (cl-letf (((symbol-function 'oltp--read-project)
               (lambda () "/p/whatever")))
      (should-error (oltp-add-project-tag) :type 'user-error))))

(ert-deftest oltp-test-add-project-tag-appends-tag ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "** TODO [A1] do dishes\n")
    (goto-char (point-min))
    (cl-letf (((symbol-function 'oltp--read-project)
               (lambda () "/home/blaine/kitchen")))
      (oltp-add-project-tag))
    (should (string-match-p ":kitchen:" (buffer-string)))))

(ert-deftest oltp-test-add-project-tag-merges-with-existing ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "** TODO [A1] mow lawn :home:\n")
    (goto-char (point-min))
    (cl-letf (((symbol-function 'oltp--read-project)
               (lambda () "/home/blaine/garden")))
      (oltp-add-project-tag))
    (let ((line (buffer-substring-no-properties
                 (point-min) (line-end-position))))
      (should (string-match-p ":home:" line))
      (should (string-match-p ":garden:" line)))))

(ert-deftest oltp-test-add-project-tag-idempotent ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert "** TODO [A1] mow lawn :garden:\n")
    (goto-char (point-min))
    (cl-letf (((symbol-function 'oltp--read-project)
               (lambda () "/home/blaine/garden")))
      (oltp-add-project-tag)
      (oltp-add-project-tag))
    (let* ((line (buffer-substring-no-properties
                  (point-min) (line-end-position)))
           (count 0)
           (start 0))
      (while (string-match ":garden:" line start)
        (setq count (1+ count))
        (setq start (match-end 0)))
      (should (= count 1)))))

;;; -------------------------- schedule tasks file ---------------------------

(ert-deftest oltp-test-schedule-tasks-file-adds-scheduled ()
  (let* ((tmpdir (make-temp-file "oltp-test-" t))
         (path (expand-file-name "tasks.org" tmpdir)))
    (unwind-protect
        (let ((oltp-tasks-file path))
          (with-temp-file path
            (insert "* Do it today\n")
            (insert "** TODO [A1] something\n")
            (insert "* Do it next year\n")
            (insert "** TODO [A1] long-term thing\n"))
          (oltp-tests--at-reference-time
            (oltp-schedule-tasks-file))
          (let ((contents (with-temp-buffer
                            (insert-file-contents path)
                            (buffer-string))))
            (should (string-match-p
                     "\\*\\* TODO \\[A1\\] something\\(.\\|\n\\)*SCHEDULED: <2026-05-16"
                     contents))
            (should (string-match-p
                     "\\*\\* TODO \\[A1\\] long-term thing\\(.\\|\n\\)*SCHEDULED: <2027-01-01"
                     contents))))
      (when (file-exists-p path) (delete-file path))
      (when (file-exists-p (concat path "~"))
        (delete-file (concat path "~")))
      (delete-directory tmpdir t))))

(ert-deftest oltp-test-schedule-tasks-file-skips-unknown-section ()
  (let* ((tmpdir (make-temp-file "oltp-test-" t))
         (path (expand-file-name "tasks.org" tmpdir)))
    (unwind-protect
        (let ((oltp-tasks-file path))
          (with-temp-file path
            (insert "* Some weird section\n")
            (insert "** TODO [A1] orphan\n"))
          (oltp-schedule-tasks-file)
          (let ((contents (with-temp-buffer
                            (insert-file-contents path)
                            (buffer-string))))
            (should-not (string-match-p "SCHEDULED:" contents))))
      (when (file-exists-p path) (delete-file path))
      (when (file-exists-p (concat path "~"))
        (delete-file (concat path "~")))
      (delete-directory tmpdir t))))

;;; -------------------------- tag-region ------------------------------------

(ert-deftest oltp-test-tag-region-prompts-per-headline ()
  (with-temp-buffer
    (delay-mode-hooks (org-mode))
    (insert (concat "** TODO [A1] one\n"
                    "body line, not a headline\n"
                    "** TODO [A2] two\n"))
    (let ((calls 0)
          (projects '("/p/alpha" "/p/beta")))
      (cl-letf (((symbol-function 'oltp--read-project)
                 (lambda ()
                   (prog1 (nth calls projects)
                     (setq calls (1+ calls))))))
        (oltp-tag-region (point-min) (point-max)))
      (should (= calls 2))
      ;; `org-set-tags' pads with alignment whitespace, so allow any
      ;; amount of whitespace between the title and the tag block.
      (should (string-match-p "\\*\\* TODO \\[A1\\] one[ \t]+:alpha:"
                              (buffer-string)))
      (should (string-match-p "\\*\\* TODO \\[A2\\] two[ \t]+:beta:"
                              (buffer-string))))))

(provide 'org-todo-letter-number-priorities-tests)
;;; org-todo-letter-number-priorities-tests.el ends here

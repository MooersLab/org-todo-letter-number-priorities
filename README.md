![Version](https://img.shields.io/static/v1?label=org-todo-letter-number-priorities&message=0.1.0&color=brightcolor)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Emacs](https://img.shields.io/badge/Emacs-27.1%2B-purple.svg)](https://www.gnu.org/software/emacs/)
[![Made with Org](https://img.shields.io/badge/Made_with-Emacs_Lisp-7F5AB6.svg)](https://www.gnu.org/software/emacs/manual/html_node/elisp/index.html)

# org-todo-letter-number-priorities

Letter+number TODO priorities for Org-mode.

This package lets you mark, sort, and tag Org headlines with priority cookies of the form `TODO [XY]`, where `X` is an uppercase letter for the priority group and `Y` is a non-negative integer for the rank inside the group. A smaller `Y` means higher priority, so `[A1]` outranks `[A2]` which outranks `[A44]` which outranks `[B1]`. A prioritized Org headline looks like

```org
** TODO [A1] task description :tag:
```

A single space is required between the keyword `TODO` and the left square bracket.

The package is self-contained. It depends only on Emacs and Org. The optional project-tagging feature reads project names from a SQLite database you maintain for time tracking, using either Emacs's built-in `sqlite` library or the `sqlite3` command-line shell.

## Features

- Prioritize Org headlines across a region with `oltp-prioritize-region`. Blank lines separate priority groups, so the first contiguous block of headlines becomes `A1`, `A2`, `A3`, the next block becomes `B1`, `B2`, and so on. SCHEDULED lines and body text between headlines do not consume priority slots.
- Strip `[XY]` cookies with `oltp-strip-region`, leaving the `TODO` keyword in place.
- Sort `**+` subtrees by `[XY]` priority with `oltp-sort-region`. Subtrees move as units, so SCHEDULED lines and body text follow their headline. Level-1 `*` headlines stay in place as section boundaries.
- Tag a headline with a project from a SQLite database via `oltp-add-project-tag`. The tag merges into the existing Org tag list through `org-set-tags`.
- Scaffold `tasks.org` with `oltp-init-tasks-file`, pre-populated with eleven time-horizon sections.
- Apply SCHEDULED dates to every TODO in `tasks.org` with `oltp-schedule-tasks-file`, derived from each TODO's parent `*` section.

## Requirements

- Emacs 27.1 or newer
- Org 9.3 or newer
- For project tagging: either Emacs 29 or newer with `--with-sqlite3`, or the `sqlite3` command-line shell on `PATH`
- GNU Make and `makeinfo` to build the docs and install via the Makefile

## Installation

### Manual install with the Makefile

```sh
git clone https://github.com/blaine-mooers/org-todo-letter-number-priorities
cd org-todo-letter-number-priorities
make compile
make info
sudo make install
```

The default install paths are:

- Elisp: `/usr/local/share/emacs/site-lisp/org-todo-letter-number-priorities`
- Info: `/usr/local/share/info`

Override `PREFIX`, `ELISPDIR`, or `INFODIR` to install elsewhere. For a per-user install:

```sh
make install PREFIX=$HOME/.local
```

After install, add the install directory to `load-path` and require:

```elisp
(add-to-list 'load-path
  "/usr/local/share/emacs/site-lisp/org-todo-letter-number-priorities")
(require 'org-todo-letter-number-priorities)
```

### straight.el

```elisp
(straight-use-package
 '(org-todo-letter-number-priorities
   :type git
   :host github
   :repo "blaine-mooers/org-todo-letter-number-priorities"))
```

### use-package with straight

```elisp
(use-package org-todo-letter-number-priorities
  :straight (org-todo-letter-number-priorities
             :type git
             :host github
             :repo "MooersLab/org-todo-letter-number-priorities")
  :after org
  :commands (oltp-prioritize-region
             oltp-strip-region
             oltp-sort-region
             oltp-add-project-tag
             oltp-tag-region
             oltp-init-tasks-file
             oltp-schedule-tasks-file)
  :custom
  (oltp-tasks-file "~/org/tasks.org")
  (oltp-db-path "~/6003TimeTracking/cb/tenKprojects.db"))
```

## Configuration

```elisp
(setq oltp-tasks-file "~/org/tasks.org")
(setq oltp-db-path "~/60003TimeTracking/cb/tenKprojects.db")
;; Optional: pin the table name if auto-detection picks the wrong one.
;; (setq oltp-db-table "projects")
;; Optional: change the column the project picker reads from.
;; (setq oltp-db-column "ProjectDirectory")
;; Optional: customize the date function for one of the sections.
;; (setf (alist-get "Do it this week" oltp-section-date-functions nil nil #'equal)
;;       (lambda () (oltp--days-hence 4)))
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `oltp-tasks-file` | `~/tasks.org` | Path to the tasks.org file managed by this package |
| `oltp-tasks-file-headlines` | Eleven `Do it ...` headlines | Top-level headlines written by `oltp-init-tasks-file` |
| `oltp-org-todo-keyword` | `TODO` | Org keyword used in front of the priority cookie |
| `oltp-section-date-functions` | Reasonable defaults for each section | Alist mapping section name to a zero-arg function returning a time |
| `oltp-db-path` | `~/6003TimeTracking/cb/tenKprojects.db` | SQLite database read by the project picker |
| `oltp-db-table` | `nil` (auto-detect) | Table that holds project rows |
| `oltp-db-column` | `ProjectDirectory` | Column that holds project names |
| `oltp-tag-use-basename` | `t` | Use the basename of the project path for the tag |

### Suggested keybindings

```elisp
(define-key org-mode-map (kbd "C-c j p") #'oltp-prioritize-region)
(define-key org-mode-map (kbd "C-c j s") #'oltp-strip-region)
(define-key org-mode-map (kbd "C-c j o") #'oltp-sort-region)
(define-key org-mode-map (kbd "C-c j t") #'oltp-add-project-tag)
(define-key org-mode-map (kbd "C-c j T") #'oltp-tag-region)
(define-key org-mode-map (kbd "C-c j i") #'oltp-init-tasks-file)
(define-key org-mode-map (kbd "C-c j d") #'oltp-schedule-tasks-file)
```

## Usage

### One-time setup

```
M-x oltp-init-tasks-file
```

Creates `oltp-tasks-file` with the eleven standard headlines. With a prefix argument, the file is overwritten if it already exists.

### Add tasks under a section

Open `oltp-tasks-file` and type your tasks under the section that matches their time horizon, in descending order of priority. Use blank lines to separate priority groups inside the same section.

```org
* Do it today
** finish grant draft
** respond to reviewer email

** water plants
** unload dishwasher

* Do it this week
** read paper on DSDs
** book travel
```

### Prioritize the section you just typed

Select the region of `**` headlines under one section and run `M-x oltp-prioritize-region`. Each contiguous block of headlines gets the next letter; ranks restart at 1 inside each block.

```org
* Do it today
** TODO [A1] finish grant draft
** TODO [A2] respond to reviewer email

** TODO [B1] water plants
** TODO [B2] unload dishwasher
```

The command is idempotent. Strip and re-prioritize when the day changes.

### Sort a section

`M-x oltp-sort-region` re-orders subtrees by `[XY]` priority. Each subtree moves as a unit, so SCHEDULED lines and body text follow the headline.

If you select the whole file, level-1 `*` headlines stay in place as section boundaries and items inside each section sort independently.

### Apply SCHEDULED dates to every TODO

```
M-x oltp-schedule-tasks-file
```

Walks `oltp-tasks-file` and inserts (or replaces) a SCHEDULED line under each `** TODO`, using the parent `*` section's date function. Default mappings are:

| Section | SCHEDULED date |
| --- | --- |
| Do it today | today |
| Do it this week | today + 6 days |
| Do it next week | today + 13 days |
| Do it later this month | last day of this month |
| Do it next month | first day of next month |
| Do it in two months | today + 2 months (day clamped to 28) |
| Do it in three months | today + 3 months |
| Do it in four months | today + 4 months |
| Do it in five months | today + 5 months |
| Do it in six months | today + 6 months |
| Do it next year | January 1 of next year |

The command is safe to re-run; existing SCHEDULED lines are replaced rather than duplicated.

### Tag a TODO with its project

Place point on a `** TODO [XY]` headline and run `M-x oltp-add-project-tag`. The package reads the `ProjectDirectory` column from the SQLite database referenced by `oltp-db-path`, presents the values via `completing-read`, and inserts the chosen project as an Org tag through `org-set-tags`. Existing tags and the alignment column are preserved.

| Before | After (adding `garden`) |
| --- | --- |
| `** TODO [A1] mow lawn` | `** TODO [A1] mow lawn                                :garden:` |
| `** TODO [A1] mow lawn :home:` | `** TODO [A1] mow lawn                          :home:garden:` |
| `** TODO [A1] mow lawn :garden:` | unchanged (idempotent) |

To tag every headline in a region, run `M-x oltp-tag-region`.

### Strip cookies to re-prioritize tomorrow

```
M-x oltp-strip-region
```

removes every `[XY]` cookie from headlines in the region. The `TODO` keyword stays.

## SQLite database

The package expects a SQLite database with a column of project identifiers. The default schema is:

```sql
CREATE TABLE projects (
    id               INTEGER PRIMARY KEY,
    ProjectDirectory TEXT
);
```

The table name is not significant when `oltp-db-table` is `nil`. The package walks the schema and picks the first table whose columns include `oltp-db-column`. If you keep your projects in a different column, change `oltp-db-column`. If multiple tables contain that column, set `oltp-db-table` explicitly to pin detection.

Project names are de-duplicated and sorted before they are shown to `completing-read`.

## Documentation

A full Texinfo manual ships with the package:

```sh
make info     # produces org-todo-letter-number-priorities.info
make html     # produces org-todo-letter-number-priorities.html
```

Inside Emacs the manual is reachable through `C-h i` once installed.

## Testing

The ERT suite covers prioritization (single, multi-group, idempotent, replaces existing cookies, three-star), stripping (basic, no-TODO, no-op, preserves body, three-star, empty), headline parsing, priority comparison, sorting (subtree-aware moves, multi-digit Y, preamble, uncookied last, across multiple `*` sections), date helpers (including February in a leap year and December wrap-around), `oltp-init-tasks-file` (create + error + overwrite), the inlined SQLite project-name lookup (table auto-detection, explicit table override, sorted and de-duplicated names, missing database signals), `oltp-add-project-tag` (errors outside headline, append, merge, idempotent), `oltp-tag-region`, and `oltp-schedule-tasks-file` (known section, unknown section skipped).

```sh
make test
```

`oltp--read-project` is mocked in tag tests, while the SQLite tests build a temporary database with the `sqlite3` shell (or the built-in library) to exercise the project-names path end to end. Date helpers pin `current-time` to a fixed reference moment so the suite is deterministic.

## License

This package is licensed under the GNU General Public License, version 3 or later. See [LICENSE](LICENSE) for the full text.

The accompanying documentation is licensed under the GNU Free Documentation License, version 1.3 or later.

## Author

Blaine Mooers, Department of Biochemistry and Physiology, University of Oklahoma Health Campus.
Email: blaine-mooers@ou.edu

## Funding

- NIH: R01 CA242845, R01 AI088011
- NIH: P30 CA225520 (PI: R. Mannel); P30 GM145423 (PI: A. West)



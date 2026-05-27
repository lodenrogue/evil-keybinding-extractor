(defcustom my/config-file-location "~/.emacs.d/config.org"
  "The location of the org config file where keybindings can be found."
  :type 'string)

(defun my/extract-evil-leader-bindings ()
  "Parse the file set in `my/config-file-location' for `evil-leader/set-key` blocks.
Generates separate Org tables for each top-level heading in a new buffer."
  (interactive)
  (let* ((config-path (expand-file-name my/config-file-location))
         (output-buffer (get-buffer-create "*Evil Leader Bindings*"))
         (collected-data nil)) ; Structure: ((Heading1 . ((key . func) ...)) (Heading2 . (...)))

    (unless (file-exists-p config-path)
      (error "Configuration file not found at %s" config-path))

    ;; Step 1: Open and parse the specific configuration file
    (with-current-buffer (find-file-noselect config-path)
      (save-excursion
        (org-element-map (org-element-parse-buffer) 'src-block
          (lambda (src-block)
            (when (string= (org-element-property :language src-block) "emacs-lisp")
              (let* ((block-value (org-element-property :value src-block))
                     ;; Find the top-level heading this source block belongs to
                     (element-heading (save-excursion
                                        (goto-char (org-element-property :begin src-block))
                                        (let ((outline-regexp "^\\* "))
                                          (if (re-search-backward outline-regexp nil t)
                                              (org-get-heading t t t t)
                                            "Uncategorized")))))
                
                ;; Read forms from the source block string
                (with-temp-buffer
                  (insert block-value)
                  (goto-char (point-min))
                  (condition-case nil
                      (while (not (eobp))
                        (let ((form (read (current-buffer))))
                          ;; Check if the form is an evil-leader/set-key call
                          (when (and (listp form)
                                     (eq (car form) 'evil-leader/set-key))
                            (let ((args (cdr form))
                                  (bindings nil))
                              ;; Pair up the arguments (key function key function ...)
                              (while (>= (length args) 2)
                                (let ((key (car args))
                                      (func (cadr args))
                                      (func-str nil))
                                  ;; Strip the quote if the function is quoted (e.g., 'find-file or '(lambda ...))
                                  (when (and (listp func) (eq (car func) 'quote))
                                    (setq func (cadr func)))
                                  
                                  ;; Handle either symbol functions or lambda functions
                                  (cond
                                   ((symbolp func)
                                    (setq func-str (symbol-name func)))
                                   ((and (listp func) (eq (car func) 'lambda))
                                    (setq func-str (prin1-to-string func))))
                                  
                                  (when (and (stringp key) func-str)
                                    (push (cons key func-str) bindings)))
                                (setq args (cddr args)))
                              
                              ;; Append found bindings to the current heading's collection
                              (when bindings
                                (let ((existing (assoc element-heading collected-data)))
                                  (if existing
                                      (setcdr existing (append (cdr existing) (reverse bindings)))
                                    (push (cons element-heading (reverse bindings)) collected-data))))))))
                    (error nil)))))))))

    ;; Step 2: Write the collected data to the output buffer
    (with-current-buffer output-buffer
      (read-only-mode -1)
      (erase-buffer)
      (org-mode)
      
      (if (null collected-data)
          (insert "# No evil-leader/set-key bindings found.\n")
        
        (dolist (section (reverse collected-data))
          (let ((heading (car section))
                (bindings (cdr section)))
            ;; Insert heading
            (insert "* " heading "\n")
            ;; Insert table header
            (insert "| Keybinding | Function |\n")
            (insert "|------------+----------|\n")
            ;; Insert rows
            (dolist (binding bindings)
              (insert (format "| %s | %s |\n" (car binding) (cdr binding))))
            ;; Align the table
            (forward-line -1)
            (org-table-align)
            (goto-char (point-max)))))
      
      (goto-char (point-min)))
    
    ;; Switch to the output buffer
    (switch-to-buffer output-buffer)))

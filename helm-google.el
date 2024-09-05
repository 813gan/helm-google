;;; helm-google.el --- Emacs Helm Interface for quick Google searches -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2018, Steckerhalter
;;               2024,      813gan

;; Author: steckerhalter
;; Package: helm-google
;; Package-Requires: ((helm "0"))
;; URL: https://framagit.org/steckerhalter/helm-google
;; Keywords: helm google search browse searx
;; Version: 1.0

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Emacs Helm Interface for quick Google searches

;;; Code:

(require 'helm)
(require 'helm-net)
(require 'json)
(require 'cl-lib)

(defgroup helm-google '()
  "Customization group for `helm-google'."
  :link '(url-link "https://framagit.org/steckerhalter/helm-google")
  :group 'convenience
  :group 'comm)

(defcustom helm-google-default-engine 'searx
  "The default engine to use.
See `helm-google-engines' for available engines."
  :type 'symbol
  :group 'helm-google)

(defcustom helm-google-actions
  '(("Browse URL" . browse-url)
    ("Browse URL with EWW" . (lambda (candidate)
                               (eww-browse-url candidate)))
    ("Copy URL to clipboard" . (lambda (candidate)
                                 (kill-new  candidate)))
    ("Browse URL with webkit xwidget" . (lambda (candidate)
                                          (xwidget-webkit-browse-url candidate))))
  "List of actions for helm-google sources."
  :group 'helm-google
  :type '(alist :key-type string :value-type function))

(defcustom helm-google-engines
  '((google . "https://encrypted.google.com/search?ie=UTF-8&oe=UTF-8&q=%s")
    (searx . "https://metasearx.com/?format=json&q=%s")
    (brave . "https://api.search.brave.com/res/v1/web/search?q=%s")
    (stract . "https://stract.com/beta/api/search")
    )
  "Alist of search engines.
Each element is a cons-cell (ENGINE . URL).
`%s' is where the search terms are inserted in the URL."
  :group 'helm-google
  :type '(alist :key-type symbol :value-type string))

(defcustom helm-google-idle-delay 0.5
  "Time to wait when idle until query is made."
  :type 'integer
  :group 'helm-google)

(defcustom helm-google-user-agent
  "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0"
  "User agent to use.
g**gle may not work for some settings."
  :type 'string
  :group 'helm-google)

(defvar helm-google-input-history nil)
(defvar helm-google-pending-query nil)

(defvar helm-google-brave-api-key)

(defun helm-google--process-html (html)
  (replace-regexp-in-string
   "\n" ""
   (with-temp-buffer
     (insert html)
     (if (fboundp 'html2text)
         (html2text)
       (shr-render-region (point-min) (point-max)))
     (buffer-substring-no-properties (point-min) (point-max)))))

(defmacro helm-google--with-buffer (buf &rest body)
  (declare (doc-string 3) (indent 2))
  `(with-current-buffer ,buf
     (set-buffer-multibyte t)
     (goto-char url-http-end-of-headers)
     (prog1 ,@body
       (kill-buffer ,buf))))

(defun helm-google--parse-google (buf)
  "Parse the html response from Google."
  (helm-google--with-buffer buf
      (let (results result)
        (while (re-search-forward "class=\"kCrYT\"><a href=\"/url\\?q=\\(.*?\\)&amp;sa" nil t)
          (setq result (plist-put result :url (match-string-no-properties 1)))
          (re-search-forward "BNeawe vvjwJb AP7Wnd\">\\(.*?\\)</div>" nil t)
          (setq result (plist-put result :title (helm-google--process-html (match-string-no-properties 1))))
          ;; This check is necessary because of featured results
          (if (looking-at "</h3>")
              (progn
                (re-search-forward "BNeawe s3v9rd" nil t)
                (re-search-forward "BNeawe s3v9rd" nil t)
                (re-search-forward "\">\\(.*?\\)</div>" nil t)
                (setq result (plist-put result :content (helm-google--process-html (match-string-no-properties 1))))))
          (add-to-list 'results result t)
          (setq result nil))
        results)))

(defun helm-google--parse-searx (buf)
  "Parse the json response from Searx."
  (let ((json-object-type 'plist)
        (json-array-type 'list))
    (plist-get (helm-google--with-buffer buf (json-read)) :results)))

(defun helm-google--parse-brave (buf)
  "Parse the json response from Brave search."
  (let* ((json-object-type 'plist)
         (json-array-type 'list)
         (results-results (plist-get (helm-google--with-buffer buf (json-read)) :web))
         (results (plist-get results-results :results))
         (render-description))
    (cl-loop for result in results
             do (setq render-description
                      (with-temp-buffer
                        (insert (plist-get result :description))
                        (shr-render-region (point-min) (point-max))
                        (buffer-string)))
             collect `(:url ,(plist-get result :url)
                       :title ,(plist-get result :title)
                       :content ,render-description) ) ))

(defun helm-google--parse-stract (buf)
  "Parse the json response from Stract search stored in BUF."
  (let* ((json-object-type 'plist)
         (json-array-type 'list)
         (results (plist-get (helm-google--with-buffer buf (json-read)) :webpages))
         (render-description))
    (cl-loop for result in results
             do (setq render-description
                      (let* ((text-fragments-list (plist-get result :snippet))
                             (fragments-list (plist-get text-fragments-list :text))
                             (fragments (plist-get fragments-list :fragments)))
                        (mapconcat (lambda (f) (plist-get f :text)) fragments "") ))
             collect `(:url ,(plist-get result :url)
                       :title ,(plist-get result :title)
                       :content ,render-description) ) ))

(defun helm-google--response-buffer-from-search (text search-url)
  (let ((url-mime-charset-string "utf-8")
        (url (format search-url (url-hexify-string text))))
    (url-retrieve-synchronously url t)))

(defun helm-google--search (text engine)
  "Fetch the response buffer and parse it with the corresponding
parsing function."
  (let* ((search-url (or (and (eq engine 'google)
                              (boundp 'helm-google-url) ;support legacy variable
                              helm-google-url)
                         (alist-get engine helm-google-engines)))
         (url-request-extra-headers `(("User-Agent" . ,helm-google-user-agent)))
         (url-request-method "GET")
         (url-request-data nil)
         (buf nil))
    (cond
     ((eq engine 'stract)
      (progn
        (add-to-list
       'url-request-extra-headers '("Content-Type" . "application/json"))
        (setq url-request-method "POST"
              url-request-data (json-serialize `((query . ,text))))))
     ((eq engine 'brave)
      (add-to-list
       'url-request-extra-headers `("X-Subscription-Token" . ,helm-google-brave-api-key))))
    (setq buf (helm-google--response-buffer-from-search text search-url))
    (when (bound-and-true-p helm-google---debug-write-response)
      (with-current-buffer buf (write-region (point-min) (point-max) "/tmp/helm-google-debug")))
    (funcall (intern (format "helm-google--parse-%s" engine)) buf)))

(defun helm-google-search (&optional engine)
  "Query the search engine, parse the response and fontify the candidates."
  (let* ((engine (or engine helm-google-default-engine))
         (results (helm-google--search helm-pattern engine)))
    (mapcar (lambda (result)
              (let ((cite (plist-get result :cite)))
                (cons
                 (concat
                  (propertize
                   (plist-get result :title)
                   'face 'font-lock-variable-name-face)
                  "\n"
                  (plist-get result :content)
                  "\n"
                  (when cite
                    (concat
                     (propertize
                      cite
                      'face 'link)
                     "\n"))
                  (propertize
                   (url-unhex-string
                    (plist-get result :url))
                   'face (if cite 'glyphless-char 'link)))
                 (plist-get result :url))))
            results)))


(defun helm-google-engine-string ()
  (capitalize
   (format "%s" helm-google-default-engine)))

(defvar helm-source-google
  (helm-build-sync-source "helm for WWW"
    :name (helm-google-engine-string)
    :action 'helm-google-actions
    :candidates #'helm-google-search
    :requires-pattern 3
    :nohighlight 't
    :multiline 't
    :match '(identity)
    :volatile 't))

;;;###autoload
(defun helm-google (&optional engine search-term)
  "Web search interface for Emacs."
  (interactive)
  (let ((input (or search-term (when (use-region-p)
                                 (buffer-substring-no-properties
                                  (region-beginning)
                                  (region-end)))))
        (helm-google-default-engine (or engine helm-google-default-engine)))
    (helm :sources 'helm-source-google
          :prompt (concat (helm-google-engine-string) ": ")
          :input input
          :input-idle-delay helm-google-idle-delay
          :buffer "*helm google*"
          :history 'helm-google-input-history)))

;;;###autoload
(defun helm-google-searx (&optional search-term)
  "Explicitly use Searx for the web search."
  (interactive)
  (helm-google 'searx search-term))

;;;###autoload
(defun helm-google-google (&optional search-term)
  "Explicitly use Google for the web search."
  (interactive)
  (helm-google 'google search-term))

;;;###autoload
(defun helm-google-brave (&optional search-term)
  "Explicitly use Google for the web search."
  (interactive)
  (helm-google 'brave search-term))

;;;###autoload
(defun helm-google-stract (&optional search-term)
  "Explicitly use Google for the web search."
  (interactive)
  (helm-google 'stract search-term))

(add-to-list 'helm-google-suggest-actions
             '("Helm-Google" . (lambda (candidate)
                                 (helm-google nil candidate))))

(provide 'helm-google)

;;; helm-google.el ends here

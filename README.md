# helm-google

Emacs Helm Interface for quick Google searches

## Screenshot

![screen shot](https://raw.github.com/steckerhalter/helm-google/master/screenshot.png)

## Installation

### quelpa

`quelpa` is at https://github.com/quelpa/quelpa

```lisp
(quelpa '(helm-google :fetcher github :repo "steckerhalter/helm-google"))
```

### MELPA

`helm-google` is on [melpa](https://melpa.org/) (see there for more info).

## Usage

Call it with:

    M-x helm-google

Or bind it to a key:

```lisp
(global-set-key (kbd "C-h C--") 'helm-google)
```

If a region is selected it will take that as default input and search Google immediately. Otherwise it will start to search after you have entered a term. Pressing `RET` on a result calls the `browse-url` function which should open the URL in your web browser.

To use the internal `Emacs Web Wowser` (EWW, since Emacs 24.4) to open an url, press <key>F2</key>.

To copy the link into the clipboard, press <key>F3</key>.

If you want use EWW by default you can set it as your default browser like so:

```lisp
(setq browse-url-browser-function 'eww-browse-url)
```

If you want to keep the search open use `C-z` instead of `RET`.

### Idle delay

The default delay after a new search is made when you stopped typing is `0.4s`. You can customize this and set it to 1s for example:

``` emacs-lisp
(setq helm-google-idle-delay 1)
```

### helm-google-suggest

`helm-google` is added as an action to `helm-google-suggest` (thanks to Dickby). Press TAB and choose `Helm-Google` or use the shortcut listed there directly.

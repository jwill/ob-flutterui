;;; ob-flutterui.el --- Org babel functions for Flutter UI evaluation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 James Williams

;; Author: James Williams
;; Package-Requires: ((emacs "25.1") (dart-mode "1.0.0") (org "9.2.0"))
;; URL: https://github.com/jwill/ob-flutterui
;; Version: 0.0.2

;;; Commentary:

;; Run and render Flutter blocks using org babel natively with headless Golden Widget Tests.
;;
;; Install with:
;;
;;   (require 'ob-flutterui)
;;   (setq ob-flutterui-project-path "~/Documents/babel_dart")
;;   (ob-flutterui-setup)

;;; Code:
(require 'ob)
(require 'org)
(require 'dart-mode nil t)
(require 'map)

(defalias 'flutterui-mode #'dart-mode)

(defgroup ob-flutterui nil
  "Org Babel Flutter UI."
  :group 'org-babel)

(defcustom ob-flutterui-project-path "~/Documents/babel_dart"
  "Path to the Flutter project that hosts the execution."
  :type 'string
  :group 'ob-flutterui)

(defvar org-babel-default-header-args:flutterui '((:results . "file")
                                                  (:view . "none")
                                                  (:file . nil)
                                                  (:width . "1920")
                                                  (:height . "1080")
                                                  (:exports . "results"))
  "Default ob-flutterui header args.")

(defun ob-flutterui--ensure-fonts ()
  (let ((font-path (concat ob-flutterui-project-path "/test/Roboto-Regular.ttf")))
    (unless (file-exists-p font-path)
      (message "Downloading default Roboto font just once for headless typography...")
      (url-copy-file "https://github.com/google/fonts/raw/main/ofl/roboto/Roboto-Regular.ttf" font-path t))))

(defun org-babel-execute:flutterui (body params)
  "Execute a block of Flutter code using a headless test layer."
  (message "Evaluating Flutter block headlessly... (Expect ~4 seconds)")
  (let* ((write-to-file (member "file" (map-elt params :result-params)))
         (output-file (map-elt params :file))
         (width (or (map-elt params :width) "1920"))
         (height (or (map-elt params :height) "1080"))
         (binary (make-temp-file "ob-flutterui-"))
         (source (concat ob-flutterui-project-path "/test/org_babel_widget_test.dart"))
         (png-path (if write-to-file
                       (if output-file (expand-file-name output-file) (concat binary ".png"))
                     nil)))
    
    (unless png-path
      (user-error "ob-flutterui now requires ':results file :file name.png' strictly for headless evaluation!"))

    (when (file-exists-p png-path)
      (delete-file png-path))

    ;; Ensure test directory exists
    (unless (file-directory-p (concat ob-flutterui-project-path "/test"))
      (make-directory (concat ob-flutterui-project-path "/test") t))

    (ob-flutterui--ensure-fonts)

    (with-temp-buffer
      (insert (ob-flutterui--expand-preview body params png-path width height))
      (write-region (point-min) (point-max) source nil 'silent))

    (let ((default-directory ob-flutterui-project-path))
      (let ((result (call-process "flutter" nil "*ob-flutterui-output*" t "test" "--update-goldens" "test/org_babel_widget_test.dart")))
        (unless (eq result 0)
          (user-error "Flutter compilation failed! Press 'C-x b *ob-flutterui-output*' to view the Dart stacktrace!"))))

    (unless (file-exists-p png-path)
      (user-error "Flutter ran but failed to dump the screenshot to %s" png-path))

    nil))

(defun ob-flutterui-setup ()
  "Set up babel Flutter UI support."
  (add-to-list 'org-babel-tangle-lang-exts '("flutterui" . "dart"))
  (org-babel-do-load-languages 'org-babel-load-languages
                               (append org-babel-load-languages
                                       '((flutterui . t))))
  (add-to-list 'org-src-lang-modes '("flutterui" . dart)))

(defun ob-flutterui--expand-preview (body params png-path width height)
  (let ((root-view (if (and (map-elt params :view)
                            (not (string-equal (map-elt params :view) "none")))
                       (map-elt params :view)
                     "none")))
    (format
"import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'dart:math' as math;

// Generated specifically for Org-Babel headless execution.

Future<void> _loadTestFonts() async {
  final fontLoader = FontLoader('Roboto');
  final fontData = File('test/Roboto-Regular.ttf').readAsBytesSync();
  fontLoader.addFont(Future.value(ByteData.view(fontData.buffer)));
  await fontLoader.load();
}

void main() {
  testWidgets('org babel block render', (WidgetTester tester) async {
    await _loadTestFonts();
    tester.view.physicalSize = const Size(%s, %s);
    tester.view.devicePixelRatio = 2.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto'),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: %s,
        ),
      ),
    );

    // Wait for frames to settle (animations, etc).
    await tester.pumpAndSettle();

    // Snap screenshot to absolute system path natively
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('%s'));
  });
}

%s
"
     width
     height
     (if (string-equal root-view "none")
         (format "Center(child: %s)" body)
       (format "%s()" root-view))
     png-path
     (if (string-equal root-view "none") "" body))))

(provide 'ob-flutterui)
;;; ob-flutterui.el ends here

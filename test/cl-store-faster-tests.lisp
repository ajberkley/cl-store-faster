(defpackage #:cl-store-faster-tests
  (:use #:common-lisp #:parachute #:cl-store-faster #:cl-store-faster-extensions))

(in-package #:cl-store-faster-tests)

(define-test test-very-basic-list-cdr-circularity
  (let ((a (list 123 456))
	(*support-shared-list-structures* nil))
    (setf (cddr a) a)
    (let ((result (restore-from-vector (store-to-vector a))))
      ;; (let ((*print-circle* t))
      ;; 	(print result))
      (is '= (first result) 123)
      (is '= (second result) 456)
      (is 'eq (cddr result) result))))

(define-test test-very-basic-list-car-circularity
  (let ((a (list nil "abcd"))
	(*support-shared-list-structures* nil))
    (setf (first a) a)
    (let ((result (restore-from-vector (store-to-vector a))))
      ;; (let ((*print-circle* t))
      ;; 	(print result))
      (is 'eq (first result) result)
      (is 'equalp (second result) "abcd")
      (false (cddr result)))))

(define-test test-non-basic-circularity
  (let ((a (list 123 456))
	(*support-shared-list-structures* t))
    (setf (cdr (last a)) (nthcdr 1 a)) ;; loop back to second element
    (let ((result (restore-from-vector (store-to-vector a))))
      (is '= (first result) 123)
      (is '= (cadr result) 456)
      (is 'eq (cddr result) (cdr result)))))

(define-test test-simple-displaced-array-circularity
  (let* ((a (make-array 1))
	 (b (make-array 1 :displaced-to a))
	 (*support-shared-list-structures* nil))
    (setf (aref a 0) b)
    (let ((c (restore-from-vector (store-to-vector b))))
      (let ((*print-circle* t))
	;; This depends on the circle printer to do the same thing :)
	(is 'equal
	    (format nil "~A~%" c)
	    (format nil "~A~%" b))))))

(define-test test-displaced-array-circularity
  (let* ((a (make-array 3))
	 (b (make-array 1 :displaced-to a))
	 (*support-shared-list-structures* nil))
    (setf (aref a 0) b)
    (setf (aref a 1) (list "blarg" a b))
    (setf (aref a 2) (make-array 3 :initial-element b))
    (let ((c (restore-from-vector (store-to-vector b))))
      (let ((*print-circle* t))
	;; This depends on the circle printer to do the same thing :)
	(is 'equal
	    (format nil "~A~%" c)
	    (format nil "~A~%" b))))))

(define-test test-simple-arrays
    (let* ((elt-types
	     '(bit fixnum base-char character single-float
	       double-float (signed-byte 8) (signed-byte 16)
	       (signed-byte 32) (signed-byte 64)
	       (unsigned-byte 2)
	       (unsigned-byte 4)
	       (unsigned-byte 7)
	       (unsigned-byte 8)
	       (unsigned-byte 15)
	       (unsigned-byte 16)
	       (unsigned-byte 31)
	       (unsigned-byte 32)
	       (unsigned-byte 62)
	       (unsigned-byte 64)))
	   (sizes
	     (loop repeat (length elt-types)
		   collect (+ 1 (random 10))))
	   (fill-values
	     (loop for elt-type in elt-types
		   for size in sizes
		   collect
		   (loop repeat size collect
				     (case elt-type
				       (bit (random 1))
				       (fixnum (random (- (expt 2 62) (expt 2 61))))
				       (base-char #\a)
				       (character #\b)
				       (single-float (random 1f0))
				       (double-float (random 1d0))
				       (otherwise
					(if (eql (first elt-type) 'signed-byte)
					    (- (random 128))
					    (random (expt 2 (second elt-type))))))))))
      (assert (= (length elt-types) (length fill-values) (length sizes)))
      (let ((input (store-to-vector 
		    (loop for elt-type in elt-types
			  for fill in fill-values
			  for size in sizes
			  collect
			  (make-array size :element-type elt-type :initial-contents fill)))))
	(loop for elt-type in elt-types
	      for fill in fill-values
	      for size in sizes
	      for result in (restore-from-vector input)
	      do
		 ;;(format t "~A with ~A elements~% ~A (vs ~A)~%" elt-type size fill result)
		 (true (equal (upgraded-array-element-type (array-element-type result))
			      elt-type))
		 (true (every (lambda (x fill-value) (eql x fill-value)) result fill))
		 (true (= (length result) size))))))
  
(define-test test-strings
  (dolist (string (list (make-string 10 :element-type 'base-char :initial-element #\a)
			"asdffdsa"
			(make-string 10 :element-type 'character :initial-element #\b)))
    (is 'equalp (restore-from-vector (store-to-vector string)) string)))

(define-test test-symbols
  (let ((symbols (list (intern "HI" "CL-STORE-FASTER-TESTS")
		       (intern "TEST-SYMBOL-HI" "CL-STORE-FASTER"))))
    (true (equalp
	   (restore-from-vector (store-to-vector symbols))
	   symbols))
    (let ((vec (store-to-vector symbols)))
      (unintern (find-symbol "HI"))
      (unintern (find-symbol "TEST-SYMBOL-HI" "CL-STORE-FASTER"))
      (restore-from-vector vec)
      (true (find-symbol "HI"))
      (true (find-symbol "TEST-SYMBOL-HI" "CL-STORE-FASTER")))
    (let ((g (gensym)))
      (let ((new-g (restore-from-vector (store-to-vector g))))
	(is 'equalp (symbol-name g) (symbol-name new-g))
	(true (null (symbol-package new-g)))))))

(define-test test-simple-vector
  (let ((vector #(1 2 3 "asdf" "ghijil" 1d0)))
    (is
     'equalp
     (restore-from-vector (store-to-vector vector))
     vector)))

(defstruct blarg
  (a)
  (b 0d0 :type double-float)
  (c 0f0 :type single-float)
  (d #() :type simple-vector)
  (f nil :type boolean)
  (g t :type (or simple-vector integer (eql t))))

(define-test test-struct-simple
  (let ((s (list (make-blarg :a 1234 :b 1d0 :d (make-array 5 :initial-element "hi"))
		 (make-blarg :a 456 :b 3d0 :d (make-array 5 :initial-element "boo")))))
    (let ((result (restore-from-vector (store-to-vector s))))
      (is 'equalp result s))))

(define-test test-struct-circular
  (let ((s (list (make-blarg :a 1234 :b 1d0 :d (make-array 5 :initial-element "hi"))
		 (make-blarg :a 456 :b 3d0 :d (make-array 5 :initial-element "boo")))))
    (setf (blarg-a (second s)) (first s))
    (setf (blarg-a (first s)) (second s))
    (let ((result (restore-from-vector (store-to-vector s)))
	  (*print-circle* t))
      (is '= (length result) 2)
      (is 'eql (blarg-a (first result)) (second result))
      (is 'eql (blarg-a (second result)) (first result))
      (setf (blarg-a (first s)) nil)
      (setf (blarg-a (second s)) nil)
      (setf (blarg-a (first result)) nil)
      (setf (blarg-a (second result)) nil)
      (is 'equalp result s))))

(define-test test-struct-info
  (let ((b (cl-store-faster::compute-slot-info (make-instance 'blarg))))
    (is 'equalp
	(restore-from-vector (store-to-vector b))
	b)))

(defclass a-class ()
  ((a :initarg :a)
   (b :initform 1d0 :initarg :b)
   (c :initform "c" :initarg :c)))
  
(defclass b-class (a-class)
  ((d :initform "hihi" :initarg :d)))

(define-test test-standard-objects
  (let ((b (list (make-instance 'b-class)
		 (make-instance 'b-class :a 1 :b 2 :c 3 :d 4)
		 (make-instance 'a-class))))
    ;; circularity tests
    (setf (slot-value (first b) 'b) (first b))
    (setf (slot-value (third b) 'c) (second b))
    (destructuring-bind (x y z)
	(restore-from-vector (store-to-vector b))
      (false (slot-boundp x 'a))
      (is 'eq (slot-value x 'b) x)
      (is 'equalp (slot-value x 'c) "c")
      (is 'equalp (slot-value x 'd) "hihi")
      
      (true (slot-boundp y 'a))
      (is 'eql (slot-value y 'b) 2)
      (is 'eql (slot-value y 'c) 3)
      (is 'eql (slot-value y 'd) 4)
      
      (false (slot-boundp z 'a))
      (is 'eql (slot-value z 'b) 1d0)
      (is 'eq (slot-value z 'c) y))))

(define-test test-pathname
  (let ((a (make-pathname :directory "tmp" :name "blarg")))
    (is 'equalp
	(restore-from-vector (store-to-vector a))
	a)))

(define-test test-hash-table
  (let* ((ht (make-hash-table :test 'equalp))
	 (kvs (list (cons 1234 t)
		    (cons "blarg" 5668d0)
		    (cons (list 7d0) (vector 1 2 3))
		    (cons (vector (/ 3 4)) 17d0))))
    (map nil (lambda (x)
	       (setf (gethash (car x) ht) (cdr x)))
	 kvs)
    (let ((ht-restore (restore-from-vector (store-to-vector ht))))
      (maphash (lambda (k v)
		 (equalp (gethash k ht-restore) v))
	       ht))))
	 
(define-test test-simple-array-t-multi-dim
  (let ((a (make-array '(1 1 1) :initial-element 3)))
    (is 'equalp
	a
	(restore-from-vector (store-to-vector a)))))

(define-test test-non-proper-list
  (let ((non-proper-list '(1 . 2)))
    (is 'equal
	(restore-from-vector
	 (store-to-vector
	  non-proper-list))
	non-proper-list)))

(define-test test-simple-double-float
  (let ((df 3.1415d0))
    (is '= df
	(restore-from-vector
	 (store-to-vector df)))))

(define-test test-simple-single-float
  (let ((sf 3.1415f0))
    (is '= sf
	(restore-from-vector
	 (store-to-vector sf)))))

(define-test test-complex
  (let ((complex-numbers
	  (list
	   (complex 1 2)
	   (complex 3f0 4f0)
	   (complex -5d0 3d0)
	   (complex (/ 1 2) 17)
	   (complex 1f0 2d0))))
    (is 'equal
	complex-numbers
	(restore-from-vector
	 (store-to-vector complex-numbers)))))

(define-test test-ratio
  (let ((ratios (list (/ 1 2) (/ 4 -5))))
    (is 'equal
	ratios
	(restore-from-vector
	 (store-to-vector ratios)))))

(define-test test-sb8
  (is '= -127 (restore-from-vector (store-to-vector -127)))
  (is '= -255 (restore-from-vector (store-to-vector -255))))

(define-test test-sb16
  (is '= -32768 (restore-from-vector (store-to-vector -32768)))
  (is '= -65535 (restore-from-vector (store-to-vector -65535))))

(define-test test-sb32
  (let ((num (- (expt 2 31))))
    (is '= num (restore-from-vector (store-to-vector num))))
  (let ((num (- (1- (expt 2 32)))))
    (is '= num (restore-from-vector (store-to-vector num)))))

(define-test test-fixnum
  (let* ((num (expt 2 59))
	 (mnum (- num)))
    (is '= num (restore-from-vector (store-to-vector num)))
    (is '= mnum (restore-from-vector (store-to-vector mnum)))))

(define-test test-versioning
  (fail
      (restore
       (let ((*write-magic-number* t)
	     (*write-version* 123))
	 (store nil "check"))))
  (is 'equalp
      "check"
      (restore
       (let ((*write-magic-number* nil)
	     (*write-version* 123))
	 (store nil "check"))))
  (is 'equalp
      "check"
      (nth-value 1
		 (restore
		  (let ((*write-magic-number* t))
		    (store nil "check"))))))
  
#+sbcl(define-test test-condition-serialization
  ;; On sbcl a condition is neither a standard-object nor a structure-object
  (let* ((a (make-condition 'simple-error :format-control "hi ~A" :format-arguments (list 123)))
         (b (restore (store nil a))))
    (is 'eql (type-of a) (type-of b))
    (is 'eql (class-of a) (class-of b))
    (is 'equalp (simple-condition-format-control a) (simple-condition-format-control b))
    (is 'equal (simple-condition-format-arguments a) (simple-condition-format-arguments b))))

#+sbcl(define-test test-sap-write/read
        ;; Normal use
        (let ((a (make-array 24 :element-type '(unsigned-byte 8) :initial-element 0))
              (input (list 1 2)))
          (is 'equal
              (cl-store-faster::with-pinned-objects (a)
                (let ((len (store-to-sap (cl-store-faster::vector-sap a) (length a) input)))
                  (restore-from-sap (cl-store-faster::vector-sap a) len)))
              input))
        ;; Not enough space
        (let ((a (make-array 2 :element-type '(unsigned-byte 8) :initial-element 0))
              (input (list 1 2)))
              (cl-store-faster::with-pinned-objects (a)
                (fail (store-to-sap (cl-store-faster::vector-sap a) (length a) input))))
        ;; Dynamic sap replacement for mmap'ed files
        (let ((a (make-array 24 :element-type '(unsigned-byte 8) :initial-element 0))
              (data (list 1d0 2 3)))
          ;; Here we don't actually reallocate, we just lie and say we did
          (cl-store-faster::with-pinned-objects (a)
            (let* ((len
                     (handler-bind ((out-of-space
                                      (lambda (e)
                                        (replace-store-sap-buffer
                                         (cl-store-faster::vector-sap a)
                                         :sap-offset (out-of-space-current-offset e)
                                         :sap-size (length a)))))
                       (store-to-sap (sb-sys:vector-sap a) 1 data))))
              (is 'equal data (restore-from-sap (sb-sys:vector-sap a) len))))))

(define-test test-store/restore-to-file
  (let ((data1 (make-array 398423 :initial-element 3))
        (data2 (make-list 1234 :initial-element "hi")))
    (multiple-value-bind (d1 d2)
        (restore (store "blarg-test-cl-store.bin" data1 data2))
      (is 'equalp data1 d1)
      (is 'equalp data2 d2))))

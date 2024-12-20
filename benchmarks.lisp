;; TODO ADD A SIMPLE-BASE-STRING tag code and a SIMPLE-STRING tag code
;; about 10% of the time is spent in upgraded-array-element-type and
;; array-dimensions and other stuff.

(quicklisp:quickload "cl-store")
(require 'sb-sprof)

(defun long-simple-list ()
  (let ((a (loop for i fixnum from 0 below 1000000
		 collect (make-pathname :name (format nil "~A" (random 2398423))
					:directory "my-directory"))))
    (gc :full t)
    (let ((cl-store-faster::*support-shared-list-structures* nil))
      (time (dotimes (x 10) (cl-store-faster:store-to-file "blarg.bin" a))))
    (with-open-file (str "blarg.bin")
      (format t "CL-STORE-FASTER: file length ~,2fMB~%" (/ (file-length str) 1d6)))
    (time (dotimes (x 10) (cl-store-faster:restore-from-file "blarg.bin")))
    (gc :full t)
    (time (dotimes (x 10) (cl-store:store a "blarg.bin")))
    (with-open-file (str "blarg.bin")
      (format t "CL-STORE: file length ~,2fMB~%" (/ (file-length str) 1d6)))
    (time (dotimes (x 10) (cl-store:restore "blarg.bin")))
    )
  (gc :full t))

;; Testing 10x writing and reading a 1M long list of identical
;; value of the types below.  This is just a test on the hash
;; table usage (it shows that cl-store does not de-duplicate
;; numbers larger than ub32s).  File sizes is 3MB for
;; CL-STORE-FASTER vs 4MB for CL-STORE
;;+------------+------------------+------------------+ 
;;|  FIXED     | CL-STORE-FASTER  |     CL-STORE     |
;;+------------+------------------+------------------+
;;| TYPE       |WRITE(ms)|READ(ms)|WRITE(ms)|READ(ms)|
;;+------------+---------+--------+---------+--------+
;; symbol      |      505|     150|      650|     700|
;; ub8         |      335|     140|      720|     680|
;; sb8         |      330|     140|      720|     680|
;; ub16        |      385|     140|      950|     815|
;; sb16        |      370|     135|      920|     800|
;; ub32        |      400|     150|      915|     795|
;; fixnum      |      435|     160|     5000|    3400| 
;; single-float|      435|     160|      675|     680|
;; double-float|      535|     145|      690|     690|
;; complex     |      530|     160|      650|     690|
;; string      |      150|     130|      670|     690| ;; 3 MB cl-store-faster vs 4 MB cl-store
;; pathname    |      650|     130|      680|     700| ;; 3 MB cl-store-faster vs 4 MB cl-store
;;+------------+---------+--------+---------+--------+
;; For the number cases we are storing say 20M objects (the conses
;; and the numbers) in 350 ms which is 57M transactions/sec or
;; 18 ns per transaction.  That's not so bad for this cache hot
;; case.  (This is all on an old i5 laptop).  In terms of data rate,
;; this is 30 MB/ 350 ms or 85 MB/sec which isn't amazing.

;; Now, doing 10 repeats of writing 1 million random objects
;;+------------+------------------+------------------+---------------+--------+ 
;;|   RANDOM   | CL-STORE-FASTER  |     CL-STORE     |CL-STORE-FASTER|CL-STORE|
;;+------------+------------------+------------------+---------------+--------+
;;| TYPE       |WRITE(ms)|READ(ms)|WRITE(ms)|READ(ms)|      SIZE     |  SIZE  |
;;+------------+---------+--------+---------+--------+---------------+--------+
;; ub8         |      375|     135|      715|     715|            3MB|     5MB|
;; ub16        |      390|     140|      925|     815|            4MB|     8MB|
;; ub32        |      390|     150|      910|     800|            6MB|     8MB|
;; fixnum      |      435|     160|     5000|    3400|           10MB|    38MB|
;; single-float|      410|     145|   700000|    6500|            6MB|    21MB|
;; double-float|     3650|     330|    10400|   11100|           10MB|    48MB|
;; gensym      |     1240|    1890|     3650|    3270|           13MB|    12MB|
;; complex/sb8 |      540|     150|      690|     700|            3MB|     4MB|
;; complex/df  |      530|     140|      690|     770|            3MB|     4MB|
;; complex/sf  |      540|     140|      690|     710|            3MB|     4MB|
;; string      |     2200|     500|     3600|    1800|           11MB|    11MB|
;; pathname    |     3000|     740|     2400|    3100|            7MB|     8MB|
;;+------------+---------+--------+---------+--------+---------------+--------+

;; TODO WHY IS PATHNAME SLOW-ish?  Weird.  
;; Hm.  eq hashtable didn't speed it up, so I don't know...

;; TODO do write flushing asynchronously --- we are hitting 90% CPU only with
;; 10% system time already for many things.

;; TODO: add a fast approximate radix bucket sort to assign reference ids after
;; the reference counting step?  It's not trivial to do fast, but I think it
;; might be fun.  Only trigger it if > 65536 references because ub32 vs ub16 is
;; significant.  I guess we can also do if 256 < num-refs < 65536 but use a
;; really coarse metric?

;; WARNING: sbcl hashing on single floats is terrible, so cl-store does not finish
(defun long-float-array (&optional (random nil))
  (let ((a (coerce (loop repeat 1000000 collect (if random (random 1f0) 1f0))
		   '(simple-array single-float (*)))))
    (gc :full t)
    (let ((cl-store-faster::*support-shared-list-structures* nil))
      ;;(sb-sprof:with-profiling (:report :graph)
      (time (dotimes (x 10) (cl-store-faster:store-to-file "blarg.bin" a)))
      (time (dotimes (x 10) (cl-store-faster:restore-from-file "blarg.bin"))))
    (with-open-file (str "blarg.bin")
      (format t "CL-STORE-FASTER: file length ~,2fMB~%" (/ (file-length str) 1d6)))
    (gc :full t)
    (time (dotimes (x 10) (cl-store:store a "blarg.bin")))
    (time (dotimes (x 10) (cl-store:restore "blarg.bin")))
    (with-open-file (str "blarg.bin")
      (format t "CL-STORE: file length ~,2fMB~%" (/ (file-length str) 1d6))))
  (gc :full t))
;; Double float non-random (you can see the hot branch predicted path going zoom)
;; CL-STORE-FASTER: 145 ms write /  35 ms read; half is system time on write
;; CL-STORE:        600 ms write / 625 ms read.  Not a surprise of course.
;; Double-float random (here we are puthash limited tracking double-float references)
;; CL-STORE-FASTER:   767 ms write /    40 ms read
;; CL-STORE:        11400 ms write / 10825 ms read (this is because double float storing is slow)
;; Single float non-random
;; CL-STORE-FASTER:    83 ms write /    20 ms read
;; CL-STORE:          540 ms write /   670 ms read
;; Single float random
;; CL-STORE-FASTER:   100 ms write /    25 ms read (half is system time on write)
;; CL-STORE:          DNF ms write /   DNF ms read (terrible single float hashing stuff? on SBCL)

(defun long-complex-list ()
  (let ((a (loop repeat 1000000 collect (if (> (random 1000) 500)
					    (random 1d0)
					    ;; (complex 1d0) ;; cl-store chokes
					    ;; (random 1d0) ;; cl-store chokes
					    (if (> (random 100) 50)
						;;(random 1f0) ;; <- makes cl-store take forever!
						(format nil "~A" (random 123)) ;;"hi" ;;'blarg
						(if (> (random 100) 50)
						    (cons (random 30) 2)
						    (if (= (random 2) 1)
							"hello"
							;; (random 1f0) slows cl-store crazily
							#())))))))
    (gc :full t)
    (let ((cl-store-faster::*support-shared-list-structures* nil))
      (time (dotimes (x 10) (cl-store-faster:store-to-file "blarg.bin" a))))
      (time (dotimes (x 10) (cl-store-faster:restore-from-file "blarg.bin")))
    (assert (equalp (cl-store-faster:restore-from-file "blarg.bin") a))
    (with-open-file (str "blarg.bin")
      (format t "CL-STORE-FASTER: file length ~,2fMB~%" (/ (file-length str) 1d6)))
    (gc :full t)
    (time (dotimes (x 10) (cl-store:store a "blarg.bin")))
    (time (dotimes (x 10) (cl-store:restore "blarg.bin")))
    (with-open-file (str "blarg.bin")
      (format t "CL-STORE: file length ~,2fMB~%" (/ (file-length str) 1d6)))
    )
  (gc :full t))

;; Without the random single floats, otherwise cl-store takes forever
;; CL-STORE-FASTER: 925 ms write /  265 ms read
;; CL-STORE:       1400 ms write / 1400 ms read

(defun long-random-double-float-list ()
  (let ((a (loop repeat 1000000 collect (random 1d0))))
    (gc :full t)
    (let ((cl-store-faster::*support-shared-list-structures* nil))
      ;;      (sb-sprof:with-profiling (:report :graph)
      (time (dotimes (x 10) (cl-store-faster:store-to-file "blarg.bin" a))))
    (time (dotimes (x 10) (cl-store-faster:restore-from-file "blarg.bin")))
    ;; (assert (equalp (cl-store-faster:restore-from-file "blarg.bin") a))
    (gc :full t)
    ;;(sb-sprof:with-profiling (:report :graph)
      (time (dotimes (x 10) (cl-store:store a "blarg.bin")))
    (time (dotimes (x 10) (cl-store:restore "blarg.bin"))))
  (gc :full t))
;; long-random-double-float-list
;; CL-STORE-FASTER: 3500 ms write /   315 ms read
;; CL-STORE:       12700 ms write / 11000 ms read

(defun single-float-hash-test ()
  (let ((ht (Make-hash-table :test 'eql)))
    (loop repeat 1000000
	  ;;for val = (expt 2d0 (- (random 616d0) 308d0))
	  for val = (if (> (random 1000) 800)
			(random 1f0)
			(random 1f0))
	  do (incf (gethash (sxhash val) ht 0)))
    (let ((sum 0)
	  (max 0))
      (maphash (lambda (k v)
		 (setf max (max v max))
		 (incf sum v))
	       ht)
      (format t "HT size is ~A, maximum collisions is ~A, average collisions ~A~%"
	      (hash-table-size ht)
	      max
	      (* 1f0 (/ sum (hash-table-count ht)))))))


(defun four-long-simple-lists ()
  (let* ((length 1000000)
	 (chunks 4)
	 (as (loop repeat chunks
		   collect
		   (loop repeat (floor length chunks) collect 'a))))
    (gc :full t)
    (let ((cl-store-faster::*support-shared-list-structures* nil))
      ;;(sb-sprof:with-profiling (:report :graph)
      (time (dotimes (x 10) (apply #'cl-store-faster:store-to-file "blarg.bin" as))))
    ;; (time (dotimes (x 10) (cl-store-faster:restore-from-file "blarg.bin")))
    (gc :full t)
    ;; Here we average 4 bytes per
    ;; 1 byte for each cons,
    ;; 1 byte for a reference
    ;; and two bytes for the reference?
    ;; (time (dotimes (x 10) (cl-store:store a "blarg.bin")))
    ;; (time (dotimes (x 10) (cl-store:restore "blarg.bin")))
    )
  (gc :full t))

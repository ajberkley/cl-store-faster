(in-package :cl-store-faster)


;; (pushnew :debug-csf *features*)
;; (setf *features* (delete :debug-csf *Features*))
;; Referrers are used to handle circularity (in lists, non-specialized
;; vectors, structure-classes and standard-classes).  Referrers are
;; implicitly created during serialization and deserialization.

;; We use referrers when the underlying common lisp structure allows sharing
;; and when it makes sense to save memory in the restored image (that is objects
;; that are tagged):
;;  (and number (not fixnum) (not `single-float')) will be de-duplicated
;;  `structure-class'es and slot-values thereof
;;  `standard-class'es and slot-values thereof
;;  `cons'es

(defstruct referrer)

(defparameter *references* nil
  "An EQL hash-table that is locally bound during store or restore.

 Used to store objects we restore which may be referenced later
 (or in a circular manner).
 For example if we store a circular list:
  #1=(cons #1 #1)
 To store this, we first see the cons, write out a +cons-code+,
 and store the cons in *references* pointing at referrer index 1.
 Then we see a reference to referrer index 1, which we can
 immediately resolve.  There is no complexity here requiring
 delayed fix-ups or anything.

 When we are reading though, we see the cons, and immediately
 allocate (cons nil nil).  The same goes for structures and classes,
 where we pre-allocate the objects as soon as we see their types.

 This hash-table maps values -> reference-indices when writing, and
 reference-indices -> values when reading, as such ONLY store non
 fixnum objects in here.")

(declaim (inline store-reference))
(defun store-reference (ref-index storage)
  "We store references as the minimum possible size we can"
  (declare (type (and (integer 0) fixnum) ref-index))
  (ensure-enough-room storage 4)
  (let ((offset (storage-offset storage))
	(array (storage-store storage)))
    (typecase ref-index
      ((unsigned-byte 8)
       (store-ub8 +referrer-ub8-code+ storage nil)
       (store-ub8 ref-index storage nil))
      ((unsigned-byte 16)
       (store-ub8 +referrer-ub16-code+ storage nil)
       (store-ub16 ref-index storage nil))
      ((unsigned-byte 32)
       (store-ub8 +referrer-ub32-code+ storage nil)
       (store-ub32 ref-index storage nil))
      (t
       (setf (aref array offset) +referrer-code+)
       (setf (storage-offset storage) (+ offset 1))
       (store-tagged-unsigned-integer ref-index storage)))))

(defun check/store-reference (value storage &aux (ht *references*))
  (declare (optimize speed safety))
  (let ((ref-index (gethash value ht)))
    (if ref-index
	(progn (store-reference ref-index storage) t)
	(progn
	  (let ((ref-index (hash-table-count ht)))
	    #+debug-csf
	    (let ((*print-circle* t))
	      (format t "Assigning reference id ~A to ~S (~A)~%" ref-index value
		      (type-of value)))
	    (setf (gethash value ht) ref-index)
	    nil)))))

;; RESTORATION WORK

(declaim (inline record-reference))
(defun record-reference (value &aux (ht *references*))
  "This is used during RESTORE.  Here we keep track of a global count of
 references"
  (let ((len (length ht)))
    #+debug-csf
    (let ((*print-circle* t))
      (format t "Recording reference id ~A as ~S~%" len (if value value "delayed")))
    (vector-push-extend value ht)
    (values value len)))

(declaim (inline update-reference))
(defun update-reference (ref-id value)
  "Used during RESTORE"
  #+debug-csf
  (let ((*print-circle* t))
    (format t "Updating reference id ~A to ~S~%" ref-id value))
  (values (setf (aref *references* ref-id) value)))

(defun invalid-referrer (ref-idx)
  (cerror "skip" (format nil "reference index ~A does not refer to anything!" ref-idx)))

(declaim (inline get-reference))
(defun get-reference (ref-id)
  (or (aref *references* ref-id) (invalid-referrer ref-id)))

(declaim (inline restore-referrer))
(defun restore-referrer (storage)
  "Used during RESTORE"
  (get-reference (restore-object storage)))

(declaim (inline restore-referrer-ub8))
(defun restore-referrer-ub8 (storage)
  (get-reference (restore-ub8 storage)))

(declaim (inline restore-referrer-ub16))
(defun restore-referrer-ub16 (storage)
  (get-reference (restore-ub16 storage)))

(declaim (inline restore-referrer-ub32))
(defun restore-referrer-ub32 (storage)
  (get-reference (restore-ub32 storage)))

;; During restoring, we cannot always construct objects before we have
;; restored a bunch of other information (for example building displaced
;; arrays).  So we need to be able to fix-up references to the not yet built
;; object (which may have been restored while determining how to build the
;; object).

(declaim (inline fixup-p make-fixup fixup-list fixup-ref-id))
(defstruct fixup
  (list nil)
  (ref-id -1 :type fixnum))

(defun fixup (fixup new-value)
  (declare (optimize speed safety))
  "Resolve a delayed object construction.  Returns new-value."
  (mapc (lambda (func)
	  (funcall (the function func) new-value))
	(fixup-list fixup))
  (update-reference (fixup-ref-id fixup) new-value))

(defmacro with-delayed-reference/fixup (&body body)
  "If you cannot construct the object you are deserializing at the
 beginning of the deserialization routine because you need to load more
 information, AND there is a chance that the information you load may
 contain a reference back to the as-yet-constructed object you are building,
 then you must wrap your code with this magic.  BODY must yield the fully
 constructed object"
  (let ((fixup (gensym)))
    `(let ((,fixup (make-fixup)))
       (declare (dynamic-extent ,fixup))
       (setf (fixup-ref-id ,fixup) (nth-value 1 (record-reference ,fixup)))
       #+debug-csf(format t "Fixup is now ~A~%" ,fixup)
       (fixup ,fixup (progn ,@body)))))

(defmacro with-delayed-reference (&body body)
  "If you cannot construct the object you are deserializing at the
 beginning of the deserialization routine because you need to load
 more information, then you must wrap your code with this to keep
 referrer ids correct.  BODY must return the final object.  IF there
 is a chance of deserializing an object during BODY that may contain a
 reference to this not yet constructed object, then you must use
 WITH-DELAYED-REFERENCE/FIXUP instead."
  (let ((ref-id (gensym)))
    `(let ((,ref-id (nth-value 1 (record-reference nil))))
       (update-reference ,ref-id (progn ,@body)))))

(defmacro restore-object-to (place storage)
  "If you are deserializing an object which contains slots (for example
 an array, a list, or structure-object or a standard-object) which may
 point to other lisp objects which have yet to be fully reified, then
 please update your slots with this macro which will handle circularity
 fixups for you.

 Note that we capture any parameters of place so you may safely use this
 in loops or with references to variables whose values may be updated later"
  (let* ((restored (gensym))
	 (new-object (gensym))
	 (variables-to-capture (cdr place))
	 (names (loop repeat (length variables-to-capture) collect (gensym))))
    `(let ((,restored (restore-object ,storage)))
       (if (fixup-p ,restored)
	   (push
	    (let (,@(mapcar #'list names variables-to-capture))
	      (lambda (,new-object)
		(setf (,(first place) ,@names) ,new-object)))
	    (fixup-list ,restored))
	   (setf ,place ,restored)))))

(defmacro maybe-store-reference-instead ((obj storage) &body body)
  "Objects may occur multiple times during serialization or
 deserialization, so where object equality is expected (pretty much
 every object except numbers) or not determinable (double-floats,
 complex, ratios, bignum), we store references to objects we
 serialize so we can write a shorter reference to them later.  The
 counting of objects is done implicitely by matching of
 'maybe-store-reference-instead in store routines with the use of
 'with-delayed-reference, 'with-delayed-reference/fixup, or record-reference
 in the restore routines."
  `(or (check/store-reference ,obj ,storage)
       (progn
	 ,@body)))

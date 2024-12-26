(in-package :cl-binary-store)

;; Here we deal with STRUCTURE-OBJECT and STANDARD-OBJECT
;;  NOTE that we do not de-duplicate double-floats stored in slots unless they are eq (not eql!) to others
;;  NOTE that even if you specify 

(defvar *store-class-slots* nil
  "If set / let to T, then slots in standard-objects with :class allocation
 will be stored, otherwise not.")

;; We provide an extension point to customize how objects are
;; serialized.  We follow the design of cl-store with the addition of
;; some extra values which can be used to short circuit most of the
;; work in exchange for speed.  If you wish to customize on the
;; deserialization side, I suggest something like an :after method on
;; initialize-instance.  For example:

;; (defmethod serializable-slot-info ((object my-object-type) (type 'my-object-type))
;;   (let ((class (find-class 'my-object-type)))
;;     (make-class-info :type 'my-object-type
;;                      :class class
;;		        :slot-names (class-slots class)
;;                      :call-initialize-instance t)))


;; (defmethod initialize-instance :after
;;            ((obj my-object-type &rest initargs &key &allow-other-keys))
;;   ;; do something here to touch up obj
;;   )

(defgeneric serializable-slot-info (object type)
  (:documentation
   "Must return a `slot-info'.  You can configure whether or not
 initialize-instance is called, and whether or not this should be called
 for each object separately. serialize and a second value that
 is T or NIL to specify whether the slot definitions will not vary by object, and
 a third value NIL or T which specifies whether or not we should construct the
 object using make-instance (applies default initargs / initforms) or allocate-instance
 (does not apply default initargs / initforms) respectively.

 If the second value is NIL then this function will be called for every object.

 There a penalty in speed for not returning (value slot-definitions t t)
 which is the default of `standard-object's and `structure-object's.")
  (:method (object type)
    ;; This will be called with standard-object, structure-object, and conditions
    (compute-slot-info object :type type)))

;; We store some meta-information about the structure-object or
;; standard-object We generate and store this once for each object type
;; into *class-info* and also into the output stream.

(defvar *slot-info* nil
  "An eql hash table which maps from structure-object or standard-class type name
 to a `slot-info' structure")

(declaim (inline slot-info-class slot-info-slot-names slot-info-type
		 slot-info-call-initialize-instance make-slot-info))
(defstruct slot-info
  (class (find-class 'structure-object))
  (slot-names #() :type simple-vector)
  (call-initialize-instance nil :type boolean)
  (type 'slot-info :type symbol))

(defun compute-slot-info (obj &key (type (type-of obj)) (call-initialize-info nil))
  (let* ((is-structure-object (typep obj 'structure-object))
	 (store-class-slots *store-class-slots*)
	 (class (find-class type))
	 (slots (class-slots class))
	 (names (coerce		    
		 (loop for slot in slots
		       when (or is-structure-object
				store-class-slots
				(not (eql (slot-definition-allocation slot) :class)))
			 collect (slot-definition-name slot))
		 'simple-vector)))
    (make-slot-info
     :class class
     :type type
     :slot-names names
     :call-initialize-instance call-initialize-info)))

(defun store-slot-info (slot-info storage eq-refs store-object)
  (declare (optimize speed safety) (type slot-info slot-info))
  (maybe-store-reference-instead (slot-info storage eq-refs)
    (let ((slot-names (slot-info-slot-names slot-info)))
      (when storage
	(store-ub8 +slot-info-code+ storage nil)
	(store-unsigned-fixnum (length slot-names) storage)
        (store-boolean (slot-info-call-initialize-instance slot-info) storage))
      (store-symbol (slot-info-type slot-info) storage eq-refs store-object)
      (loop for name across slot-names
	    do (store-symbol name storage eq-refs store-object)))))

(defun restore-slot-info (storage restore-object)
  (declare (optimize speed safety) (type function restore-object))
  (let* ((num-slots (restore-tagged-unsigned-fixnum storage))
         (call-initialize-instance (restore-boolean storage))
         (slot-name-vector (make-array num-slots))
         (si (make-slot-info :call-initialize-instance call-initialize-instance
                             :slot-names slot-name-vector))
         (type (funcall restore-object)))
    (setf (slot-info-type si) type)
    (setf (slot-info-class si) (find-class type))
    ;; No circularity possible below
    (loop for idx fixnum from 0 below num-slots
	  do (setf (svref slot-name-vector idx) (funcall restore-object)))
    si))
	
(defun get-slot-info (object)
  (let ((type (type-of object)))
    (or (gethash type *slot-info*)
	(setf (gethash type *slot-info*)
	      (serializable-slot-info object type)))))

(defun store-struct (struct storage eq-refs store-object)
  (declare (optimize speed safety) (type structure-object struct) (type function store-object))
  (maybe-store-reference-instead (struct storage eq-refs)
    (when storage
      (store-ub8 +structure-object-code+ storage nil))
    (let ((slot-info (get-slot-info struct)))
      (store-slot-info slot-info storage eq-refs store-object)
      (loop for name across (slot-info-slot-names slot-info)
	    do (funcall store-object (slot-value struct name))))))

(defun restore-struct (restore-object)
  (declare (type function restore-object))
  (let* ((slot-info (funcall restore-object))
         (class (slot-info-class slot-info))
	 (struct (if (slot-info-call-initialize-instance slot-info)
                     (make-instance class)
		     (allocate-instance class))))
    (loop for name across (slot-info-slot-names slot-info)
	  do (restore-object-to (slot-value struct name) restore-object))
    struct))

;; We use the same methods as structure-objects, but must deal with unbound slots

(declaim (inline store-unbound))
(defun store-unbound (storage)
  (store-ub8 +unbound-code+ storage nil))

(declaim (inline restore-unbound))
(defun restore-unbound ()
  'unbound-slot)

(defun store-standard-object (obj storage eq-refs store-object)
  (declare (optimize speed safety) (type (or standard-object condition) obj))
  (maybe-store-reference-instead (obj storage eq-refs)
    (when storage
      (store-ub8 +standard-object-code+ storage nil))
    (let ((slot-info (get-slot-info obj)))
      (store-slot-info slot-info storage eq-refs store-object)
      (loop for name across (slot-info-slot-names slot-info)
	    do (if (slot-boundp obj name)
		   (funcall (the function store-object) (slot-value obj name))
		   (when storage (store-unbound storage)))))))

(defun (setf slot-value*) (value object name)
  "Handle internal 'unbound-slot value"
  (if (eq value 'unbound-slot)
      (slot-makunbound object name)
      (setf (slot-value object name) value)))

(defun restore-standard-object (restore-object)
  (declare (optimize speed safety) (type function restore-object))
  (let* ((slot-info (funcall restore-object))
         (class (slot-info-class slot-info))
	 (obj (if (slot-info-call-initialize-instance slot-info)
                     (make-instance class)
		     (allocate-instance class))))
    (map nil (lambda (name)
	       (restore-object-to (slot-value* obj name) restore-object))
	 (slot-info-slot-names slot-info))
    obj))

(defpackage :cl-store-faster-extensions
  (:use :common-lisp :cl-store-faster)
  (:documentation "A package that exports tools used inside cl-store-faster for use by
 someone writing their own specialized serialization or deserialization routine.
 TODO: this isn't right yet :)")
  (:export
   #:register-code

   ;; Complex circularity handling during restore
   #:restore-object-to

   ;; Normal circularity handling
   #:record-reference ; during restore
   #:check/store-reference ; during store

   #:store-boolean
   #:store-t
   #:store-nil
   
   #:store-ub8 ; critically used for writing tag ids
   #:store-ub16
   #:store-ub32
   #:store-fixnum
   #:store-tagged-unsigned-fixnum
   #:store-tagged-unsigned-integer

   #:store-double-float
   #:restore-double-float
   #:restore-double-float-to
   #:store-single-float
   #:restore-single-float
   
   #:store-ratio
   #:restore-ratio
   #:store-bignum
   #:restore-bignum
   #:store-complex
   #:restore-complex
   #:store-complex-single-float
   #:restore-complex-single-float
   #:store-complex-double-float
   #:restore-complex-double-float

   #:store-array
   #:restore-array

   #:store-simple-specialized-array
   #:restore-simple-specialized-array
   #:store-simple-specialized-vector
   #:restore-simple-specialized-vector

   #:store-string
   #:restore-string
   
   #:store-simple-vector
   #:restore-simple-vector

   #:store-standard-object
   #:restore-standard-object
   #:store-structure-object
   #:restore-structure-object

   #:slot-info
   #:slot-info-class
   #:slot-info-slot-names
   #:slot-info-call-initialize-instance
   #:make-slot-info
   #:compute-slot-info
   
   #:ensure-enough-room-to-write
   #:storage-store
   #:storage-offset
   #:storage-max
   #:storage-size

   #:action
   #:action-code

   #:replace-storage
   ))

(in-package :cl-store-faster-extensions)

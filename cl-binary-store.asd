(defsystem #:cl-binary-store
  :version "0.0.2"
  :description "Fast serialization / deserialization library"
  :author "Andrew J. Berkley <ajberkley@gmail.com>"
  :long-name "Fast serialization / deserialization library"
  :pathname "src/"
  :depends-on (#:flexi-streams #:babel #:cl-ppcre)
  :components ((:file "features")
	       (:file "cl-binary-store")
	       (:file "cl-binary-store-user" :depends-on ("cl-binary-store"))
	       (:file "type-discrimination")
	       (:file "storage" :depends-on ("features" "cl-binary-store"))
	       (:file "unsigned-bytes" :depends-on ("storage" "features" "cl-binary-store"))
	       (:file "referrers-and-fixup" :depends-on ("unsigned-bytes" "features"))
	       (:file "defstore" :depends-on ("features"))
	       (:file "reference-tables" :depends-on ("defstore"))
               (:file "codes" :depends-on ("defstore" "reference-tables"))
	       (:file "numbers" :depends-on ("unsigned-bytes" "referrers-and-fixup"
							      "features"))
               (:file "actions" :depends-on ("unsigned-bytes" "storage"))
	       (:file "reference-count" :depends-on ("actions" "numbers"))
               (:file "magic-numbers" :depends-on ("actions" "numbers"))
	       (:file "cons" :depends-on ("referrers-and-fixup" "numbers" "unsigned-bytes"
								"features"))
	       (:file "sbcl-utilities" :if-feature :sbcl :depends-on ("features"))
	       (:file "simple-array-sbcl" :if-feature :sbcl
		:depends-on ("referrers-and-fixup" "numbers" "features"))
	       (:file "simple-vector" :depends-on ("unsigned-bytes" "referrers-and-fixup"
								    "features"))
	       (:file "symbols" :depends-on ("unsigned-bytes" "referrers-and-fixup"
							      "features"))
	       (:file "array" :depends-on ("unsigned-bytes" "cons" "symbols" "numbers"
							    "referrers-and-fixup" "features"))
	       (:file "pathname" :depends-on ("referrers-and-fixup" "symbols" "numbers"
								    "unsigned-bytes" "features"))
	       (:file "hash-table" :depends-on ("referrers-and-fixup" "symbols" "numbers" "unsigned-bytes" "features"))
	       (:file "objects" :depends-on ("symbols" "simple-vector" "referrers-and-fixup" "numbers" "unsigned-bytes" "features"))

	       (:file "dispatch" :depends-on ("codes" "array" "symbols" "simple-vector" "cons"
						      "hash-table" "features" "actions" "magic-numbers"
						      "referrers-and-fixup" "numbers" "pathname"
						      "unsigned-bytes" "objects" "storage"
						      "reference-count" "type-discrimination"))
	       (:file "update-dispatch" :depends-on ("codes" "dispatch"))
	       (:file "user" :depends-on ("dispatch" "storage" "features" "magic-numbers")))
  :license :BSD-3
  :in-order-to ((asdf:test-op (asdf:test-op :cl-binary-store-tests))))

(defsystem #:cl-binary-store-tests
  :description "Unit tests for CL-BINARY-STORE"
  :author "Andrew J. Berkley <ajberkley@gmail.com>"
  :license :BSD-3
  :depends-on (#:parachute)
  :pathname "test/"
  :components ((:file "cl-binary-store-tests"))
  :perform (test-op (o c) (uiop:symbol-call :parachute :test :cl-binary-store-tests)))

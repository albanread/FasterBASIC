' Comprehensive test of object type checking
DIM users AS HASHMAP
DIM scores(5) AS INTEGER
DIM total AS INTEGER

' Array operations
scores(0) = 10
scores(1) = 20
scores(2) = 30

' Hashmap operations
users("alice") = "admin"
users("bob") = "user"
users("charlie") = "guest"

' Mix of operations
total = scores(0) + scores(1) + scores(2)
PRINT "Total:"; total

PRINT "Alice role:"; users("alice")
PRINT "Bob role:"; users("bob")

END

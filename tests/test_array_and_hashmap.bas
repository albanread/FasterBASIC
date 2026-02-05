' Test both arrays and hashmaps together
DIM arr(10) AS INTEGER
DIM dict AS HASHMAP

' Test array
arr(0) = 100
arr(1) = 200
PRINT "Array:"; arr(0); arr(1)

' Test hashmap
dict("x") = "hello"
dict("y") = "world"
PRINT "Hashmap:"; dict("x"); dict("y")

END

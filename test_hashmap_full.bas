DIM contacts AS HASHMAP

contacts("Alice") = "555-1234"
contacts("Bob") = "555-5678"
contacts("Charlie") = "555-9012"

PRINT "Alice's phone: "; contacts("Alice")
PRINT "Bob's phone: "; contacts("Bob")
PRINT "Charlie's phone: "; contacts("Charlie")

contacts("Alice") = "555-0000"
PRINT "Alice's new phone: "; contacts("Alice")

END

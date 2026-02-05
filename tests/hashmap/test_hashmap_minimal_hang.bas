REM Minimal test to reproduce the hang
REM Just 2 hashmaps with 2 keys each

PRINT "Creating first hashmap (contacts)..."
DIM contacts AS HASHMAP

PRINT "Inserting Alice into contacts..."
contacts("Alice") = "alice@example.com"

PRINT "Inserting Bob into contacts..."
contacts("Bob") = "bob@example.com"

PRINT "First hashmap complete!"

PRINT ""
PRINT "Creating second hashmap (scores)..."
DIM scores AS HASHMAP

PRINT "Inserting Alice into scores..."
scores("Alice") = "95"

PRINT "Inserting Bob into scores..."
scores("Bob") = "87"

PRINT "Second hashmap complete!"

PRINT ""
PRINT "✓ Both hashmaps created successfully!"

END

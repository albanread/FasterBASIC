' Minimal test: integer arithmetic inside FUNCTION
FUNCTION Add(a AS INTEGER, b AS INTEGER) AS INTEGER
    Add = a + b
END FUNCTION

PRINT Add(3, 5)

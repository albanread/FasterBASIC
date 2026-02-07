; =========================================================================
; FasterBASIC Tree-sitter Outline Queries for Zed
; Provides code navigation symbols in the outline/symbols panel
; =========================================================================

; -------------------------------------------------------------------------
; Class declarations
; -------------------------------------------------------------------------
(class_declaration
  "CLASS" @context
  name: (_) @name) @item

; -------------------------------------------------------------------------
; Class members
; -------------------------------------------------------------------------
(constructor_declaration
  "CONSTRUCTOR" @context @name) @item

(destructor_declaration
  "DESTRUCTOR" @context @name) @item

(method_declaration
  "METHOD" @context
  name: (_) @name) @item

(field_declaration
  (_) @name
  "AS" @context) @item

; -------------------------------------------------------------------------
; Subroutine declarations
; -------------------------------------------------------------------------
(sub_declaration
  "SUB" @context
  name: (_) @name) @item

; -------------------------------------------------------------------------
; Function declarations
; -------------------------------------------------------------------------
(function_declaration
  "FUNCTION" @context
  name: (_) @name) @item

; -------------------------------------------------------------------------
; DEF FN declarations
; -------------------------------------------------------------------------
(def_fn_statement
  "DEF" @context
  name: (_) @name) @item

; -------------------------------------------------------------------------
; TYPE (UDT) declarations
; -------------------------------------------------------------------------
(type_declaration
  "TYPE" @context
  name: (_) @name) @item

(type_field
  (_) @name
  "AS" @context) @item

; -------------------------------------------------------------------------
; Labels
; -------------------------------------------------------------------------
(label
  (identifier_plain) @name) @item

; -------------------------------------------------------------------------
; Constants
; -------------------------------------------------------------------------
(constant_statement
  "CONSTANT" @context
  (_) @name) @item

(constant_statement
  "CONST" @context
  (_) @name) @item

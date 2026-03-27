module token;


public enum TokenType {
    EOF = "EOF",
    ILLEGAL = "ILLEGAL",

    CONJUNCTION = "CONJUNCTION",
    DISJUNCTION = "DISJUNCTION",
    IMPLICATION = "IMPLICATION",
    BICONDITIONAL = "BICONDITIONAL",
    NEGATION = "NEGATION",
    UNIVERSAL = "UNIVERSAL",
    EXISTENTIAL = "EXISTENTIAL",

    VARIABLE = "VARIABLE",

    LPAREN = "LPAREN",
    RPAREN = "RPAREN",
}

public struct Token {
    TokenType tt;
    dstring literal;

    public string toString() const {
        return "Token[ tt: " ~ cast(string)tt ~ ", literal: " ~ cast(string)literal ~ " ]";
    }
}
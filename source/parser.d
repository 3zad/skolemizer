module parser;

import token;
import model;

import std.stdio;

// order of operations: Negation > Conjunction > Disjunction > Implication > Biconditional
struct Parser {
    Token[] tokens;
    size_t  pos;

    Token peek()    { return tokens[pos]; }
    Token consume() { return tokens[pos++]; }

    bool check(TokenType tt) { return peek().tt == tt; }

    ASTNode* parse() { return parseBiconditional(); }

    ASTNode* parseBiconditional() {
        ASTNode* left = parseImplication();

        if (check(TokenType.BICONDITIONAL)) {
            consume();
            ASTNode* right = parseBiconditional();
            return new ASTNode(NodeType.Biconditional, ""d, left, right);
        }
        return left;
    }

    ASTNode* parseImplication() {
        ASTNode* left = parseDisjunction();

        if (check(TokenType.IMPLICATION)) {
            consume();
            ASTNode* right = parseImplication(); // recurse instead of loop
            return new ASTNode(NodeType.Implication, ""d, left, right);
        }
        return left;
    }

    ASTNode* parseDisjunction() {
        ASTNode* left = parseConjunction();

        while (check(TokenType.DISJUNCTION)) {
            consume();
            ASTNode* right = parseConjunction();
            ASTNode* node  = new ASTNode(NodeType.Disjunction, ""d, left, right);
            left = node;
        }
        return left;
    }

    ASTNode* parseConjunction() {
        ASTNode* left = parseNegation();

        while (check(TokenType.CONJUNCTION)) {
            consume();
            ASTNode* right = parseNegation();
            ASTNode* node  = new ASTNode(NodeType.Conjunction, ""d, left, right);
            left = node;
        }
        return left;
    }

    ASTNode* parsePredicate(dstring name) {
        consume();
        ASTNode*[] args;

        while (!check(TokenType.RPAREN)) {
            Token t = consume();
            args ~= new ASTNode(NodeType.Variable, t.literal, null, null);
            if (check(TokenType.COMMA)) consume();
        }
        consume();

        // Store args as a linked list via left/right, or add an args field to ASTNode
        ASTNode* node = new ASTNode(NodeType.Predicate, name, null, null);
        node.args = args;
        return node;
    }

    ASTNode* parseNegation() {
        if (check(TokenType.NEGATION)) {
            consume();
            ASTNode* operand = parseNegation();
            return new ASTNode(NodeType.Negation, ""d, operand, null);
        }
        return parseQuantifier();
    }

    ASTNode* parseQuantifier() {
        if (check(TokenType.UNIVERSAL) || check(TokenType.EXISTENTIAL)) {
            // just do nothing for now
            consume();
            consume();
            return parseNegation();
        }
        return parsePrimary();
    }

    ASTNode* parsePrimary() {
        if (check(TokenType.LPAREN)) {
            consume();
            ASTNode* inner = parseBiconditional();
            consume();
            return inner;
        }

        Token t = consume();

        if (t.tt == TokenType.VARIABLE) {
            return new ASTNode(NodeType.Variable, t.literal, null, null);
        }

        if (t.tt == TokenType.PREDICATE) {
            if (check(TokenType.LPAREN)) {
                return parsePredicate(t.literal); // has args: P(x,y)
            }
            // bare predicate with no args: P
            ASTNode* node = new ASTNode(NodeType.Predicate, t.literal, null, null);
            node.args = [];
            return node;
        }

        if (t.tt == TokenType.UNIVERSAL || t.tt == TokenType.EXISTENTIAL) {
            dstring variable  = t.literal;
            ASTNode* body     = parseBiconditional();
            NodeType nt       = t.tt == TokenType.UNIVERSAL ? NodeType.Universal : NodeType.Existential;
            return new ASTNode(nt, variable, body, null);
        }

        assert(false, "Unexpected token: " ~ cast(string)t.literal);
    }
}
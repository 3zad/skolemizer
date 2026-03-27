module parser;

import token;
import model;

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

        while (check(TokenType.BICONDITIONAL)) {
            consume();
            ASTNode* right = parseImplication();
            ASTNode* node  = new ASTNode(NodeType.Biconditional, ""d, left, right);
            left = node;
        }
        return left;
    }

    ASTNode* parseImplication() {
        ASTNode* left = parseDisjunction();

        while (check(TokenType.IMPLICATION)) {
            consume();
            ASTNode* right = parseDisjunction();
            ASTNode* node  = new ASTNode(NodeType.Implication, ""d, left, right);
            left = node;
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

    ASTNode* parseNegation() {
        if (check(TokenType.NEGATION)) {
            consume();
            ASTNode* operand = parseNegation();
            return new ASTNode(NodeType.Negation, ""d, operand, null);
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

        if (t.tt == TokenType.VARIABLE || t.tt == TokenType.UNIVERSAL)
            return new ASTNode(NodeType.Variable, t.literal, null, null);

        assert(false, "Unexpected token: " ~ cast(string)t.literal);
    }
}
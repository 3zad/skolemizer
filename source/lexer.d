module lexer;

import token;
import std.bitmanip;
import std.conv;
import std.encoding;
import std.string;
import std.utf;
import std.stdio;

class Lexer {
    dstring formula;
    int position;
    int readPosition;
    int lineNo;
    dchar ch;

    this(string formula)
    {
        this.formula = toUTF32(formula);
        this.position = 0;
        this.readPosition = 0;
        this.lineNo = 1;
        readChar();
    }

    void readChar()
    {
        if (readPosition >= formula.length) {
            ch = '\0';
        } else {
            ch = formula[readPosition];
        }
        position = readPosition;
        readPosition++;
    }

    void skipWhitespace()
    {
        while (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
            if (ch == '\n') {
                lineNo++;
            }
            readChar();
        }
    }

    Token newToken(TokenType tt, dstring literal)
    {
        return Token(tt, literal);
    }

    bool isLetter(dchar ch)
    {
        return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
    }

    dstring readIdentifier()
    {
        int startPosition = position;
        while (isLetter(ch)) {
            readChar();
        }
        return formula[startPosition .. position];
    }

    Token nextToken()
    {
        skipWhitespace();

        Token tok;

        switch (ch) {
            case '\0':
                tok = newToken(TokenType.EOF, "");
                break;
            case '&':
                tok = newToken(TokenType.CONJUNCTION, "&");
                break;
            case '|':
                tok = newToken(TokenType.DISJUNCTION, "|");
                break;
            case '>':
                tok = newToken(TokenType.IMPLICATION, ">");
                break;
            case '=':
                tok = newToken(TokenType.BICONDITIONAL, "=");
                break;
            case '!':
                tok = newToken(TokenType.NEGATION, "!");
                break;
            case 'A':
                tok = newToken(TokenType.UNIVERSAL, "A");
                break;
            case 'E':
                tok = newToken(TokenType.EXISTENTIAL, "E");
                break;
            case '(':
                tok = newToken(TokenType.LPAREN, "(");
                break;
            case ')':
                tok = newToken(TokenType.RPAREN, ")");
                break;
            default:
                if (isLetter(ch)) {
                    dstring literal = readIdentifier();
                    TokenType tt = TokenType.VARIABLE;
                    return newToken(tt, literal);
                } else {
                    tok = newToken(TokenType.ILLEGAL, ch.to!dstring);
                }
        }

        readChar();
        return tok;
    }

    Token[] tokenize()
    {
        Token[] tokens;
        Token tok;
        do {
            tok = nextToken();
            tokens ~= tok;
        } while (tok.tt != TokenType.EOF);
        return tokens;
    }
}
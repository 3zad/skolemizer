module skolemizer.lexer;

import skolemizer.token;
import std.bitmanip;
import std.conv;
import std.encoding;
import std.string;
import std.utf;
import std.stdio;
import std.typecons;

public Token[] tokenize(string formula)
{
    auto lexer = new Lexer(formula);
    return lexer.tokenize();
}

private class Lexer {
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

    bool isLowercaseLetter(dchar ch)
    {
        return (ch >= 'a' && ch <= 'z');
    }

    bool isUppercaseLetter(dchar ch)
    {
        return (ch >= 'A' && ch <= 'Z');
    }

    // returns identifier, type
    Tuple!(dstring, TokenType) readIdentifier()
    {
        int startPosition = position;
        while (isLowercaseLetter(ch)) {
            readChar();
        }

        if (ch == '(') {
            return tuple(formula[startPosition .. position], TokenType.FUNCTION);
        }

        return tuple(formula[startPosition .. position], TokenType.VARIABLE);
    }

    dstring readQuantifierIdentifier()
    {
        int startPosition = position;
        readChar();
        while (isLowercaseLetter(ch) || (ch >= '0' && ch <= '9')) {
            readChar();
        }
        return formula[startPosition+1 .. position];
    }

    dstring readPredicate()
    {
        int startPosition = position;
        while (isUppercaseLetter(ch) || (ch >= '0' && ch <= '9')) {
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
            case '∧':
                tok = newToken(TokenType.CONJUNCTION, "&");
                break;
            case '|':
            case '∨':
                tok = newToken(TokenType.DISJUNCTION, "|");
                break;
            case '>':
            case '→':
            case '⟶':
                tok = newToken(TokenType.IMPLICATION, ">");
                break;
            case '=':
            case '↔':
            case '⟷':
                tok = newToken(TokenType.BICONDITIONAL, "=");
                break;
            case '!':
            case '¬':
            case '~':
                tok = newToken(TokenType.NEGATION, "!");
                break;
            case '(':
            case '[':
                tok = newToken(TokenType.LPAREN, "(");
                break;
            case ')':
            case ']':
                tok = newToken(TokenType.RPAREN, ")");
                break;
            case ',':
                tok = newToken(TokenType.COMMA, ",");
                break;
            default:
                if (isLowercaseLetter(ch)) {
                    auto result = readIdentifier();
                    dstring literal = result[0];
                    TokenType tt = result[1];
                    return newToken(tt, literal);
                } else if (ch == '∃' || ch == '∀') {
                    dchar quantifier = ch;
                    dstring literal = readQuantifierIdentifier();
                    TokenType tt = quantifier == '∃' ? TokenType.EXISTENTIAL : TokenType.UNIVERSAL;
                    return newToken(tt, literal);
                } else if (isUppercaseLetter(ch)) {
                    dstring literal = readPredicate();
                    TokenType tt = TokenType.PREDICATE;
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

unittest {
    Lexer lexer = new Lexer("∀x (P(x) > ∃y Q(y))");
    auto tokens = lexer.tokenize();
    assert(tokens[0].tt == TokenType.UNIVERSAL && tokens[0].literal == "x");
    assert(tokens[1].tt == TokenType.LPAREN && tokens[1].literal == "(");
    assert(tokens[2].tt == TokenType.PREDICATE && tokens[2].literal == "P");
    assert(tokens[3].tt == TokenType.LPAREN && tokens[3].literal == "(");
    assert(tokens[4].tt == TokenType.VARIABLE && tokens[4].literal == "x");
    assert(tokens[5].tt == TokenType.RPAREN && tokens[5].literal == ")");
    assert(tokens[6].tt == TokenType.IMPLICATION && tokens[6].literal == ">");
    assert(tokens[7].tt == TokenType.EXISTENTIAL && tokens[7].literal == "y");
    assert(tokens[8].tt == TokenType.PREDICATE && tokens[8].literal == "Q");
    assert(tokens[9].tt == TokenType.LPAREN && tokens[9].literal == "(");
    assert(tokens[10].tt == TokenType.VARIABLE && tokens[10].literal == "y");
    assert(tokens[11].tt == TokenType.RPAREN && tokens[11].literal == ")");
    assert(tokens[12].tt == TokenType.RPAREN && tokens[12].literal == ")");

    Lexer lexer2 = new Lexer("a > b > a");
    auto tokens2 = lexer2.tokenize();
    assert(tokens2[0].tt == TokenType.VARIABLE && tokens2[0].literal == "a");
    assert(tokens2[1].tt == TokenType.IMPLICATION && tokens2[1].literal == ">");
    assert(tokens2[2].tt == TokenType.VARIABLE && tokens2[2].literal == "b");
    assert(tokens2[3].tt == TokenType.IMPLICATION && tokens2[3].literal == ">");
    assert(tokens2[4].tt == TokenType.VARIABLE && tokens2[4].literal == "a");
}
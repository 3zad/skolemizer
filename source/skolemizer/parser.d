module skolemizer.parser;

import skolemizer.token;
import skolemizer.model;

import std.stdio;
import std.file;
import std.string;
import std.algorithm.searching;

public ASTNode* parse(Token[] tokens) {
    auto parser = Parser(tokens);
    return parser.parse();
}

// order of operations: Negation > Conjunction > Disjunction > Implication > Biconditional
private struct Parser {
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

            // rewrite to skip the double implication step
            ASTNode* notLeft  = new ASTNode(NodeType.Negation, ""d, left,  null);
            ASTNode* notRight = new ASTNode(NodeType.Negation, ""d, right, null);
            ASTNode* disj1    = new ASTNode(NodeType.Disjunction, ""d, notLeft,  right);
            ASTNode* disj2    = new ASTNode(NodeType.Disjunction, ""d, notRight, left);
            return new ASTNode(NodeType.Conjunction, ""d, disj1, disj2);
        }
        return left;
    }

    ASTNode* parseImplication() {
        ASTNode* left = parseDisjunction();

        if (check(TokenType.IMPLICATION)) {
            consume();
            ASTNode* right = parseImplication();
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
            if (check(TokenType.LPAREN)) {
                args ~= parseFunction(t.literal);
            } else {
                args ~= parseVariable(t.literal);
            }
            if (check(TokenType.COMMA)) consume();
        }
        consume(); // RPAREN

        ASTNode* node = new ASTNode(NodeType.Predicate, name, null, null);
        node.args = args;
        return node;
    }

    ASTNode* parseFunction(dstring name) {
        consume();
        ASTNode*[] args;

        while (!check(TokenType.RPAREN)) {
            Token t = consume();
            if (check(TokenType.LPAREN)) {
                args ~= parseFunction(t.literal);
            } else {
                args ~= parseVariable(t.literal);
            }
            if (check(TokenType.COMMA)) consume();
        }
        consume();

        ASTNode* node = new ASTNode(NodeType.Function, name, null, null);
        node.args = args;
        return node;
    }

    ASTNode* parseVariable(dstring name) {
        return new ASTNode(NodeType.Variable, name, null, null);
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
        if (check(TokenType.UNIVERSAL)) {
            Token t = consume();
            ASTNode* inner = parseNegation();
            return new ASTNode(NodeType.Universal, t.literal, inner, null);
        } else if (check(TokenType.EXISTENTIAL)) {
            Token t = consume();
            ASTNode* inner = parseNegation();
            return new ASTNode(NodeType.Existential, t.literal, inner, null);
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

        if (t.tt == TokenType.PREDICATE) {
            if (check(TokenType.LPAREN)) {
                return parsePredicate(t.literal); // has args: P(x,y)
            }
            throw new Exception("Unexpected predicate token without '(': " ~ cast(string)t.literal);
        }

        if (t.tt == TokenType.FUNCTION) {
            if (check(TokenType.LPAREN)) {
                return parseFunction(t.literal); // has args: f(x,y)
            }
            throw new Exception("Unexpected function token without '(': " ~ cast(string)t.literal);
        }

        if (t.tt == TokenType.VARIABLE) {
            return parseVariable(t.literal);
        }

        assert(false, "Unexpected token: " ~ cast(string)t.literal);
    }
}

/// Convert AST to a human-readable formula string
dstring toFormulaString(ASTNode* node, dstring result = "")
{
	if (node is null) {
		return "";
	}

	if (node.type == NodeType.Conjunction || node.type == NodeType.Disjunction || 
		node.type == NodeType.Implication || node.type == NodeType.Biconditional) {
		
		result ~= "(";
		result ~= toFormulaString(node.left);
		switch (node.type)
		{
			case NodeType.Conjunction:  result ~= " & "; break;
			case NodeType.Disjunction:  result ~= " ∨ "; break;
			case NodeType.Implication:  result ~= " ⟶ "; break;
			case NodeType.Biconditional: result ~= " ⟷ "; break;
			default: break;
		}
		result ~= toFormulaString(node.right);
		result ~= ")";
	} else {
        bool leftOnly = false;
		switch (node.type)
		{
			case NodeType.Negation:
				result ~= " ¬"d;
                leftOnly = true;
				break;
			case NodeType.Universal:
				result ~= "∀"d~node.value;
                leftOnly = true;
				break;
			case NodeType.Existential:
				result ~= "∃"d~node.value;
                leftOnly = true;
				break;
			case NodeType.Variable:
				result ~= node.value;
				break;
			case NodeType.Predicate:
				dstring argsStr;
				foreach (arg; node.args) {
					argsStr ~= toFormulaString(arg) ~ ", ";
				}
				// remove trailing comma and space
				if (argsStr.length >= 2) {
					argsStr = argsStr[0 .. $ - 2];
				}
				result ~= node.value ~ "(" ~ argsStr ~ ")";
				break;
			case NodeType.SkolemFunction:
				dstring skolemArgsStr;
				foreach (arg; node.args) {
					skolemArgsStr ~= toFormulaString(arg) ~ ", ";
				}
				// remove trailing comma and space
				if (skolemArgsStr.length >= 2) {
					skolemArgsStr = skolemArgsStr[0 .. $ - 2];
				}
				result ~= node.value ~ "(" ~ skolemArgsStr ~ ")";
				break;
			case NodeType.Function:
				dstring funcArgsStr;
				foreach (arg; node.args) {
					funcArgsStr ~= toFormulaString(arg) ~ ", ";
				}
				if (funcArgsStr.length >= 2) {
					funcArgsStr = funcArgsStr[0 .. $ - 2];
				}
				result ~= node.value ~ "(" ~ funcArgsStr ~ ")";
				break;
			default:
				break;
		}
        result ~= toFormulaString(node.left);
		if (!leftOnly) {
			result ~= toFormulaString(node.right);
		}
	}

	if (result.length < 2) {
		return result;
	}

	// remove leading and trailing parenthesis
	int depth = 0;
	while (result[depth] == '(')
	{
		depth++;
	}

	result = result[depth..result.length-depth];

	// remove all double spaces
	while (result.canFind("  "d))
	{
		result = result.replace("  "d, " "d);
	}

	// remove trailing and tailing spaces
	result = result.strip();

	return result;
}

/// Write AST to a file with indentation
public void writeToFile(string filename, ASTNode* node)
{
	auto file = File(filename, "w");
	scope(exit) file.close();
	string content = node.toString();
	int depth = 0;
	char prev = '\0';
	foreach (c; content) {
		if (prev == '[') {
			depth++;
			file.write('\n');
			for (int i = 0; i < depth; i++) {
				file.write("\t");
			}
		} else if (c == ']') {
			depth--;
			file.write('\n');
			for (int i = 0; i < depth; i++) {
				file.write("\t");
			}
		}
		file.write(c);
		prev = c;
	}
}

unittest {
    // todo
}